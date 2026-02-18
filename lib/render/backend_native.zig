const DepthTarget = struct {
    texture: *wgpu.Texture,
    view: *wgpu.TextureView,
};

const depth_format = wgpu.TextureFormat.depth24_plus;

pub const RendererConfig = struct {
    present_mode: ?wgpu.PresentMode = null,
    enable_validation: bool = false,
};

pub fn configForVsync(vsync: bool) RendererConfig {
    return .{ .present_mode = if (vsync) .fifo else .immediate };
}

pub const Buffer = struct {
    buffer: *wgpu.Buffer,
    size: u64,
};

pub const Texture = struct {
    texture: *wgpu.Texture,
    view: *wgpu.TextureView,
    width: u32,
    height: u32,
    format: wgpu.TextureFormat,
};

pub const Sampler = struct {
    sampler: *wgpu.Sampler,
};

pub const Pipeline = struct {
    pipeline: *wgpu.RenderPipeline,
};

pub const Shader = struct {
    pipeline_opaque: *wgpu.RenderPipeline,
    pipeline_blend: *wgpu.RenderPipeline,
};

pub const Material = struct {
    bind_group: *wgpu.BindGroup,
};

pub const ShaderSource = struct {
    wgsl: ?[]const u8 = null,
    glsl_vertex: ?[]const u8 = null,
    glsl_fragment: ?[]const u8 = null,
};

pub const MeshVertexLayout = enum(u8) {
    uv2,
    pos3_color4,
};

pub const Mesh = struct {
    vertex_buffer: Buffer,
    index_buffer: Buffer,
    index_count: u32,
    vertex_layout: MeshVertexLayout,
};

pub const max_instances_per_draw: usize = 6000;

pub const RendererStats = extern struct {
    meshes_alive: u32 = 0,
    meshes_slots: u32 = 0,
    meshes_free: u32 = 0,
    textures_alive: u32 = 0,
    textures_slots: u32 = 0,
    materials_alive: u32 = 0,
    materials_slots: u32 = 0,
    samplers_alive: u32 = 0,
    samplers_slots: u32 = 0,
};

pub const MeshInstance = extern struct {
    transform: common.Mat4 = common.Mat4.identity(),
    color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
};

pub const VertexColor = extern struct {
    position: [2]f32,
    color: [3]f32,
};

pub const VertexUv = extern struct {
    position: [2]f32,
    uv: [2]f32,
};

pub const VertexPos3Color = extern struct {
    position: [3]f32,
    color: [4]f32,
};

pub const Triangle = struct {
    vertices: [3]VertexColor,
};

pub const TexturedQuad = struct {
    mesh: Mesh,
    material: Material,
    instance: MeshInstance,
    blend: bool = false,
};

pub const DrawCmd = union(enum) {
    triangle: Triangle,
    textured_quad: TexturedQuad,
};

const InstanceData = extern struct {
    model0: [4]f32,
    model1: [4]f32,
    model2: [4]f32,
    model3: [4]f32,
    color: [4]f32,
};

