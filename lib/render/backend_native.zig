const DepthTarget = struct {
    texture: *wgpu.Texture,
    view: *wgpu.TextureView,
};

const depth_format = wgpu.TextureFormat.depth24_plus;
const shadow_map_format = wgpu.TextureFormat.depth32_float;

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

pub const SamplerFilter = enum(u8) {
    nearest,
    linear,
};

pub const SamplerAddressMode = enum(u8) {
    clamp_to_edge,
    repeat,
    mirror_repeat,
};

pub const SamplerDescriptor = struct {
    mag_filter: SamplerFilter = .linear,
    min_filter: SamplerFilter = .linear,
    mipmap_filter: SamplerFilter = .linear,
    address_mode_u: SamplerAddressMode = .clamp_to_edge,
    address_mode_v: SamplerAddressMode = .clamp_to_edge,
    address_mode_w: SamplerAddressMode = .clamp_to_edge,

    pub fn tiledLinear() SamplerDescriptor {
        return .{
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_filter = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
        };
    }

    pub fn pixelArtTiled() SamplerDescriptor {
        return .{
            .mag_filter = .nearest,
            .min_filter = .nearest,
            .mipmap_filter = .nearest,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
        };
    }
};

pub const Pipeline = struct {
    pipeline: *wgpu.RenderPipeline,
};

pub const Shader = struct {
    pipeline_opaque: *wgpu.RenderPipeline,
    pipeline_blend: *wgpu.RenderPipeline,
    vertex_layout: ShaderVertexLayout,
    binding_mode: ShaderBindingMode,
};

pub const ShadowShader = struct {
    pipeline: *wgpu.RenderPipeline,
    vertex_layout: ShaderVertexLayout,
    binding_mode: ShaderBindingMode,
};

pub const PostProcessShader = struct {
    pipeline_opaque: *wgpu.RenderPipeline,
    pipeline_blend: *wgpu.RenderPipeline,
};

pub const FrameTarget = union(enum) {
    surface,
    texture: Texture,
};

pub const Material = struct {
    bind_group: *wgpu.BindGroup,
    scene_bind_group: *wgpu.BindGroup,
};

pub const SceneMaterialBinding = struct {
    base_color_texture: Texture,
    metallic_roughness_texture: Texture,
    occlusion_texture: Texture,
};

pub const ShaderSource = struct {
    wgsl: ?[]const u8 = null,
    glsl_vertex: ?[]const u8 = null,
    glsl_fragment: ?[]const u8 = null,
    vertex_layout: ShaderVertexLayout = .pos3_color4,
    binding_mode: ShaderBindingMode = .none,
};

pub const ShaderVertexLayout = enum(u8) {
    uv2,
    pos3_color4,
    pos3_uv2,
    pos3_norm_uv2,
};

pub const ShaderBindingMode = enum(u8) {
    none,
    material,
    material_scene,
};

pub const MeshVertexLayout = enum(u8) {
    uv2,
    pos3_uv2,
    pos3_color4,
    pos3_norm_uv2,
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
    clip_transform: common.Mat4 = common.Mat4.identity(),
    model_transform: common.Mat4 = common.Mat4.identity(),
    color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
    pbr_params: [4]f32 = .{ 0.0, 1.0, 1.0, 0.0 },
};

pub const VertexColor = extern struct {
    position: [2]f32,
    color: [3]f32,
};

pub const VertexUv = extern struct {
    position: [2]f32,
    uv: [2]f32,
};

pub const VertexPos3Uv = extern struct {
    position: [3]f32,
    uv: [2]f32,
};

pub const VertexPos3NormUv = extern struct {
    position: [3]f32,
    normal: [3]f32,
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
    clip0: [4]f32,
    clip1: [4]f32,
    clip2: [4]f32,
    clip3: [4]f32,
    model0: [4]f32,
    model1: [4]f32,
    model2: [4]f32,
    model3: [4]f32,
    color: [4]f32,
    pbr_params: [4]f32,
};

const PostProcessUniformData = extern struct {
    params0: [4]f32,
    params1: [4]f32,
    params2: [4]f32,
    params3: [4]f32,
    meta0: [4]f32,
};

const PostProcessSlot = struct {
    texture: Texture,
    bind_group: *wgpu.BindGroup,
    alive: bool = false,
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
    mesh_textured_pipeline_opaque: *wgpu.RenderPipeline,
    mesh_textured_pipeline_blend: *wgpu.RenderPipeline,
    quad_bind_group_layout: *wgpu.BindGroupLayout,
    scene_bind_group_layout: *wgpu.BindGroupLayout,
    shadow_bind_group_layout: *wgpu.BindGroupLayout,
    post_process_bind_group_layout: *wgpu.BindGroupLayout,
    scene_uniform_buffer: Buffer,
    shadow_uniform_buffer: Buffer,
    shadow_sampler: Sampler,
    shadow_bind_group: ?*wgpu.BindGroup,
    shadow_slot_index: u32,
    shadow_slot_width: u32,
    shadow_slot_height: u32,
    shadow_map_texture: ?Texture,
    post_process_sampler: Sampler,
    post_process_uniform_buffer: Buffer,

    triangle_vertex_buffer: Buffer,
    quad_vertex_buffer: Buffer,
    quad_index_buffer: Buffer,
    instance_buffer: Buffer,
    instance_ring: RingBuffer,
    depth_target: DepthTarget,
    post_process_slots: std.ArrayListUnmanaged(PostProcessSlot),

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
            .mesh_textured_pipeline_opaque = undefined,
            .mesh_textured_pipeline_blend = undefined,
            .quad_bind_group_layout = undefined,
            .scene_bind_group_layout = undefined,
            .shadow_bind_group_layout = undefined,
            .post_process_bind_group_layout = undefined,
            .scene_uniform_buffer = undefined,
            .shadow_uniform_buffer = undefined,
            .shadow_sampler = undefined,
            .shadow_bind_group = null,
            .shadow_slot_index = 0,
            .shadow_slot_width = 0,
            .shadow_slot_height = 0,
            .shadow_map_texture = null,
            .post_process_sampler = undefined,
            .post_process_uniform_buffer = undefined,
            .triangle_vertex_buffer = undefined,
            .quad_vertex_buffer = undefined,
            .quad_index_buffer = undefined,
            .instance_buffer = undefined,
            .instance_ring = RingBuffer.init(512 * 1024),
            .depth_target = undefined,
            .post_process_slots = .empty,
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
        self.post_process_uniform_buffer = try createEmptyBuffer(
            self.device,
            wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            @sizeOf(PostProcessUniformData),
        );
        self.scene_uniform_buffer = try createEmptyBuffer(
            self.device,
            wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            @sizeOf(scene_uniforms.SceneUniforms),
        );
        self.shadow_uniform_buffer = try createEmptyBuffer(
            self.device,
            wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            @sizeOf(shadow_uniforms.ShadowUniforms),
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

        const shader_mesh_textured = self.device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
            .code = meshTexturedShaderWGSL,
        })) orelse return error.ShaderCreationFailed;
        defer shader_mesh_textured.release();

        const triangle_key = CacheKey{ .a = 1, .b = 0, .c = 0 };
        _ = hashCacheKey(triangle_key);
        self.triangle_pipeline = try createTrianglePipeline(self.device, shader_triangle, self.surface_format, depth_format);

        const quad_key = CacheKey{ .a = 2, .b = 0, .c = 0 };
        _ = hashCacheKey(quad_key);
        const quad_bind_group_layout = try createQuadBindGroupLayout(self.device);
        self.quad_bind_group_layout = quad_bind_group_layout;
        self.scene_bind_group_layout = try createSceneBindGroupLayout(self.device);
        self.shadow_bind_group_layout = try createShadowBindGroupLayout(self.device);
        self.post_process_bind_group_layout = try createPostProcessBindGroupLayout(self.device);
        self.post_process_sampler = try self.createSampler();
        self.shadow_sampler = try createComparisonSampler(self.device);
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
        self.mesh_textured_pipeline_opaque = try createMeshTexturedPipeline(
            self.device,
            shader_mesh_textured,
            self.surface_format,
            depth_format,
            quad_bind_group_layout,
            false,
            true,
        );
        self.mesh_textured_pipeline_blend = try createMeshTexturedPipeline(
            self.device,
            shader_mesh_textured,
            self.surface_format,
            depth_format,
            quad_bind_group_layout,
            true,
            false,
        );
    }

    pub fn deinit(self: *Renderer) void {
        for (self.post_process_slots.items) |*slot| {
            if (!slot.alive) continue;
            slot.bind_group.release();
            destroyTextureStorage(&slot.texture);
        }
        self.post_process_slots.deinit(self.allocator);

        self.triangle_pipeline.release();
        self.quad_pipeline_opaque.release();
        self.quad_pipeline_blend.release();
        self.mesh_textured_pipeline_opaque.release();
        self.mesh_textured_pipeline_blend.release();
        self.quad_bind_group_layout.release();
        self.scene_bind_group_layout.release();
        self.shadow_bind_group_layout.release();
        self.post_process_bind_group_layout.release();
        self.destroySampler(&self.post_process_sampler);
        self.destroySampler(&self.shadow_sampler);
        if (self.shadow_bind_group) |bind_group| bind_group.release();
        self.destroyShadowResources();

        self.triangle_vertex_buffer.buffer.release();
        self.quad_vertex_buffer.buffer.release();
        self.quad_index_buffer.buffer.release();
        self.instance_buffer.buffer.release();
        self.scene_uniform_buffer.buffer.release();
        self.shadow_uniform_buffer.buffer.release();
        self.post_process_uniform_buffer.buffer.release();
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
        for (self.post_process_slots.items) |*slot| {
            if (!slot.alive) continue;
            slot.bind_group.release();
            destroyTextureStorage(&slot.texture);
            slot.alive = false;
        }
        self.destroyShadowResources();
        if (self.shadow_bind_group) |bind_group| {
            bind_group.release();
            self.shadow_bind_group = null;
        }
        self.shadow_slot_width = 0;
        self.shadow_slot_height = 0;
    }

    pub fn beginFrame(self: *Renderer) !Frame {
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

        return Frame{
            .renderer = self,
            .encoder = encoder,
            .render_pass = null,
            .surface_texture = surface_texture,
            .surface_view = view,
        };
    }

    pub fn createSampler(self: *Renderer) !Sampler {
        return self.createSamplerWithDescriptor(.{});
    }

    pub fn createSamplerWithDescriptor(self: *Renderer, descriptor: SamplerDescriptor) !Sampler {
        const sampler = self.device.createSampler(&wgpu.SamplerDescriptor{
            .mag_filter = toWgpuFilter(descriptor.mag_filter),
            .min_filter = toWgpuFilter(descriptor.min_filter),
            .mipmap_filter = toWgpuMipmapFilter(descriptor.mipmap_filter),
            .address_mode_u = toWgpuAddressMode(descriptor.address_mode_u),
            .address_mode_v = toWgpuAddressMode(descriptor.address_mode_v),
            .address_mode_w = toWgpuAddressMode(descriptor.address_mode_w),
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

    pub fn createTextureRgba8Linear(self: *Renderer, width: u32, height: u32, data: []const u8) !Texture {
        const texture = self.device.createTexture(&wgpu.TextureDescriptor{
            .size = .{ .width = width, .height = height, .depth_or_array_layers = 1 },
            .format = .rgba8_unorm,
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
            .format = .rgba8_unorm,
        };
    }

    pub fn createTextureRgba16Float(self: *Renderer, width: u32, height: u32, data: []const f32) !Texture {
        const texture = self.device.createTexture(&wgpu.TextureDescriptor{
            .size = .{ .width = width, .height = height, .depth_or_array_layers = 1 },
            .format = .rgba16_float,
            .usage = wgpu.TextureUsages.texture_binding | wgpu.TextureUsages.copy_dst,
            .mip_level_count = 1,
            .sample_count = 1,
            .dimension = .@"2d",
        }) orelse return error.TextureCreationFailed;
        errdefer texture.release();

        const view = texture.createView(&wgpu.TextureViewDescriptor{}) orelse return error.TextureViewFailed;
        errdefer view.release();

        const pixel_count: usize = @intCast(width * height);
        if (data.len != pixel_count * 4) return error.InvalidTextureData;

        const bytes_per_row = width * 8;
        const aligned_bpr = std.mem.alignForward(u32, bytes_per_row, 256);
        const upload_len: usize = aligned_bpr * height;
        const upload = try self.allocator.alloc(u8, upload_len);
        defer self.allocator.free(upload);
        @memset(upload, 0);

        var row: u32 = 0;
        while (row < height) : (row += 1) {
            const src_row_start: usize = @intCast(row * width * 4);
            const dst_row_start: usize = @intCast(row * aligned_bpr);
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const src_base = src_row_start + @as(usize, @intCast(x)) * 4;
                const dst_base = dst_row_start + @as(usize, @intCast(x)) * 8;
                writeHalf4(upload[dst_base .. dst_base + 8], data[src_base .. src_base + 4]);
            }
        }

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
            .format = .rgba16_float,
        };
    }

    pub fn destroyTexture(_: *Renderer, texture: *Texture) void {
        destroyTextureStorage(texture);
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
        const scene_bind_group = try createSceneBindGroup(
            self.device,
            self.scene_bind_group_layout,
            sampler.sampler,
            texture.view,
            texture.view,
            texture.view,
            self.scene_uniform_buffer.buffer,
        );
        return Material{ .bind_group = bind_group, .scene_bind_group = scene_bind_group };
    }

    pub fn createSceneMaterial(self: *Renderer, binding: SceneMaterialBinding, sampler: Sampler) !Material {
        const entries = [_]wgpu.BindGroupEntry{
            .{ .binding = 0, .sampler = sampler.sampler },
            .{ .binding = 1, .texture_view = binding.base_color_texture.view },
        };
        const bind_group = self.device.createBindGroup(&wgpu.BindGroupDescriptor{
            .layout = self.quad_bind_group_layout,
            .entry_count = entries.len,
            .entries = entries[0..].ptr,
        }) orelse return error.BindGroupCreationFailed;
        const scene_bind_group = try createSceneBindGroup(
            self.device,
            self.scene_bind_group_layout,
            sampler.sampler,
            binding.base_color_texture.view,
            binding.metallic_roughness_texture.view,
            binding.occlusion_texture.view,
            self.scene_uniform_buffer.buffer,
        );
        return Material{ .bind_group = bind_group, .scene_bind_group = scene_bind_group };
    }

    pub fn destroyMaterial(_: *Renderer, material: *Material) void {
        material.bind_group.release();
        material.scene_bind_group.release();
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

    pub fn createMeshPos3Uv(self: *Renderer, vertices: []const VertexPos3Uv, indices: []const u16) !Mesh {
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
            .vertex_layout = .pos3_uv2,
        };
    }

    pub fn updateMeshPos3Uv(self: *Renderer, mesh: *Mesh, vertices: []const VertexPos3Uv, indices: []const u16) !void {
        if (mesh.vertex_layout != .pos3_uv2) return error.InvalidMeshLayout;
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

    pub fn createMeshPos3NormUv(self: *Renderer, vertices: []const VertexPos3NormUv, indices: []const u16) !Mesh {
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
            .vertex_layout = .pos3_norm_uv2,
        };
    }

    pub fn updateMeshPos3NormUv(self: *Renderer, mesh: *Mesh, vertices: []const VertexPos3NormUv, indices: []const u16) !void {
        if (mesh.vertex_layout != .pos3_norm_uv2) return error.InvalidMeshLayout;
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
        return self.createShaderForFormat(source, self.surface_format);
    }

    pub fn createShadowShader(self: *Renderer, source: ShaderSource) !ShadowShader {
        const shader_vertex = try createShaderModule(self.device, .vertex, source);
        defer shader_vertex.release();
        return .{
            .pipeline = try createShadowPipeline(
                self.device,
                shader_vertex,
                shadow_map_format,
                source.vertex_layout,
                source.binding_mode,
                self.quad_bind_group_layout,
            ),
            .vertex_layout = source.vertex_layout,
            .binding_mode = source.binding_mode,
        };
    }

    fn createShaderForFormat(self: *Renderer, source: ShaderSource, color_format: wgpu.TextureFormat) !Shader {
        const shader_vertex = try createShaderModule(self.device, .vertex, source);
        defer shader_vertex.release();
        const shader_fragment = try createShaderModule(self.device, .fragment, source);
        defer shader_fragment.release();
        return switch (source.binding_mode) {
            .none => .{
                .pipeline_opaque = try createColorPipeline(
                    self.device,
                    shader_vertex,
                    shader_fragment,
                    color_format,
                    depth_format,
                    false,
                    true,
                ),
                .pipeline_blend = try createColorPipeline(
                    self.device,
                    shader_vertex,
                    shader_fragment,
                    color_format,
                    depth_format,
                    true,
                    false,
                ),
                .vertex_layout = source.vertex_layout,
                .binding_mode = source.binding_mode,
            },
            .material => .{
                .pipeline_opaque = try createCustomMaterialPipeline(
                    self.device,
                    shader_vertex,
                    shader_fragment,
                    color_format,
                    depth_format,
                    self.quad_bind_group_layout,
                    self.shadow_bind_group_layout,
                    source.vertex_layout,
                    source.binding_mode,
                    false,
                    true,
                ),
                .pipeline_blend = try createCustomMaterialPipeline(
                    self.device,
                    shader_vertex,
                    shader_fragment,
                    color_format,
                    depth_format,
                    self.quad_bind_group_layout,
                    self.shadow_bind_group_layout,
                    source.vertex_layout,
                    source.binding_mode,
                    true,
                    false,
                ),
                .vertex_layout = source.vertex_layout,
                .binding_mode = source.binding_mode,
            },
            .material_scene => .{
                .pipeline_opaque = try createCustomMaterialPipeline(
                    self.device,
                    shader_vertex,
                    shader_fragment,
                    color_format,
                    depth_format,
                    self.scene_bind_group_layout,
                    self.shadow_bind_group_layout,
                    source.vertex_layout,
                    source.binding_mode,
                    false,
                    true,
                ),
                .pipeline_blend = try createCustomMaterialPipeline(
                    self.device,
                    shader_vertex,
                    shader_fragment,
                    color_format,
                    depth_format,
                    self.scene_bind_group_layout,
                    self.shadow_bind_group_layout,
                    source.vertex_layout,
                    source.binding_mode,
                    true,
                    false,
                ),
                .vertex_layout = source.vertex_layout,
                .binding_mode = source.binding_mode,
            },
        };
    }

    pub fn destroyShader(_: *Renderer, shader: *Shader) void {
        shader.pipeline_opaque.release();
        shader.pipeline_blend.release();
    }

    pub fn destroyShadowShader(_: *Renderer, shader: *ShadowShader) void {
        shader.pipeline.release();
    }

    pub fn createPostProcessShader(self: *Renderer, source: ShaderSource) !PostProcessShader {
        const fragment_shader = try createShaderModule(self.device, .fragment, source);
        defer fragment_shader.release();
        const vertex_shader = self.device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
            .code = postProcessVertexWGSL,
        })) orelse return error.ShaderCreationFailed;
        defer vertex_shader.release();

        return PostProcessShader{
            .pipeline_opaque = try createPostProcessPipeline(self.device, vertex_shader, fragment_shader, self.surface_format, self.post_process_bind_group_layout, false),
            .pipeline_blend = try createPostProcessPipeline(self.device, vertex_shader, fragment_shader, self.surface_format, self.post_process_bind_group_layout, true),
        };
    }

    pub fn destroyPostProcessShader(_: *Renderer, shader: *PostProcessShader) void {
        shader.pipeline_opaque.release();
        shader.pipeline_blend.release();
    }

    pub fn ensurePostProcessSlot(self: *Renderer, slot_index: u32, width: u32, height: u32) !Texture {
        const index: usize = @intCast(slot_index);
        if (self.post_process_slots.items.len <= index) {
            const previous_len = self.post_process_slots.items.len;
            try self.post_process_slots.resize(self.allocator, index + 1);
            for (self.post_process_slots.items[previous_len..]) |*slot| {
                slot.* = .{
                    .texture = undefined,
                    .bind_group = undefined,
                    .alive = false,
                };
            }
        }
        const slot = &self.post_process_slots.items[index];
        if (!slot.alive or slot.texture.width != width or slot.texture.height != height) {
            if (slot.alive) {
                slot.bind_group.release();
                destroyTextureStorage(&slot.texture);
                slot.alive = false;
            }
            slot.texture = try createRenderTexture(self.device, width, height, self.surface_format);
            slot.bind_group = try createPostProcessBindGroup(
                self.device,
                self.post_process_bind_group_layout,
                self.post_process_sampler.sampler,
                slot.texture.view,
                self.post_process_uniform_buffer.buffer,
            );
            slot.alive = true;
        }
        return slot.texture;
    }

    pub fn ensureShadowMapSlot(self: *Renderer, slot_index: u32, width: u32, height: u32) !Texture {
        _ = slot_index;
        if (self.shadow_map_texture == null or
            self.shadow_slot_width != width or
            self.shadow_slot_height != height)
        {
            self.destroyShadowResources();
            self.shadow_map_texture = try createShadowMapTexture(self.device, width, height);
            self.shadow_slot_width = width;
            self.shadow_slot_height = height;
            if (self.shadow_bind_group) |bind_group| {
                bind_group.release();
                self.shadow_bind_group = null;
            }
        }
        return self.shadow_map_texture.?;
    }

    fn ensureShadowBindGroup(self: *Renderer, slot_index: u32, width: u32, height: u32) !void {
        const slot_texture = try self.ensureShadowMapSlot(slot_index, width, height);
        if (self.shadow_bind_group != null and
            self.shadow_slot_index == slot_index and
            self.shadow_slot_width == width and
            self.shadow_slot_height == height)
        {
            return;
        }
        if (self.shadow_bind_group) |bind_group| {
            bind_group.release();
            self.shadow_bind_group = null;
        }
        self.shadow_bind_group = try createShadowBindGroup(
            self.device,
            self.shadow_bind_group_layout,
            self.shadow_uniform_buffer.buffer,
            self.shadow_sampler.sampler,
            slot_texture.view,
        );
        self.shadow_slot_index = slot_index;
        self.shadow_slot_width = width;
        self.shadow_slot_height = height;
    }

    fn postProcessBindGroup(self: *Renderer, slot_index: u32) ?*wgpu.BindGroup {
        const index: usize = @intCast(slot_index);
        if (index >= self.post_process_slots.items.len) return null;
        const slot = &self.post_process_slots.items[index];
        if (!slot.alive) return null;
        return slot.bind_group;
    }

    fn destroyShadowResources(self: *Renderer) void {
        if (self.shadow_map_texture) |*texture| {
            destroyTextureStorage(texture);
            self.shadow_map_texture = null;
        }
    }

    pub fn stats(_: *const Renderer) RendererStats {
        return .{};
    }
};