const PipelineCache = struct {
    map: std.AutoHashMap(u64, *wgpu.RenderPipeline),

    fn init(allocator: std.mem.Allocator) PipelineCache {
        return .{ .map = std.AutoHashMap(u64, *wgpu.RenderPipeline).init(allocator) };
    }

    fn deinit(self: *PipelineCache) void {
        self.map.deinit();
    }
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    instance: *wgpu.Instance,
    surface: *wgpu.Surface,
    adapter: *wgpu.Adapter,
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    surface_format: wgpu.TextureFormat,
    surface_size: Size,
    present_mode: wgpu.PresentMode,

    triangle_pipeline: *wgpu.RenderPipeline,
    quad_pipeline_opaque: *wgpu.RenderPipeline,
    quad_pipeline_blend: *wgpu.RenderPipeline,
    quad_bind_group_layout: *wgpu.BindGroupLayout,

    triangle_vertex_buffer: Buffer,
    quad_vertex_buffer: Buffer,
    quad_index_buffer: Buffer,
    instance_buffer: Buffer,
    instance_ring: RingBuffer,
    depth_target: DepthTarget,

    pipeline_cache: PipelineCache,

    pub fn init(allocator: std.mem.Allocator, target: SurfaceTarget, config: RendererConfig) !Renderer {
        if (target != .native) return error.InvalidSurfaceTarget;
        const native = target.native;

        const instance = createInstance(config.enable_validation) orelse return error.InstanceCreationFailed;
        errdefer instance.release();

        const surface = try createSurface(instance, native);
        errdefer surface.release();

        const adapter = try requestAdapter(instance, surface);
        errdefer adapter.release();

        const device = try requestDevice(instance, adapter);
        errdefer device.release();

        const queue = device.getQueue() orelse return error.QueueCreationFailed;
        errdefer queue.release();

        const capabilities = try getSurfaceCapabilities(surface, adapter);
        defer capabilities.freeMembers();
        const surface_format = selectSurfaceFormat(capabilities);
        if (config.present_mode) |requested| {
            const modes = capabilities.present_modes[0..capabilities.present_mode_count];
            var supported = false;
            for (modes) |mode| {
                if (mode == requested) {
                    supported = true;
                    break;
                }
            }
            if (!supported) {
                std.log.warn("Requested present mode {s} not supported; falling back", .{@tagName(requested)});
            }
        }
        const present_mode = selectPresentMode(capabilities, config.present_mode);
        std.log.info("Renderer present mode: {s}", .{@tagName(present_mode)});

        const surface_size = native.size;
        configureSurface(device, surface, surface_format, surface_size.width, surface_size.height, present_mode);

        const pipeline_cache = PipelineCache.init(allocator);

        var renderer = Renderer{
            .allocator = allocator,
            .instance = instance,
            .surface = surface,
            .adapter = adapter,
            .device = device,
            .queue = queue,
            .surface_format = surface_format,
            .surface_size = surface_size,
            .present_mode = present_mode,
            .triangle_pipeline = undefined,
            .quad_pipeline_opaque = undefined,
            .quad_pipeline_blend = undefined,
            .quad_bind_group_layout = undefined,
            .triangle_vertex_buffer = undefined,
            .quad_vertex_buffer = undefined,
            .quad_index_buffer = undefined,
            .instance_buffer = undefined,
            .instance_ring = RingBuffer.init(512 * 1024),
            .depth_target = undefined,
            .pipeline_cache = pipeline_cache,
        };

        try renderer.initResources();
        return renderer;
    }

    fn initResources(self: *Renderer) !void {
        self.triangle_vertex_buffer = try createBufferWithData(
            self.allocator,
            self.device,
            self.queue,
            wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
            std.mem.asBytes(&defaultTriangleVertices),
        );

        self.quad_vertex_buffer = try createBufferWithData(
            self.allocator,
            self.device,
            self.queue,
            wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
            std.mem.asBytes(&defaultQuadVertices),
        );
        self.quad_index_buffer = try createBufferWithData(
            self.allocator,
            self.device,
            self.queue,
            wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
            std.mem.asBytes(&defaultQuadIndices),
        );

        self.instance_buffer = try createEmptyBuffer(
            self.device,
            wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
            self.instance_ring.size,
        );

        self.depth_target = try createDepthTarget(self.device, self.surface_size.width, self.surface_size.height);

        const shader_triangle = self.device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
            .code = triangleShaderWGSL,
        })) orelse return error.ShaderCreationFailed;
        defer shader_triangle.release();

        const shader_quad = self.device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
            .code = quadShaderWGSL,
        })) orelse return error.ShaderCreationFailed;
        defer shader_quad.release();

        const triangle_key = CacheKey{ .a = 1, .b = 0, .c = 0 };
        _ = hashCacheKey(triangle_key);
        self.triangle_pipeline = try createTrianglePipeline(self.device, shader_triangle, self.surface_format, depth_format);

        const quad_key = CacheKey{ .a = 2, .b = 0, .c = 0 };
        _ = hashCacheKey(quad_key);
        const quad_bind_group_layout = try createQuadBindGroupLayout(self.device);
        self.quad_bind_group_layout = quad_bind_group_layout;
        self.quad_pipeline_opaque = try createQuadPipeline(
            self.device,
            shader_quad,
            self.surface_format,
            depth_format,
            quad_bind_group_layout,
            false,
            true,
        );
        self.quad_pipeline_blend = try createQuadPipeline(
            self.device,
            shader_quad,
            self.surface_format,
            depth_format,
            quad_bind_group_layout,
            true,
            false,
        );
    }

    pub fn deinit(self: *Renderer) void {
        self.triangle_pipeline.release();
        self.quad_pipeline_opaque.release();
        self.quad_pipeline_blend.release();
        self.quad_bind_group_layout.release();

        self.triangle_vertex_buffer.buffer.release();
        self.quad_vertex_buffer.buffer.release();
        self.quad_index_buffer.buffer.release();
        self.instance_buffer.buffer.release();
        self.depth_target.view.release();
        self.depth_target.texture.release();

        self.pipeline_cache.deinit();

        self.queue.release();
        self.device.release();
        self.adapter.release();
        self.surface.release();
        self.instance.release();
    }

    pub fn resize(self: *Renderer, width: u32, height: u32) void {
        if (width == 0 or height == 0) return;
        self.surface_size = .{ .width = width, .height = height };
        configureSurface(self.device, self.surface, self.surface_format, width, height, self.present_mode);
        const new_depth = createDepthTarget(self.device, width, height) catch return;
        self.depth_target.view.release();
        self.depth_target.texture.release();
        self.depth_target = new_depth;
    }

    pub fn beginFrame(self: *Renderer, clear: Color) !Frame {
        const clear_f = Color.F32.fromColor(clear);
        self.instance_ring.reset();
        var surface_texture: wgpu.SurfaceTexture = undefined;
        self.surface.getCurrentTexture(&surface_texture);
        if (surface_texture.status != .success_optimal and surface_texture.status != .success_suboptimal) {
            return error.SurfaceTextureError;
        }
        const texture = surface_texture.texture orelse return error.SurfaceTextureError;
        const view = texture.createView(&wgpu.TextureViewDescriptor{}) orelse return error.SurfaceTextureError;

        const encoder = self.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = wgpu.StringView.fromSlice("phasor-lite encoder"),
        }) orelse return error.CommandEncoderFailed;

        const color_attachment = wgpu.ColorAttachment{
            .view = view,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = wgpu.Color{
                .r = clear_f.r,
                .g = clear_f.g,
                .b = clear_f.b,
                .a = clear_f.a,
            },
        };
        const depth_attachment = wgpu.DepthStencilAttachment{
            .view = self.depth_target.view,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .depth_clear_value = 1.0,
        };
        const attachments = [_]wgpu.ColorAttachment{color_attachment};
        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .color_attachment_count = attachments.len,
            .color_attachments = attachments[0..].ptr,
            .depth_stencil_attachment = &depth_attachment,
        }) orelse return error.RenderPassFailed;

        return Frame{
            .renderer = self,
            .encoder = encoder,
            .render_pass = render_pass,
            .surface_texture = surface_texture,
            .view = view,
        };
    }

    pub fn createSampler(self: *Renderer) !Sampler {
        const sampler = self.device.createSampler(&wgpu.SamplerDescriptor{
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_filter = .linear,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
        }) orelse return error.SamplerCreationFailed;
        return Sampler{ .sampler = sampler };
    }

    pub fn createTextureRgba8(self: *Renderer, width: u32, height: u32, data: []const u8) !Texture {
        const texture = self.device.createTexture(&wgpu.TextureDescriptor{
            .size = .{ .width = width, .height = height, .depth_or_array_layers = 1 },
            .format = .rgba8_unorm_srgb,
            .usage = wgpu.TextureUsages.texture_binding | wgpu.TextureUsages.copy_dst,
            .mip_level_count = 1,
            .sample_count = 1,
            .dimension = .@"2d",
        }) orelse return error.TextureCreationFailed;
        errdefer texture.release();

        const view = texture.createView(&wgpu.TextureViewDescriptor{}) orelse return error.TextureViewFailed;
        errdefer view.release();

        const bytes_per_row = width * 4;
        const aligned_bpr = std.mem.alignForward(u32, bytes_per_row, 256);
        var upload = data;
        var scratch: ?[]u8 = null;
        if (aligned_bpr != bytes_per_row) {
            const total = aligned_bpr * height;
            const padded = try self.allocator.alloc(u8, total);
            @memset(padded, 0);
            for (0..height) |row| {
                const src_off = row * bytes_per_row;
                const dst_off = row * aligned_bpr;
                std.mem.copyForwards(u8, padded[dst_off..][0..bytes_per_row], data[src_off..][0..bytes_per_row]);
            }
            scratch = padded;
            upload = padded;
        }
        defer if (scratch) |padded| self.allocator.free(padded);

        const layout = wgpu.TexelCopyBufferLayout{
            .bytes_per_row = aligned_bpr,
            .rows_per_image = height,
        };
        const dst = wgpu.TexelCopyTextureInfo{
            .texture = texture,
            .origin = .{},
            .mip_level = 0,
            .aspect = .all,
        };
        const copy_size = wgpu.Extent3D{
            .width = width,
            .height = height,
            .depth_or_array_layers = 1,
        };
        self.queue.writeTexture(&dst, upload.ptr, upload.len, &layout, &copy_size);

        return Texture{
            .texture = texture,
            .view = view,
            .width = width,
            .height = height,
            .format = .rgba8_unorm_srgb,
        };
    }

    pub fn destroyTexture(_: *Renderer, texture: *Texture) void {
        texture.view.release();
        texture.texture.release();
    }

    pub fn destroySampler(_: *Renderer, sampler: *Sampler) void {
        sampler.sampler.release();
    }

    pub fn createMaterial(self: *Renderer, texture: Texture, sampler: Sampler) !Material {
        const entries = [_]wgpu.BindGroupEntry{
            .{ .binding = 0, .sampler = sampler.sampler },
            .{ .binding = 1, .texture_view = texture.view },
        };
        const bind_group = self.device.createBindGroup(&wgpu.BindGroupDescriptor{
            .layout = self.quad_bind_group_layout,
            .entry_count = entries.len,
            .entries = entries[0..].ptr,
        }) orelse return error.BindGroupCreationFailed;
        return Material{ .bind_group = bind_group };
    }

    pub fn destroyMaterial(_: *Renderer, material: *Material) void {
        material.bind_group.release();
    }

    pub fn createMeshUv(self: *Renderer, vertices: []const VertexUv, indices: []const u16) !Mesh {
        const vertex_buf = try createBufferWithData(
            self.allocator,
            self.device,
            self.queue,
            wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
            std.mem.sliceAsBytes(vertices),
        );
        const index_buf = try createBufferWithData(
            self.allocator,
            self.device,
            self.queue,
            wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
            std.mem.sliceAsBytes(indices),
        );
        return Mesh{
            .vertex_buffer = vertex_buf,
            .index_buffer = index_buf,
            .index_count = @intCast(indices.len),
            .vertex_layout = .uv2,
        };
    }

    pub fn updateMeshUv(self: *Renderer, mesh: *Mesh, vertices: []const VertexUv, indices: []const u16) !void {
        if (mesh.vertex_layout != .uv2) return error.InvalidMeshLayout;
        const vertex_bytes = std.mem.sliceAsBytes(vertices);
        const index_bytes = std.mem.sliceAsBytes(indices);
        if (vertex_bytes.len > mesh.vertex_buffer.size or index_bytes.len > mesh.index_buffer.size) {
            mesh.vertex_buffer.buffer.release();
            mesh.index_buffer.buffer.release();
            mesh.vertex_buffer = try createBufferWithData(
                self.allocator,
                self.device,
                self.queue,
                wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
                vertex_bytes,
            );
            mesh.index_buffer = try createBufferWithData(
                self.allocator,
                self.device,
                self.queue,
                wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
                index_bytes,
            );
        } else {
            self.queue.writeBuffer(mesh.vertex_buffer.buffer, 0, vertex_bytes.ptr, vertex_bytes.len);
            self.queue.writeBuffer(mesh.index_buffer.buffer, 0, index_bytes.ptr, index_bytes.len);
        }
        mesh.index_count = @intCast(indices.len);
    }

    pub fn createMeshPos3Color(self: *Renderer, vertices: []const VertexPos3Color, indices: []const u16) !Mesh {
        const vertex_buf = try createBufferWithData(
            self.allocator,
            self.device,
            self.queue,
            wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
            std.mem.sliceAsBytes(vertices),
        );
        const index_buf = try createBufferWithData(
            self.allocator,
            self.device,
            self.queue,
            wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
            std.mem.sliceAsBytes(indices),
        );
        return Mesh{
            .vertex_buffer = vertex_buf,
            .index_buffer = index_buf,
            .index_count = @intCast(indices.len),
            .vertex_layout = .pos3_color4,
        };
    }

    pub fn updateMeshPos3Color(self: *Renderer, mesh: *Mesh, vertices: []const VertexPos3Color, indices: []const u16) !void {
        if (mesh.vertex_layout != .pos3_color4) return error.InvalidMeshLayout;
        const vertex_bytes = std.mem.sliceAsBytes(vertices);
        const index_bytes = std.mem.sliceAsBytes(indices);
        if (vertex_bytes.len > mesh.vertex_buffer.size or index_bytes.len > mesh.index_buffer.size) {
            mesh.vertex_buffer.buffer.release();
            mesh.index_buffer.buffer.release();
            mesh.vertex_buffer = try createBufferWithData(
                self.allocator,
                self.device,
                self.queue,
                wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
                vertex_bytes,
            );
            mesh.index_buffer = try createBufferWithData(
                self.allocator,
                self.device,
                self.queue,
                wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
                index_bytes,
            );
        } else {
            self.queue.writeBuffer(mesh.vertex_buffer.buffer, 0, vertex_bytes.ptr, vertex_bytes.len);
            self.queue.writeBuffer(mesh.index_buffer.buffer, 0, index_bytes.ptr, index_bytes.len);
        }
        mesh.index_count = @intCast(indices.len);
    }

    pub fn destroyMesh(_: *Renderer, mesh: *Mesh) void {
        mesh.vertex_buffer.buffer.release();
        mesh.index_buffer.buffer.release();
    }

    pub fn createShader(self: *Renderer, source: ShaderSource) !Shader {
        const shader_vertex = try createShaderModule(self.device, .vertex, source);
        defer shader_vertex.release();
        const shader_fragment = try createShaderModule(self.device, .fragment, source);
        defer shader_fragment.release();

        return Shader{
            .pipeline_opaque = try createColorPipeline(
                self.device,
                shader_vertex,
                shader_fragment,
                self.surface_format,
                depth_format,
                false,
                true,
            ),
            .pipeline_blend = try createColorPipeline(
                self.device,
                shader_vertex,
                shader_fragment,
                self.surface_format,
                depth_format,
                true,
                false,
            ),
        };
    }

    pub fn destroyShader(_: *Renderer, shader: *Shader) void {
        shader.pipeline_opaque.release();
        shader.pipeline_blend.release();
    }

    pub fn stats(_: *const Renderer) RendererStats {
        return .{};
    }
};