pub const Frame = struct {
    renderer: *Renderer,
    encoder: *wgpu.CommandEncoder,
    render_pass: ?*wgpu.RenderPassEncoder,
    surface_texture: wgpu.SurfaceTexture,
    surface_view: *wgpu.TextureView,

    pub fn draw(self: *Frame, cmd: DrawCmd) void {
        switch (cmd) {
            .triangle => |triangle| self.drawTriangle(triangle),
            .textured_quad => |quad| self.drawTexturedQuad(quad),
        }
    }

    pub fn beginScenePass(self: *Frame, target: FrameTarget, clear: Color) !void {
        try self.beginPass(target, clear, true, false, null);
    }

    pub fn beginScenePassLoad(self: *Frame, target: FrameTarget) !void {
        try self.beginPass(target, Color.rgba(0, 0, 0, 0), true, true, null);
    }

    pub fn beginShadowPass(self: *Frame, target: FrameTarget, clear: Color) !void {
        const depth_view = switch (target) {
            .surface => self.renderer.depth_target.view,
            .texture => |texture| texture.view,
        };
        try self.beginDepthOnlyPass(depth_view, clear);
    }

    pub fn beginPostProcessPass(self: *Frame, target: FrameTarget, clear: Color) !void {
        try self.beginPass(target, clear, false, false, null);
    }

    pub fn setViewportScissor(self: *Frame, x: f32, y: f32, width: f32, height: f32) void {
        const render_pass = self.render_pass orelse return;
        render_pass.setViewport(x, y, width, height, 0.0, 1.0);
        const sx: u32 = @intFromFloat(@max(0.0, x));
        const sy: u32 = @intFromFloat(@max(0.0, y));
        const sw: u32 = @intFromFloat(@max(0.0, width));
        const sh: u32 = @intFromFloat(@max(0.0, height));
        render_pass.setScissorRect(sx, sy, sw, sh);
    }

    pub fn setSceneUniforms(self: *Frame, uniforms: scene_uniforms.SceneUniforms) void {
        const bytes = std.mem.asBytes(&uniforms);
        self.renderer.queue.writeBuffer(self.renderer.scene_uniform_buffer.buffer, 0, bytes.ptr, bytes.len);
    }

    pub fn setShadowUniforms(self: *Frame, uniforms: shadow_uniforms.ShadowUniforms, slot_index: u32, slot_size: Size) void {
        const bytes = std.mem.asBytes(&uniforms);
        self.renderer.queue.writeBuffer(self.renderer.shadow_uniform_buffer.buffer, 0, bytes.ptr, bytes.len);
        self.renderer.ensureShadowBindGroup(slot_index, slot_size.width, slot_size.height) catch return;
    }

    fn drawTriangle(self: *Frame, triangle: Triangle) void {
        const render_pass = self.render_pass orelse return;
        const data = std.mem.asBytes(&triangle.vertices);
        self.renderer.queue.writeBuffer(self.renderer.triangle_vertex_buffer.buffer, 0, data.ptr, data.len);
        render_pass.setPipeline(self.renderer.triangle_pipeline);
        render_pass.setVertexBuffer(0, self.renderer.triangle_vertex_buffer.buffer, 0, self.renderer.triangle_vertex_buffer.size);
        render_pass.draw(3, 1, 0, 0);
    }

    fn drawTexturedQuad(self: *Frame, quad: TexturedQuad) void {
        if (quad.mesh.vertex_layout != .uv2) return;
        const render_pass = self.render_pass orelse return;
        const instance = buildInstanceData(quad.instance);
        const instance_bytes = std.mem.asBytes(&instance);
        const offset = self.renderer.instance_ring.allocate(@sizeOf(InstanceData), 256);
        self.renderer.queue.writeBuffer(self.renderer.instance_buffer.buffer, offset, instance_bytes.ptr, instance_bytes.len);

        const pipeline = if (quad.blend) self.renderer.quad_pipeline_blend else self.renderer.quad_pipeline_opaque;
        render_pass.setPipeline(pipeline);
        render_pass.setBindGroup(0, quad.material.bind_group, 0, null);
        render_pass.setVertexBuffer(0, quad.mesh.vertex_buffer.buffer, 0, quad.mesh.vertex_buffer.size);
        render_pass.setVertexBuffer(1, self.renderer.instance_buffer.buffer, offset, @sizeOf(InstanceData));
        render_pass.setIndexBuffer(quad.mesh.index_buffer.buffer, .uint16, 0, quad.mesh.index_buffer.size);
        render_pass.drawIndexed(quad.mesh.index_count, 1, 0, 0, 0);
    }

    pub fn drawTexturedQuads(self: *Frame, mesh: Mesh, material: Material, instances: []const MeshInstance, blend: bool) void {
        const pipeline = switch (mesh.vertex_layout) {
            .uv2 => if (blend) self.renderer.quad_pipeline_blend else self.renderer.quad_pipeline_opaque,
            .pos3_uv2 => if (blend) self.renderer.mesh_textured_pipeline_blend else self.renderer.mesh_textured_pipeline_opaque,
            else => return,
        };
        if (instances.len == 0) return;
        const render_pass = self.render_pass orelse return;
        const total_bytes: usize = instances.len * @sizeOf(InstanceData);
        const offset = self.renderer.instance_ring.allocate(total_bytes, 256);

        var i: usize = 0;
        while (i < instances.len) : (i += 1) {
            const data = buildInstanceData(instances[i]);
            const bytes = std.mem.asBytes(&data);
            const byte_offset = offset + i * @sizeOf(InstanceData);
            self.renderer.queue.writeBuffer(self.renderer.instance_buffer.buffer, byte_offset, bytes.ptr, bytes.len);
        }

        render_pass.setPipeline(pipeline);
        render_pass.setBindGroup(0, material.bind_group, 0, null);
        render_pass.setVertexBuffer(0, mesh.vertex_buffer.buffer, 0, mesh.vertex_buffer.size);
        render_pass.setVertexBuffer(1, self.renderer.instance_buffer.buffer, offset, total_bytes);
        render_pass.setIndexBuffer(mesh.index_buffer.buffer, .uint16, 0, mesh.index_buffer.size);
        render_pass.drawIndexed(mesh.index_count, @intCast(instances.len), 0, 0, 0);
    }

    pub fn drawTexturedMeshesWithShader(self: *Frame, mesh: Mesh, material: Material, shader: Shader, instances: []const MeshInstance, blend: bool) void {
        if (instances.len == 0) return;
        if (!shaderMatchesMesh(shader, mesh.vertex_layout)) return;
        const render_pass = self.render_pass orelse return;
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
        render_pass.setPipeline(pipeline);
        render_pass.setBindGroup(0, if (shader.binding_mode == .material_scene) material.scene_bind_group else material.bind_group, 0, null);
        if (shader.binding_mode == .material_scene) {
            if (self.renderer.shadow_bind_group) |shadow_bind_group| {
                render_pass.setBindGroup(1, shadow_bind_group, 0, null);
            }
        }
        render_pass.setVertexBuffer(0, mesh.vertex_buffer.buffer, 0, mesh.vertex_buffer.size);
        render_pass.setVertexBuffer(1, self.renderer.instance_buffer.buffer, offset, total_bytes);
        render_pass.setIndexBuffer(mesh.index_buffer.buffer, .uint16, 0, mesh.index_buffer.size);
        render_pass.drawIndexed(mesh.index_count, @intCast(instances.len), 0, 0, 0);
    }

    pub fn drawShadowTexturedMeshesWithShader(self: *Frame, mesh: Mesh, material: Material, shader: ShadowShader, instances: []const MeshInstance) void {
        if (instances.len == 0) return;
        if (!shadowShaderMatchesMesh(shader, mesh.vertex_layout)) return;
        const render_pass = self.render_pass orelse return;
        const total_bytes: usize = instances.len * @sizeOf(InstanceData);
        const offset = self.renderer.instance_ring.allocate(total_bytes, 256);

        var i: usize = 0;
        while (i < instances.len) : (i += 1) {
            const data = buildInstanceData(instances[i]);
            const bytes = std.mem.asBytes(&data);
            const byte_offset = offset + i * @sizeOf(InstanceData);
            self.renderer.queue.writeBuffer(self.renderer.instance_buffer.buffer, byte_offset, bytes.ptr, bytes.len);
        }

        render_pass.setPipeline(shader.pipeline);
        if (shader.binding_mode == .material) {
            render_pass.setBindGroup(0, material.bind_group, 0, null);
        }
        render_pass.setVertexBuffer(0, mesh.vertex_buffer.buffer, 0, mesh.vertex_buffer.size);
        render_pass.setVertexBuffer(1, self.renderer.instance_buffer.buffer, offset, total_bytes);
        render_pass.setIndexBuffer(mesh.index_buffer.buffer, .uint16, 0, mesh.index_buffer.size);
        render_pass.drawIndexed(mesh.index_count, @intCast(instances.len), 0, 0, 0);
    }

    pub fn drawColoredMeshes(self: *Frame, mesh: Mesh, shader: Shader, instances: []const MeshInstance, blend: bool) void {
        if (mesh.vertex_layout != .pos3_color4) return;
        if (instances.len == 0) return;
        const render_pass = self.render_pass orelse return;
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
        render_pass.setPipeline(pipeline);
        render_pass.setVertexBuffer(0, mesh.vertex_buffer.buffer, 0, mesh.vertex_buffer.size);
        render_pass.setVertexBuffer(1, self.renderer.instance_buffer.buffer, offset, total_bytes);
        render_pass.setIndexBuffer(mesh.index_buffer.buffer, .uint16, 0, mesh.index_buffer.size);
        render_pass.drawIndexed(mesh.index_count, @intCast(instances.len), 0, 0, 0);
    }

    pub fn drawShadowColoredMeshes(self: *Frame, mesh: Mesh, shader: ShadowShader, instances: []const MeshInstance) void {
        if (mesh.vertex_layout != .pos3_color4) return;
        if (shader.vertex_layout != .pos3_color4) return;
        if (instances.len == 0) return;
        const render_pass = self.render_pass orelse return;
        const total_bytes: usize = instances.len * @sizeOf(InstanceData);
        const offset = self.renderer.instance_ring.allocate(total_bytes, 256);

        var i: usize = 0;
        while (i < instances.len) : (i += 1) {
            const data = buildInstanceData(instances[i]);
            const bytes = std.mem.asBytes(&data);
            const byte_offset = offset + i * @sizeOf(InstanceData);
            self.renderer.queue.writeBuffer(self.renderer.instance_buffer.buffer, byte_offset, bytes.ptr, bytes.len);
        }

        render_pass.setPipeline(shader.pipeline);
        render_pass.setVertexBuffer(0, mesh.vertex_buffer.buffer, 0, mesh.vertex_buffer.size);
        render_pass.setVertexBuffer(1, self.renderer.instance_buffer.buffer, offset, total_bytes);
        render_pass.setIndexBuffer(mesh.index_buffer.buffer, .uint16, 0, mesh.index_buffer.size);
        render_pass.drawIndexed(mesh.index_count, @intCast(instances.len), 0, 0, 0);
    }

    pub fn drawPostProcess(
        self: *Frame,
        shader: PostProcessShader,
        source_slot: u32,
        params: [16]f32,
        source_size: Size,
        blend: bool,
    ) void {
        const render_pass = self.render_pass orelse return;
        const bind_group = self.renderer.postProcessBindGroup(source_slot) orelse return;
        const uniforms = PostProcessUniformData{
            .params0 = .{ params[0], params[1], params[2], params[3] },
            .params1 = .{ params[4], params[5], params[6], params[7] },
            .params2 = .{ params[8], params[9], params[10], params[11] },
            .params3 = .{ params[12], params[13], params[14], params[15] },
            .meta0 = .{
                1.0 / @as(f32, @floatFromInt(@max(source_size.width, 1))),
                1.0 / @as(f32, @floatFromInt(@max(source_size.height, 1))),
                @floatFromInt(source_size.width),
                @floatFromInt(source_size.height),
            },
        };
        const uniform_bytes = std.mem.asBytes(&uniforms);
        self.renderer.queue.writeBuffer(self.renderer.post_process_uniform_buffer.buffer, 0, uniform_bytes.ptr, uniform_bytes.len);

        const pipeline = if (blend) shader.pipeline_blend else shader.pipeline_opaque;
        render_pass.setPipeline(pipeline);
        render_pass.setBindGroup(0, bind_group, 0, null);
        render_pass.draw(3, 1, 0, 0);
    }

    pub fn endFrame(self: *Frame) !void {
        self.endPass();

        const command_buffer = self.encoder.finish(&wgpu.CommandBufferDescriptor{}) orelse return error.CommandBufferFailed;
        defer command_buffer.release();
        self.renderer.queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});

        _ = self.renderer.surface.present();
        self.surface_view.release();
        if (self.surface_texture.texture) |texture| {
            texture.release();
        }
        self.encoder.release();
    }

    fn beginPass(
        self: *Frame,
        target: FrameTarget,
        clear: Color,
        use_depth: bool,
        load_color: bool,
        depth_view_override: ?*wgpu.TextureView,
    ) !void {
        self.endPass();

        const clear_f = Color.F32.fromColor(clear);
        const target_view = switch (target) {
            .surface => self.surface_view,
            .texture => |texture| texture.view,
        };
        const color_attachment = wgpu.ColorAttachment{
            .view = target_view,
            .load_op = if (load_color) .load else .clear,
            .store_op = .store,
            .clear_value = wgpu.Color{
                .r = clear_f.r,
                .g = clear_f.g,
                .b = clear_f.b,
                .a = clear_f.a,
            },
        };
        const attachments = [_]wgpu.ColorAttachment{color_attachment};
        const depth_view = depth_view_override orelse self.renderer.depth_target.view;
        var depth_attachment = wgpu.DepthStencilAttachment{
            .view = depth_view,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .depth_clear_value = 1.0,
        };
        self.render_pass = self.encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .color_attachment_count = attachments.len,
            .color_attachments = attachments[0..].ptr,
            .depth_stencil_attachment = if (use_depth) &depth_attachment else null,
        }) orelse return error.RenderPassFailed;
    }

    fn beginDepthOnlyPass(self: *Frame, depth_view: *wgpu.TextureView, clear: Color) !void {
        _ = clear;
        self.endPass();

        const no_color_attachments = [_]wgpu.ColorAttachment{};
        var depth_attachment = wgpu.DepthStencilAttachment{
            .view = depth_view,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .depth_clear_value = 1.0,
        };
        self.render_pass = self.encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .color_attachment_count = 0,
            .color_attachments = no_color_attachments[0..].ptr,
            .depth_stencil_attachment = &depth_attachment,
        }) orelse return error.RenderPassFailed;
    }

    fn endPass(self: *Frame) void {
        if (self.render_pass) |render_pass| {
            render_pass.end();
            render_pass.release();
            self.render_pass = null;
        }
    }
};

fn buildInstanceData(instance: MeshInstance) InstanceData {
    const clip = instance.clip_transform.m;
    const model = instance.model_transform.m;
    return .{
        .clip0 = .{ clip[0][0], clip[0][1], clip[0][2], clip[0][3] },
        .clip1 = .{ clip[1][0], clip[1][1], clip[1][2], clip[1][3] },
        .clip2 = .{ clip[2][0], clip[2][1], clip[2][2], clip[2][3] },
        .clip3 = .{ clip[3][0], clip[3][1], clip[3][2], clip[3][3] },
        .model0 = .{ model[0][0], model[0][1], model[0][2], model[0][3] },
        .model1 = .{ model[1][0], model[1][1], model[1][2], model[1][3] },
        .model2 = .{ model[2][0], model[2][1], model[2][2], model[2][3] },
        .model3 = .{ model[3][0], model[3][1], model[3][2], model[3][3] },
        .color = instance.color,
        .pbr_params = instance.pbr_params,
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

fn createRenderTexture(device: *wgpu.Device, width: u32, height: u32, format: wgpu.TextureFormat) !Texture {
    const texture = device.createTexture(&wgpu.TextureDescriptor{
        .size = .{ .width = width, .height = height, .depth_or_array_layers = 1 },
        .format = format,
        .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.texture_binding,
        .mip_level_count = 1,
        .sample_count = 1,
        .dimension = .@"2d",
    }) orelse return error.TextureCreationFailed;
    errdefer texture.release();

    const view = texture.createView(&wgpu.TextureViewDescriptor{}) orelse return error.TextureViewFailed;
    return .{
        .texture = texture,
        .view = view,
        .width = width,
        .height = height,
        .format = format,
    };
}

fn createPostProcessBindGroup(
    device: *wgpu.Device,
    layout: *wgpu.BindGroupLayout,
    sampler: *wgpu.Sampler,
    texture_view: *wgpu.TextureView,
    uniform_buffer: *wgpu.Buffer,
) !*wgpu.BindGroup {
    const entries = [_]wgpu.BindGroupEntry{
        .{ .binding = 0, .sampler = sampler },
        .{ .binding = 1, .texture_view = texture_view },
        .{
            .binding = 2,
            .buffer = uniform_buffer,
            .offset = 0,
            .size = @sizeOf(PostProcessUniformData),
        },
    };
    return device.createBindGroup(&wgpu.BindGroupDescriptor{
        .layout = layout,
        .entry_count = entries.len,
        .entries = entries[0..].ptr,
    }) orelse error.BindGroupCreationFailed;
}

fn createShadowBindGroupLayout(device: *wgpu.Device) !*wgpu.BindGroupLayout {
    return device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
        .entry_count = 3,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.vertex | wgpu.ShaderStages.fragment,
                .buffer = .{
                    .type = .uniform,
                    .min_binding_size = @sizeOf(shadow_uniforms.ShadowUniforms),
                },
            },
            .{
                .binding = 1,
                .visibility = wgpu.ShaderStages.fragment,
                .sampler = .{ .type = .comparison },
            },
            .{
                .binding = 2,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .depth,
                    .view_dimension = .@"2d",
                    .multisampled = @intFromBool(false),
                },
            },
        },
    }) orelse error.BindGroupLayoutFailed;
}