pub const Frame = struct {
    renderer: *Renderer,
    encoder: *wgpu.CommandEncoder,
    render_pass: *wgpu.RenderPassEncoder,
    surface_texture: wgpu.SurfaceTexture,
    view: *wgpu.TextureView,

    pub fn draw(self: *Frame, cmd: DrawCmd) void {
        switch (cmd) {
            .triangle => |triangle| self.drawTriangle(triangle),
            .textured_quad => |quad| self.drawTexturedQuad(quad),
        }
    }

    fn drawTriangle(self: *Frame, triangle: Triangle) void {
        const data = std.mem.asBytes(&triangle.vertices);
        self.renderer.queue.writeBuffer(self.renderer.triangle_vertex_buffer.buffer, 0, data.ptr, data.len);
        self.render_pass.setPipeline(self.renderer.triangle_pipeline);
        self.render_pass.setVertexBuffer(0, self.renderer.triangle_vertex_buffer.buffer, 0, self.renderer.triangle_vertex_buffer.size);
        self.render_pass.draw(3, 1, 0, 0);
    }

    fn drawTexturedQuad(self: *Frame, quad: TexturedQuad) void {
        if (quad.mesh.vertex_layout != .uv2) return;
        const instance = buildInstanceData(quad.instance);
        const instance_bytes = std.mem.asBytes(&instance);
        const offset = self.renderer.instance_ring.allocate(@sizeOf(InstanceData), 256);
        self.renderer.queue.writeBuffer(self.renderer.instance_buffer.buffer, offset, instance_bytes.ptr, instance_bytes.len);

        const pipeline = if (quad.blend) self.renderer.quad_pipeline_blend else self.renderer.quad_pipeline_opaque;
        self.render_pass.setPipeline(pipeline);
        self.render_pass.setBindGroup(0, quad.material.bind_group, 0, null);
        self.render_pass.setVertexBuffer(0, quad.mesh.vertex_buffer.buffer, 0, quad.mesh.vertex_buffer.size);
        self.render_pass.setVertexBuffer(1, self.renderer.instance_buffer.buffer, offset, @sizeOf(InstanceData));
        self.render_pass.setIndexBuffer(quad.mesh.index_buffer.buffer, .uint16, 0, quad.mesh.index_buffer.size);
        self.render_pass.drawIndexed(quad.mesh.index_count, 1, 0, 0, 0);
    }

    pub fn drawTexturedQuads(self: *Frame, mesh: Mesh, material: Material, instances: []const MeshInstance, blend: bool) void {
        if (mesh.vertex_layout != .uv2) return;
        if (instances.len == 0) return;
        const total_bytes: usize = instances.len * @sizeOf(InstanceData);
        const offset = self.renderer.instance_ring.allocate(total_bytes, 256);

        var i: usize = 0;
        while (i < instances.len) : (i += 1) {
            const data = buildInstanceData(instances[i]);
            const bytes = std.mem.asBytes(&data);
            const byte_offset = offset + i * @sizeOf(InstanceData);
            self.renderer.queue.writeBuffer(self.renderer.instance_buffer.buffer, byte_offset, bytes.ptr, bytes.len);
        }

        const pipeline = if (blend) self.renderer.quad_pipeline_blend else self.renderer.quad_pipeline_opaque;
        self.render_pass.setPipeline(pipeline);
        self.render_pass.setBindGroup(0, material.bind_group, 0, null);
        self.render_pass.setVertexBuffer(0, mesh.vertex_buffer.buffer, 0, mesh.vertex_buffer.size);
        self.render_pass.setVertexBuffer(1, self.renderer.instance_buffer.buffer, offset, total_bytes);
        self.render_pass.setIndexBuffer(mesh.index_buffer.buffer, .uint16, 0, mesh.index_buffer.size);
        self.render_pass.drawIndexed(mesh.index_count, @intCast(instances.len), 0, 0, 0);
    }

    pub fn drawColoredMeshes(self: *Frame, mesh: Mesh, shader: Shader, instances: []const MeshInstance, blend: bool) void {
        if (mesh.vertex_layout != .pos3_color4) return;
        if (instances.len == 0) return;
        const total_bytes: usize = instances.len * @sizeOf(InstanceData);
        const offset = self.renderer.instance_ring.allocate(total_bytes, 256);

        var i: usize = 0;
        while (i < instances.len) : (i += 1) {
            const data = buildInstanceData(instances[i]);
            const bytes = std.mem.asBytes(&data);
            const byte_offset = offset + i * @sizeOf(InstanceData);
            self.renderer.queue.writeBuffer(self.renderer.instance_buffer.buffer, byte_offset, bytes.ptr, bytes.len);
        }

        const pipeline = if (blend) shader.pipeline_blend else shader.pipeline_opaque;
        self.render_pass.setPipeline(pipeline);
        self.render_pass.setVertexBuffer(0, mesh.vertex_buffer.buffer, 0, mesh.vertex_buffer.size);
        self.render_pass.setVertexBuffer(1, self.renderer.instance_buffer.buffer, offset, total_bytes);
        self.render_pass.setIndexBuffer(mesh.index_buffer.buffer, .uint16, 0, mesh.index_buffer.size);
        self.render_pass.drawIndexed(mesh.index_count, @intCast(instances.len), 0, 0, 0);
    }

    pub fn endFrame(self: *Frame) !void {
        self.render_pass.end();
        self.render_pass.release();

        const command_buffer = self.encoder.finish(&wgpu.CommandBufferDescriptor{}) orelse return error.CommandBufferFailed;
        defer command_buffer.release();
        self.renderer.queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});

        _ = self.renderer.surface.present();
        self.view.release();
        if (self.surface_texture.texture) |texture| {
            texture.release();
        }
        self.encoder.release();
    }
};