fn createShadowBindGroup(
    device: *wgpu.Device,
    layout: *wgpu.BindGroupLayout,
    uniform_buffer: *wgpu.Buffer,
    sampler: *wgpu.Sampler,
    texture_view: *wgpu.TextureView,
) !*wgpu.BindGroup {
    const entries = [_]wgpu.BindGroupEntry{
        .{
            .binding = 0,
            .buffer = uniform_buffer,
            .offset = 0,
            .size = @sizeOf(shadow_uniforms.ShadowUniforms),
        },
        .{ .binding = 1, .sampler = sampler },
        .{ .binding = 2, .texture_view = texture_view },
    };
    return device.createBindGroup(&wgpu.BindGroupDescriptor{
        .layout = layout,
        .entry_count = entries.len,
        .entries = entries[0..].ptr,
    }) orelse error.BindGroupCreationFailed;
}

fn createComparisonSampler(device: *wgpu.Device) !Sampler {
    const sampler = device.createSampler(&wgpu.SamplerDescriptor{
        .mag_filter = .linear,
        .min_filter = .linear,
        .mipmap_filter = .nearest,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .compare = .less_equal,
    }) orelse return error.SamplerCreationFailed;
    return .{ .sampler = sampler };
}

fn destroyTextureStorage(texture: *Texture) void {
    texture.view.release();
    texture.texture.release();
}

fn writeHalf4(dst: []u8, src: []const f32) void {
    std.debug.assert(dst.len == 8);
    std.debug.assert(src.len == 4);
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const half_bits: u16 = @bitCast(@as(f16, @floatCast(src[i])));
        std.mem.writeInt(u16, dst[i * 2 ..][0..2], half_bits, .little);
    }
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

fn createSceneBindGroupLayout(device: *wgpu.Device) !*wgpu.BindGroupLayout {
    return device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
        .entry_count = 5,
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
            .{
                .binding = 2,
                .visibility = wgpu.ShaderStages.vertex | wgpu.ShaderStages.fragment,
                .buffer = .{
                    .type = .uniform,
                    .min_binding_size = @sizeOf(scene_uniforms.SceneUniforms),
                },
            },
            .{
                .binding = 3,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                    .multisampled = @intFromBool(false),
                },
            },
            .{
                .binding = 4,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                    .multisampled = @intFromBool(false),
                },
            },
        },
    }) orelse return error.BindGroupLayoutFailed;
}

fn createPostProcessBindGroupLayout(device: *wgpu.Device) !*wgpu.BindGroupLayout {
    return device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
        .entry_count = 3,
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
            .{
                .binding = 2,
                .visibility = wgpu.ShaderStages.fragment,
                .buffer = .{
                    .type = .uniform,
                    .min_binding_size = 80,
                },
            },
        },
    }) orelse return error.BindGroupLayoutFailed;
}

fn createSceneBindGroup(
    device: *wgpu.Device,
    layout: *wgpu.BindGroupLayout,
    sampler: *wgpu.Sampler,
    base_color_view: *wgpu.TextureView,
    metallic_roughness_view: *wgpu.TextureView,
    occlusion_view: *wgpu.TextureView,
    uniform_buffer: *wgpu.Buffer,
) !*wgpu.BindGroup {
    const entries = [_]wgpu.BindGroupEntry{
        .{ .binding = 0, .sampler = sampler },
        .{ .binding = 1, .texture_view = base_color_view },
        .{
            .binding = 2,
            .buffer = uniform_buffer,
            .offset = 0,
            .size = @sizeOf(scene_uniforms.SceneUniforms),
        },
        .{ .binding = 3, .texture_view = metallic_roughness_view },
        .{ .binding = 4, .texture_view = occlusion_view },
    };
    return device.createBindGroup(&wgpu.BindGroupDescriptor{
        .layout = layout,
        .entry_count = entries.len,
        .entries = entries[0..].ptr,
    }) orelse return error.BindGroupCreationFailed;
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
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 8, .shader_location = 6 },
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