fn buildInstanceData(instance: MeshInstance) InstanceData {
    const m = instance.transform.m;
    return .{
        .model0 = .{ m[0][0], m[0][1], m[0][2], m[0][3] },
        .model1 = .{ m[1][0], m[1][1], m[1][2], m[1][3] },
        .model2 = .{ m[2][0], m[2][1], m[2][2], m[2][3] },
        .model3 = .{ m[3][0], m[3][1], m[3][2], m[3][3] },
        .color = instance.color,
    };
}

fn createInstance(enable_validation: bool) ?*wgpu.Instance {
    var extras = wgpu.InstanceExtras{
        .backends = wgpu.InstanceBackends.primary,
        .flags = if (enable_validation) wgpu.InstanceFlags.validation else wgpu.InstanceFlags.default,
        .dx12_shader_compiler = .dxc,
        .gles3_minor_version = .automatic,
        .gl_fence_behavior = .gl_fence_behaviour_normal,
        .dxil_path = wgpu.StringView{},
        .dxc_path = wgpu.StringView{},
        .dxc_max_shader_model = .dxc_max_shader_model_v6_0,
    };
    const descriptor = (wgpu.InstanceDescriptor{
        .features = wgpu.InstanceCapabilities{
            .timed_wait_any_enable = @intFromBool(false),
            .timed_wait_any_max_count = 0,
        },
    }).withNativeExtras(&extras);
    return wgpu.Instance.create(&descriptor);
}

fn requestAdapter(instance: *wgpu.Instance, surface: *wgpu.Surface) !*wgpu.Adapter {
    const request = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{
        .compatible_surface = surface,
        .power_preference = .high_performance,
    }, 0);
    return switch (request.status) {
        .success => request.adapter orelse error.AdapterFailed,
        else => error.AdapterFailed,
    };
}

fn requestDevice(instance: *wgpu.Instance, adapter: *wgpu.Adapter) !*wgpu.Device {
    const request = adapter.requestDeviceSync(instance, &wgpu.DeviceDescriptor{
        .required_feature_count = 0,
        .required_features = &[_]wgpu.FeatureName{},
        .required_limits = null,
        .default_queue = wgpu.QueueDescriptor{},
    }, 0);
    return switch (request.status) {
        .success => request.device orelse error.DeviceFailed,
        else => error.DeviceFailed,
    };
}

fn createSurface(instance: *wgpu.Instance, native: NativeSurface) !*wgpu.Surface {
    const mutable_instance = @constCast(instance);
    switch (native.kind) {
        .metal => {
            const descriptor = wgpu.surfaceDescriptorFromMetalLayer(.{
                .label = "phasor-lite metal surface",
                .layer = native.handle.metal.layer,
            });
            return mutable_instance.createSurface(&descriptor) orelse error.SurfaceCreationFailed;
        },
        .win32 => {
            const descriptor = wgpu.surfaceDescriptorFromWindowsHWND(.{
                .label = "phasor-lite win32 surface",
                .hinstance = native.handle.win32.hinstance,
                .hwnd = native.handle.win32.hwnd,
            });
            return mutable_instance.createSurface(&descriptor) orelse error.SurfaceCreationFailed;
        },
        .x11 => {
            const descriptor = wgpu.surfaceDescriptorFromXlibWindow(.{
                .label = "phasor-lite x11 surface",
                .display = native.handle.x11.display,
                .window = native.handle.x11.window,
            });
            return mutable_instance.createSurface(&descriptor) orelse error.SurfaceCreationFailed;
        },
    }
}