fn createMeshTexturedPipeline(
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
        .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x2, .offset = @sizeOf([3]f32), .shader_location = 1 },
    };
    const instance_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x4, .offset = 0, .shader_location = 2 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 1, .shader_location = 3 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 2, .shader_location = 4 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 3, .shader_location = 5 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 8, .shader_location = 6 },
    };
    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .array_stride = @sizeOf(VertexPos3Uv),
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
}

fn shaderMatchesMesh(shader: Shader, layout: MeshVertexLayout) bool {
    return switch (shader.vertex_layout) {
        .uv2 => layout == .uv2,
        .pos3_color4 => layout == .pos3_color4,
        .pos3_uv2 => layout == .pos3_uv2,
        .pos3_norm_uv2 => layout == .pos3_norm_uv2,
    };
}

fn shadowShaderMatchesMesh(shader: ShadowShader, layout: MeshVertexLayout) bool {
    return switch (shader.vertex_layout) {
        .uv2 => layout == .uv2,
        .pos3_color4 => layout == .pos3_color4,
        .pos3_uv2 => layout == .pos3_uv2,
        .pos3_norm_uv2 => layout == .pos3_norm_uv2,
    };
}

fn createShadowPipeline(
    device: *wgpu.Device,
    vertex_shader: *wgpu.ShaderModule,
    depth_format_param: wgpu.TextureFormat,
    vertex_layout_kind: ShaderVertexLayout,
    binding_mode: ShaderBindingMode,
    material_bind_group_layout: *wgpu.BindGroupLayout,
) !*wgpu.RenderPipeline {
    if (binding_mode == .material_scene) return error.PipelineCreationFailed;

    const bind_group_layouts = [_]*wgpu.BindGroupLayout{material_bind_group_layout};
    const no_bind_group_layouts = [_]*wgpu.BindGroupLayout{};
    const bind_group_layout_count: usize = if (binding_mode == .material) 1 else 0;
    const pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
        .bind_group_layout_count = bind_group_layout_count,
        .bind_group_layouts = if (bind_group_layout_count > 0) bind_group_layouts[0..].ptr else no_bind_group_layouts[0..].ptr,
    }) orelse return error.PipelineLayoutFailed;
    defer pipeline_layout.release();

    const uv2_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x2, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x2, .offset = @sizeOf([2]f32), .shader_location = 1 },
    };
    const pos3_uv2_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x2, .offset = @sizeOf([3]f32), .shader_location = 1 },
    };
    const pos3_norm_uv2_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x3, .offset = @sizeOf([3]f32), .shader_location = 1 },
        .{ .format = .float32x2, .offset = @sizeOf([3]f32) * 2, .shader_location = 2 },
    };
    const pos3_color4_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x4, .offset = @sizeOf([3]f32), .shader_location = 1 },
    };
    const clip_rows_2 = [_]wgpu.VertexAttribute{
        .{ .format = .float32x4, .offset = 0, .shader_location = 2 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 1, .shader_location = 3 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 2, .shader_location = 4 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 3, .shader_location = 5 },
    };
    const clip_rows_3 = [_]wgpu.VertexAttribute{
        .{ .format = .float32x4, .offset = 0, .shader_location = 3 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 1, .shader_location = 4 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 2, .shader_location = 5 },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 3, .shader_location = 6 },
    };

    const vertex_buffers = switch (vertex_layout_kind) {
        .uv2 => [_]wgpu.VertexBufferLayout{
            .{
                .array_stride = @sizeOf(VertexUv),
                .attribute_count = uv2_attributes.len,
                .attributes = uv2_attributes[0..].ptr,
                .step_mode = .vertex,
            },
            .{
                .array_stride = @sizeOf(InstanceData),
                .attribute_count = clip_rows_2.len,
                .attributes = clip_rows_2[0..].ptr,
                .step_mode = .instance,
            },
        },
        .pos3_uv2 => [_]wgpu.VertexBufferLayout{
            .{
                .array_stride = @sizeOf(VertexPos3Uv),
                .attribute_count = pos3_uv2_attributes.len,
                .attributes = pos3_uv2_attributes[0..].ptr,
                .step_mode = .vertex,
            },
            .{
                .array_stride = @sizeOf(InstanceData),
                .attribute_count = clip_rows_2.len,
                .attributes = clip_rows_2[0..].ptr,
                .step_mode = .instance,
            },
        },
        .pos3_norm_uv2 => [_]wgpu.VertexBufferLayout{
            .{
                .array_stride = @sizeOf(VertexPos3NormUv),
                .attribute_count = pos3_norm_uv2_attributes.len,
                .attributes = pos3_norm_uv2_attributes[0..].ptr,
                .step_mode = .vertex,
            },
            .{
                .array_stride = @sizeOf(InstanceData),
                .attribute_count = clip_rows_3.len,
                .attributes = clip_rows_3[0..].ptr,
                .step_mode = .instance,
            },
        },
        .pos3_color4 => [_]wgpu.VertexBufferLayout{
            .{
                .array_stride = @sizeOf(VertexPos3Color),
                .attribute_count = pos3_color4_attributes.len,
                .attributes = pos3_color4_attributes[0..].ptr,
                .step_mode = .vertex,
            },
            .{
                .array_stride = @sizeOf(InstanceData),
                .attribute_count = clip_rows_2.len,
                .attributes = clip_rows_2[0..].ptr,
                .step_mode = .instance,
            },
        },
    };
    const depth_state = wgpu.DepthStencilState{
        .format = depth_format_param,
        .depth_write_enabled = .true,
        .depth_compare = .less_equal,
        .stencil_front = .{},
        .stencil_back = .{},
    };
    return device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .layout = pipeline_layout,
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
        .fragment = null,
        .multisample = wgpu.MultisampleState{},
    }) orelse return error.PipelineCreationFailed;
}