fn getSurfaceCapabilities(surface: *wgpu.Surface, adapter: *wgpu.Adapter) !wgpu.SurfaceCapabilities {
    var capabilities: wgpu.SurfaceCapabilities = std.mem.zeroes(wgpu.SurfaceCapabilities);
    const status = surface.getCapabilities(adapter, &capabilities);
    if (status != .success) return error.SurfaceCapabilitiesFailed;
    return capabilities;
}

fn selectSurfaceFormat(capabilities: wgpu.SurfaceCapabilities) wgpu.TextureFormat {
    const preferred = [_]wgpu.TextureFormat{
        .bgra8_unorm_srgb,
        .rgba8_unorm_srgb,
        .bgra8_unorm,
        .rgba8_unorm,
    };
    const formats = capabilities.formats[0..capabilities.format_count];
    for (preferred) |format| {
        for (formats) |supported| {
            if (supported == format) return format;
        }
    }
    return formats[0];
}

fn selectPresentMode(capabilities: wgpu.SurfaceCapabilities, requested: ?wgpu.PresentMode) wgpu.PresentMode {
    const modes = capabilities.present_modes[0..capabilities.present_mode_count];
    if (requested) |mode| {
        for (modes) |supported| {
            if (supported == mode) return mode;
        }
    }
    const preferred = [_]wgpu.PresentMode{ .mailbox, .immediate, .fifo };
    for (preferred) |mode| {
        for (modes) |supported| {
            if (supported == mode) return mode;
        }
    }
    return modes[0];
}

fn configureSurface(device: *wgpu.Device, surface: *wgpu.Surface, format: wgpu.TextureFormat, width: u32, height: u32, present_mode: wgpu.PresentMode) void {
    const config = wgpu.SurfaceConfiguration{
        .device = device,
        .format = format,
        .usage = wgpu.TextureUsages.render_attachment,
        .width = width,
        .height = height,
        .present_mode = present_mode,
        .alpha_mode = wgpu.CompositeAlphaMode.auto,
    };
    surface.configure(&config);
}

fn createEmptyBuffer(device: *wgpu.Device, usage: wgpu.BufferUsage, size: u64) !Buffer {
    const buffer = device.createBuffer(&wgpu.BufferDescriptor{
        .usage = usage,
        .size = size,
        .mapped_at_creation = @intFromBool(false),
    }) orelse return error.BufferCreationFailed;
    return Buffer{ .buffer = buffer, .size = size };
}

fn createBufferWithData(
    allocator: std.mem.Allocator,
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    usage: wgpu.BufferUsage,
    data: []const u8,
) !Buffer {
    const aligned_len = std.mem.alignForward(usize, data.len, 4);
    const buffer = try createEmptyBuffer(device, usage, @intCast(aligned_len));
    if (aligned_len == data.len) {
        queue.writeBuffer(buffer.buffer, 0, data.ptr, data.len);
        return buffer;
    }

    const padded = try allocator.alloc(u8, aligned_len);
    defer allocator.free(padded);
    @memset(padded, 0);
    std.mem.copyForwards(u8, padded[0..data.len], data);
    queue.writeBuffer(buffer.buffer, 0, padded.ptr, padded.len);
    return buffer;
}

fn createTrianglePipeline(
    device: *wgpu.Device,
    shader: *wgpu.ShaderModule,
    format: wgpu.TextureFormat,
    depth_format_param: wgpu.TextureFormat,
) !*wgpu.RenderPipeline {
    const attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x2, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x3, .offset = @sizeOf([2]f32), .shader_location = 1 },
    };
    const vertex_buffers = [_]wgpu.VertexBufferLayout{wgpu.VertexBufferLayout{
        .array_stride = @sizeOf(VertexColor),
        .attribute_count = attributes.len,
        .attributes = attributes[0..].ptr,
        .step_mode = .vertex,
    }};
    const color_targets = [_]wgpu.ColorTargetState{wgpu.ColorTargetState{
        .format = format,
    }};
    const depth_state = wgpu.DepthStencilState{
        .format = depth_format_param,
        .depth_write_enabled = .true,
        .depth_compare = .less_equal,
        .stencil_front = .{},
        .stencil_back = .{},
    };
    const pipeline = device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .vertex = wgpu.VertexState{
            .module = shader,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = vertex_buffers.len,
            .buffers = vertex_buffers[0..].ptr,
        },
        .primitive = wgpu.PrimitiveState{
            .topology = .triangle_list,
        },
        .depth_stencil = &depth_state,
        .fragment = &wgpu.FragmentState{
            .module = shader,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = color_targets.len,
            .targets = color_targets[0..].ptr,
        },
        .multisample = wgpu.MultisampleState{},
    }) orelse return error.PipelineCreationFailed;
    return pipeline;
}

fn createQuadBindGroupLayout(device: *wgpu.Device) !*wgpu.BindGroupLayout {
    const bind_group_layout = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
        .entry_count = 2,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.fragment,
                .sampler = .{ .type = .filtering },
            },
            .{
                .binding = 1,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                    .multisampled = @intFromBool(false),
                },
            },
        },
    }) orelse return error.BindGroupLayoutFailed;
    return bind_group_layout;
}

fn createQuadPipeline(
    device: *wgpu.Device,
    shader: *wgpu.ShaderModule,
    format: wgpu.TextureFormat,
    depth_format_param: wgpu.TextureFormat,
    bind_group_layout: *wgpu.BindGroupLayout,
    enable_blend: bool,
    depth_write_enabled: bool,
) !*wgpu.RenderPipeline {
    const pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
        .bind_group_layout_count = 1,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{bind_group_layout},
    }) orelse return error.PipelineLayoutFailed;
    defer pipeline_layout.release();

    const vertex_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x2, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x2, .offset = @sizeOf([2]f32), .shader_location = 1 },
    };
    const instance_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x4, .offset = 0, .shader_location = 2 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 1, .shader_location = 3 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 2, .shader_location = 4 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 3, .shader_location = 5 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 4, .shader_location = 6 },
    };
    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .array_stride = @sizeOf(VertexUv),
            .attribute_count = vertex_attributes.len,
            .attributes = vertex_attributes[0..].ptr,
            .step_mode = .vertex,
        },
        .{
            .array_stride = @sizeOf(InstanceData),
            .attribute_count = instance_attributes.len,
            .attributes = instance_attributes[0..].ptr,
            .step_mode = .instance,
        },
    };
    const blend_state = wgpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .one_minus_src_alpha,
        },
    };
    const color_targets = [_]wgpu.ColorTargetState{wgpu.ColorTargetState{
        .format = format,
        .blend = if (enable_blend) &blend_state else null,
    }};
    const depth_state = wgpu.DepthStencilState{
        .format = depth_format_param,
        .depth_write_enabled = switch (depth_write_enabled) {
            true => .true,
            false => .false,
        },
        .depth_compare = .less_equal,
        .stencil_front = .{},
        .stencil_back = .{},
    };

    const pipeline = device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .layout = pipeline_layout,
        .vertex = wgpu.VertexState{
            .module = shader,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = vertex_buffers.len,
            .buffers = vertex_buffers[0..].ptr,
        },
        .primitive = wgpu.PrimitiveState{
            .topology = .triangle_list,
        },
        .depth_stencil = &depth_state,
        .fragment = &wgpu.FragmentState{
            .module = shader,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = color_targets.len,
            .targets = color_targets[0..].ptr,
        },
        .multisample = wgpu.MultisampleState{},
    }) orelse return error.PipelineCreationFailed;
    return pipeline;
}

const ShaderStageKind = enum {
    vertex,
    fragment,
};