fn createCustomMaterialPipeline(
    device: *wgpu.Device,
    vertex_shader: *wgpu.ShaderModule,
    fragment_shader: *wgpu.ShaderModule,
    format: wgpu.TextureFormat,
    depth_format_param: wgpu.TextureFormat,
    bind_group_layout: *wgpu.BindGroupLayout,
    shadow_bind_group_layout: *wgpu.BindGroupLayout,
    vertex_layout_kind: ShaderVertexLayout,
    binding_mode: ShaderBindingMode,
    enable_blend: bool,
    depth_write_enabled: bool,
) !*wgpu.RenderPipeline {
    var bind_group_layouts = [_]*wgpu.BindGroupLayout{ bind_group_layout, shadow_bind_group_layout };
    const bind_group_layout_count: usize = if (binding_mode == .material_scene) 2 else 1;
    const pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
        .bind_group_layout_count = bind_group_layout_count,
        .bind_group_layouts = bind_group_layouts[0..].ptr,
    }) orelse return error.PipelineLayoutFailed;
    defer pipeline_layout.release();

    const uv2_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x2, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x2, .offset = @sizeOf([2]f32), .shader_location = 1 },
    };
    const pos3_uv_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x2, .offset = @sizeOf([3]f32), .shader_location = 1 },
    };
    const pos3_norm_uv_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x3, .offset = @sizeOf([3]f32), .shader_location = 1 },
        .{ .format = .float32x2, .offset = @sizeOf([3]f32) * 2, .shader_location = 2 },
    };
    const instance_attributes_default = [_]wgpu.VertexAttribute{
        .{ .format = .float32x4, .offset = 0, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 2,
            .pos3_uv2 => 2,
            .pos3_norm_uv2 => 3,
            else => 2,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 1, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 3,
            .pos3_uv2 => 3,
            .pos3_norm_uv2 => 4,
            else => 3,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 2, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 4,
            .pos3_uv2 => 4,
            .pos3_norm_uv2 => 5,
            else => 4,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 3, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 5,
            .pos3_uv2 => 5,
            .pos3_norm_uv2 => 6,
            else => 5,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 8, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 6,
            .pos3_uv2 => 6,
            .pos3_norm_uv2 => 7,
            else => 6,
        } },
    };
    const instance_attributes_scene = [_]wgpu.VertexAttribute{
        .{ .format = .float32x4, .offset = 0, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 2,
            .pos3_uv2 => 2,
            .pos3_norm_uv2 => 3,
            else => 2,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 1, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 3,
            .pos3_uv2 => 3,
            .pos3_norm_uv2 => 4,
            else => 3,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 2, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 4,
            .pos3_uv2 => 4,
            .pos3_norm_uv2 => 5,
            else => 4,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 3, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 5,
            .pos3_uv2 => 5,
            .pos3_norm_uv2 => 6,
            else => 5,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 4, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 6,
            .pos3_uv2 => 6,
            .pos3_norm_uv2 => 7,
            else => 6,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 5, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 7,
            .pos3_uv2 => 7,
            .pos3_norm_uv2 => 8,
            else => 7,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 6, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 8,
            .pos3_uv2 => 8,
            .pos3_norm_uv2 => 9,
            else => 8,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 7, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 9,
            .pos3_uv2 => 9,
            .pos3_norm_uv2 => 10,
            else => 9,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 8, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 10,
            .pos3_uv2 => 10,
            .pos3_norm_uv2 => 11,
            else => 10,
        } },
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 9, .shader_location = switch (vertex_layout_kind) {
            .uv2 => 11,
            .pos3_uv2 => 11,
            .pos3_norm_uv2 => 12,
            else => 11,
        } },
    };
    const instance_attributes = if (binding_mode == .material_scene) instance_attributes_scene[0..] else instance_attributes_default[0..];
    const vertex_buffers = switch (vertex_layout_kind) {
        .uv2 => [_]wgpu.VertexBufferLayout{
            .{
                .array_stride = @sizeOf(VertexUv),
                .attribute_count = uv2_attributes.len,
                .attributes = uv2_attributes[0..].ptr,
                .step_mode = .vertex,
            },
            .{
                .array_stride = @sizeOf(InstanceData),
                .attribute_count = instance_attributes.len,
                .attributes = instance_attributes[0..].ptr,
                .step_mode = .instance,
            },
        },
        .pos3_uv2 => [_]wgpu.VertexBufferLayout{
            .{
                .array_stride = @sizeOf(VertexPos3Uv),
                .attribute_count = pos3_uv_attributes.len,
                .attributes = pos3_uv_attributes[0..].ptr,
                .step_mode = .vertex,
            },
            .{
                .array_stride = @sizeOf(InstanceData),
                .attribute_count = instance_attributes.len,
                .attributes = instance_attributes[0..].ptr,
                .step_mode = .instance,
            },
        },
        .pos3_norm_uv2 => [_]wgpu.VertexBufferLayout{
            .{
                .array_stride = @sizeOf(VertexPos3NormUv),
                .attribute_count = pos3_norm_uv_attributes.len,
                .attributes = pos3_norm_uv_attributes[0..].ptr,
                .step_mode = .vertex,
            },
            .{
                .array_stride = @sizeOf(InstanceData),
                .attribute_count = instance_attributes.len,
                .attributes = instance_attributes[0..].ptr,
                .step_mode = .instance,
            },
        },
        else => return error.PipelineCreationFailed,
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
        .depth_write_enabled = if (depth_write_enabled) .true else .false,
        .depth_compare = .less_equal,
        .stencil_front = .{},
        .stencil_back = .{},
    };
    return device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .layout = pipeline_layout,
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
        .{ .format = .float32x4, .offset = @sizeOf([4]f32) * 8, .shader_location = 6 },
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

fn createPostProcessPipeline(
    device: *wgpu.Device,
    vertex_shader: *wgpu.ShaderModule,
    fragment_shader: *wgpu.ShaderModule,
    format: wgpu.TextureFormat,
    bind_group_layout: *wgpu.BindGroupLayout,
    enable_blend: bool,
) !*wgpu.RenderPipeline {
    const pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
        .bind_group_layout_count = 1,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{bind_group_layout},
    }) orelse return error.PipelineLayoutFailed;
    defer pipeline_layout.release();
    const vertex_buffers = [_]wgpu.VertexBufferLayout{};

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

    return device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .layout = pipeline_layout,
        .vertex = wgpu.VertexState{
            .module = vertex_shader,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = vertex_buffers.len,
            .buffers = vertex_buffers[0..].ptr,
        },
        .primitive = wgpu.PrimitiveState{
            .topology = .triangle_list,
        },
        .depth_stencil = null,
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

fn createShadowMapTexture(device: *wgpu.Device, width: u32, height: u32) !Texture {
    const texture = device.createTexture(&wgpu.TextureDescriptor{
        .size = .{ .width = width, .height = height, .depth_or_array_layers = 1 },
        .format = shadow_map_format,
        .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.texture_binding,
        .mip_level_count = 1,
        .sample_count = 1,
        .dimension = .@"2d",
    }) orelse return error.TextureCreationFailed;
    errdefer texture.release();

    const view = texture.createView(&wgpu.TextureViewDescriptor{}) orelse return error.TextureViewFailed;
    return .{
        .texture = texture,
        .view = view,
        .width = width,
        .height = height,
        .format = shadow_map_format,
    };
}

fn toWgpuFilter(filter: SamplerFilter) wgpu.FilterMode {
    return switch (filter) {
        .nearest => .nearest,
        .linear => .linear,
    };
}

fn toWgpuMipmapFilter(filter: SamplerFilter) wgpu.MipmapFilterMode {
    return switch (filter) {
        .nearest => .nearest,
        .linear => .linear,
    };
}

fn toWgpuAddressMode(mode: SamplerAddressMode) wgpu.AddressMode {
    return switch (mode) {
        .clamp_to_edge => .clamp_to_edge,
        .repeat => .repeat,
        .mirror_repeat => .mirror_repeat,
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
const meshTexturedShaderWGSL = @embedFile("shaders/mesh_textured.wgsl");
const postProcessVertexWGSL =
    \\struct VertexOut {
    \\    @builtin(position) position: vec4<f32>,
    \\    @location(0) uv: vec2<f32>,
    \\};
    \\
    \\@vertex
    \\fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOut {
    \\    var positions = array<vec2<f32>, 3>(
    \\        vec2<f32>(-1.0, -3.0),
    \\        vec2<f32>(-1.0, 1.0),
    \\        vec2<f32>(3.0, 1.0),
    \\    );
    \\    var uvs = array<vec2<f32>, 3>(
    \\        vec2<f32>(0.0, 2.0),
    \\        vec2<f32>(0.0, 0.0),
    \\        vec2<f32>(2.0, 0.0),
    \\    );
    \\    var out: VertexOut;
    \\    out.position = vec4<f32>(positions[vertex_index], 0.0, 1.0);
    \\    out.uv = uvs[vertex_index];
    \\    return out;
    \\}
;

// Imports
const std = @import("std");
const wgpu = @import("wgpu");
const utils = @import("utils.zig");
const common = @import("common");
const scene_uniforms = @import("scene_uniforms.zig");
const shadow_uniforms = @import("shadow_uniforms.zig");

const Color = common.Color;
const Size = utils.Size;
const SurfaceTarget = utils.SurfaceTarget;
const NativeSurface = utils.NativeSurface;
const NativeHandle = utils.NativeHandle;
const CacheKey = utils.CacheKey;
const hashCacheKey = utils.hashCacheKey;
const RingBuffer = utils.RingBuffer;