fn createShaderModule(device: *wgpu.Device, stage: ShaderStageKind, source: ShaderSource) !*wgpu.ShaderModule {
    if (source.glsl_vertex != null and source.glsl_fragment != null) {
        const glsl_code = switch (stage) {
            .vertex => source.glsl_vertex.?,
            .fragment => source.glsl_fragment.?,
        };
        const shader = device.createShaderModule(&wgpu.shaderModuleGLSLDescriptor(.{
            .code = glsl_code,
            .stage = switch (stage) {
                .vertex => wgpu.ShaderStages.vertex,
                .fragment => wgpu.ShaderStages.fragment,
            },
        })) orelse return error.ShaderCreationFailed;
        return shader;
    }

    const wgsl = source.wgsl orelse return error.MissingShaderSource;
    return device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = wgsl,
    })) orelse return error.ShaderCreationFailed;
}

fn createColorPipeline(
    device: *wgpu.Device,
    vertex_shader: *wgpu.ShaderModule,
    fragment_shader: *wgpu.ShaderModule,
    format: wgpu.TextureFormat,
    depth_format_param: wgpu.TextureFormat,
    enable_blend: bool,
    depth_write_enabled: bool,
) !*wgpu.RenderPipeline {
    const vertex_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x4, .offset = @sizeOf([3]f32), .shader_location = 1 },
    };
    const instance_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x4, .offset = 0, .shader_location = 2 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 1, .shader_location = 3 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 2, .shader_location = 4 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 3, .shader_location = 5 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 4, .shader_location = 6 },
    };
    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .array_stride = @sizeOf(VertexPos3Color),
            .attribute_count = vertex_attributes.len,
            .attributes = vertex_attributes[0..].ptr,
            .step_mode = .vertex,
        },
        .{
            .array_stride = @sizeOf(InstanceData),
            .attribute_count = instance_attributes.len,
            .attributes = instance_attributes[0..].ptr,
            .step_mode = .instance,
        },
    };
    const blend_state = wgpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .one_minus_src_alpha,
        },
    };
    const color_targets = [_]wgpu.ColorTargetState{wgpu.ColorTargetState{
        .format = format,
        .blend = if (enable_blend) &blend_state else null,
    }};
    const depth_state = wgpu.DepthStencilState{
        .format = depth_format_param,
        .depth_write_enabled = switch (depth_write_enabled) {
            true => .true,
            false => .false,
        },
        .depth_compare = .less_equal,
        .stencil_front = .{},
        .stencil_back = .{},
    };

    return device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .vertex = wgpu.VertexState{
            .module = vertex_shader,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = vertex_buffers.len,
            .buffers = vertex_buffers[0..].ptr,
        },
        .primitive = wgpu.PrimitiveState{
            .topology = .triangle_list,
        },
        .depth_stencil = &depth_state,
        .fragment = &wgpu.FragmentState{
            .module = fragment_shader,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = color_targets.len,
            .targets = color_targets[0..].ptr,
        },
        .multisample = wgpu.MultisampleState{},
    }) orelse return error.PipelineCreationFailed;
}

fn createDepthTarget(device: *wgpu.Device, width: u32, height: u32) !DepthTarget {
    const texture = device.createTexture(&wgpu.TextureDescriptor{
        .size = .{ .width = width, .height = height, .depth_or_array_layers = 1 },
        .format = depth_format,
        .usage = wgpu.TextureUsages.render_attachment,
        .mip_level_count = 1,
        .sample_count = 1,
        .dimension = .@"2d",
    }) orelse return error.TextureCreationFailed;
    errdefer texture.release();

    const view = texture.createView(&wgpu.TextureViewDescriptor{}) orelse return error.TextureViewFailed;
    return .{
        .texture = texture,
        .view = view,
    };
}

const defaultTriangleVertices = [_]VertexColor{
    .{ .position = .{ 0.0, 0.6 }, .color = .{ 1.0, 0.0, 0.0 } },
    .{ .position = .{ -0.6, -0.6 }, .color = .{ 0.0, 1.0, 0.0 } },
    .{ .position = .{ 0.6, -0.6 }, .color = .{ 0.0, 0.0, 1.0 } },
};

const defaultQuadVertices = [_]VertexUv{
    .{ .position = .{ -0.5, -0.5 }, .uv = .{ 0.0, 1.0 } },
    .{ .position = .{ 0.5, -0.5 }, .uv = .{ 1.0, 1.0 } },
    .{ .position = .{ 0.5, 0.5 }, .uv = .{ 1.0, 0.0 } },
    .{ .position = .{ -0.5, 0.5 }, .uv = .{ 0.0, 0.0 } },
};

const defaultQuadIndices = [_]u16{ 0, 1, 2, 2, 3, 0 };

const triangleShaderWGSL = @embedFile("shaders/triangle.wgsl");
const quadShaderWGSL = @embedFile("shaders/quad.wgsl");

// Imports
const std = @import("std");
const wgpu = @import("wgpu");
const utils = @import("utils.zig");
const common = @import("common");

const Color = common.Color;
const Size = utils.Size;
const SurfaceTarget = utils.SurfaceTarget;
const NativeSurface = utils.NativeSurface;
const NativeHandle = utils.NativeHandle;
const CacheKey = utils.CacheKey;
const hashCacheKey = utils.hashCacheKey;
const RingBuffer = utils.RingBuffer;
