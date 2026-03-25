pub const RendererConfig = struct {
    present_mode: ?u32 = null,
    enable_validation: bool = false,
};

pub fn configForVsync(_: bool) RendererConfig {
    return .{};
}

pub const Buffer = struct {
    handle: u32 = 0,
    size: u64 = 0,
};

pub const Texture = struct {
    handle: u32,
    width: u32,
    height: u32,
};

pub const Sampler = struct {
    handle: u32,
};

pub const SamplerFilter = enum(u8) {
    nearest = 0,
    linear = 1,
};

pub const SamplerAddressMode = enum(u8) {
    clamp_to_edge = 0,
    repeat = 1,
    mirror_repeat = 2,
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
    handle: u32,
};

pub const Shader = struct {
    handle: u32,
    vertex_layout: ShaderVertexLayout,
    binding_mode: ShaderBindingMode,
};

pub const ShadowShader = struct {
    handle: u32,
    vertex_layout: ShaderVertexLayout,
    binding_mode: ShaderBindingMode,
};

pub const PostProcessShader = struct {
    handle: u32,
};

pub const FrameTarget = union(enum) {
    surface,
    slot: u32,
};

pub const Material = struct {
    handle: u32,
};

pub const SceneMaterialBinding = struct {
    base_color_texture: Texture,
    metallic_roughness_texture: Texture,
    occlusion_texture: Texture,
    normal_texture: Texture,
};

pub const ShaderSource = struct {
    wgsl: ?[]const u8 = null,
    glsl_vertex: ?[]const u8 = null,
    glsl_fragment: ?[]const u8 = null,
    vertex_layout: ShaderVertexLayout = .pos3_color4,
    binding_mode: ShaderBindingMode = .none,
};

pub const ShaderVertexLayout = enum(u32) {
    uv2 = 0,
    pos3_color4 = 1,
    pos3_uv2 = 2,
    pos3_norm_uv2 = 3,
    pos3_norm_tangent_uv2 = 4,
};

pub const ShaderBindingMode = enum(u32) {
    none = 0,
    material = 1,
    material_scene = 2,
    material_scene_env = 3,
};

pub const MeshVertexLayout = enum(u32) {
    uv2 = 1,
    pos3_uv2 = 2,
    pos3_color4 = 3,
    pos3_norm_uv2 = 4,
    pos3_norm_tangent_uv2 = 5,
};

pub const Mesh = struct {
    handle: u32,
    vertex_layout: MeshVertexLayout,
    local_bounds_min: common.Vec3 = .{},
    local_bounds_max: common.Vec3 = .{},
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

pub const VertexPos3NormTangentUv = extern struct {
    position: [3]f32,
    normal: [3]f32,
    tangent: [4]f32,
    uv: [2]f32,
};

pub const VertexPos3Color = extern struct {
    position: [3]f32,
    color: [4]f32,
};

fn boundsFromVertexUv(vertices: []const VertexUv) [2]common.Vec3 {
    return boundsFromPos2(vertices, struct {
        fn position(vertex: VertexUv) [2]f32 {
            return vertex.position;
        }
    }.position);
}

fn boundsFromVertexPos3Uv(vertices: []const VertexPos3Uv) [2]common.Vec3 {
    return boundsFromPos3(vertices, struct {
        fn position(vertex: VertexPos3Uv) [3]f32 {
            return vertex.position;
        }
    }.position);
}

fn boundsFromVertexPos3NormUv(vertices: []const VertexPos3NormUv) [2]common.Vec3 {
    return boundsFromPos3(vertices, struct {
        fn position(vertex: VertexPos3NormUv) [3]f32 {
            return vertex.position;
        }
    }.position);
}

fn boundsFromVertexPos3NormTangentUv(vertices: []const VertexPos3NormTangentUv) [2]common.Vec3 {
    return boundsFromPos3(vertices, struct {
        fn position(vertex: VertexPos3NormTangentUv) [3]f32 {
            return vertex.position;
        }
    }.position);
}

fn boundsFromVertexPos3Color(vertices: []const VertexPos3Color) [2]common.Vec3 {
    return boundsFromPos3(vertices, struct {
        fn position(vertex: VertexPos3Color) [3]f32 {
            return vertex.position;
        }
    }.position);
}

fn boundsFromPos2(vertices: anytype, comptime position_fn: fn (@typeInfo(@TypeOf(vertices)).pointer.child) [2]f32) [2]common.Vec3 {
    if (vertices.len == 0) return .{ .{}, .{} };
    const first = position_fn(vertices[0]);
    var min = common.Vec3{ .x = first[0], .y = first[1], .z = 0.0 };
    var max = min;
    for (vertices[1..]) |vertex| {
        const position = position_fn(vertex);
        min.x = @min(min.x, position[0]);
        min.y = @min(min.y, position[1]);
        max.x = @max(max.x, position[0]);
        max.y = @max(max.y, position[1]);
    }
    return .{ min, max };
}

fn boundsFromPos3(vertices: anytype, comptime position_fn: fn (@typeInfo(@TypeOf(vertices)).pointer.child) [3]f32) [2]common.Vec3 {
    if (vertices.len == 0) return .{ .{}, .{} };
    const first = position_fn(vertices[0]);
    var min = common.Vec3{ .x = first[0], .y = first[1], .z = first[2] };
    var max = min;
    for (vertices[1..]) |vertex| {
        const position = position_fn(vertex);
        min.x = @min(min.x, position[0]);
        min.y = @min(min.y, position[1]);
        min.z = @min(min.z, position[2]);
        max.x = @max(max.x, position[0]);
        max.y = @max(max.y, position[1]);
        max.z = @max(max.z, position[2]);
    }
    return .{ min, max };
}

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

extern "env" fn webgpu_init(canvas_id_ptr: [*]const u8, canvas_id_len: usize, enable_validation: bool) u32;
extern "env" fn webgpu_deinit(ctx: u32) void;
extern "env" fn webgpu_resize(ctx: u32, width: u32, height: u32) void;
extern "env" fn webgpu_begin_frame(ctx: u32, clear_r: f32, clear_g: f32, clear_b: f32, clear_a: f32) void;
extern "env" fn webgpu_begin_scene_pass(ctx: u32, target_slot: u32, clear_r: f32, clear_g: f32, clear_b: f32, clear_a: f32) void;
extern "env" fn webgpu_begin_scene_pass_load(ctx: u32, target_slot: u32) void;
extern "env" fn webgpu_begin_shadow_pass(ctx: u32, target_slot: u32) void;
extern "env" fn webgpu_begin_post_process_pass(ctx: u32, target_slot: u32, clear_r: f32, clear_g: f32, clear_b: f32, clear_a: f32) void;
extern "env" fn webgpu_draw_triangle(ctx: u32) void;
extern "env" fn webgpu_draw_textured_quad(ctx: u32, mesh_handle: u32, material_handle: u32, instance_ptr: *const InstanceData, blend: u32) void;
extern "env" fn webgpu_draw_textured_quads(ctx: u32, mesh_handle: u32, material_handle: u32, instance_ptr: [*]const MeshInstance, instance_count: u32, blend: u32) void;
extern "env" fn webgpu_draw_colored_meshes(ctx: u32, mesh_handle: u32, shader_handle: u32, instance_ptr: [*]const MeshInstance, instance_count: u32, blend: u32) void;
extern "env" fn webgpu_draw_textured_meshes_with_shader(ctx: u32, mesh_handle: u32, material_handle: u32, shader_handle: u32, instance_ptr: [*]const MeshInstance, instance_count: u32, blend: u32) void;
extern "env" fn webgpu_draw_shadow_colored_meshes(ctx: u32, mesh_handle: u32, shader_handle: u32, instance_ptr: [*]const MeshInstance, instance_count: u32) void;
extern "env" fn webgpu_draw_shadow_textured_meshes_with_shader(ctx: u32, mesh_handle: u32, material_handle: u32, shader_handle: u32, instance_ptr: [*]const MeshInstance, instance_count: u32) void;
extern "env" fn webgpu_set_scene_uniforms(ctx: u32, uniforms_ptr: [*]const u8, uniforms_len: usize) void;
extern "env" fn webgpu_set_shadow_state(
    ctx: u32,
    slot: u32,
    width: u32,
    height: u32,
    uniforms_ptr: [*]const u8,
    uniforms_len: usize,
) void;
extern "env" fn webgpu_draw_post_process(ctx: u32, shader_handle: u32, source_slot: u32, uniforms_ptr: [*]const f32, blend: u32) void;
extern "env" fn webgpu_end_frame(ctx: u32) void;
extern "env" fn webgpu_set_viewport_scissor(ctx: u32, x: f32, y: f32, width: f32, height: f32) void;
extern "env" fn webgpu_create_sampler(ctx: u32) u32;
extern "env" fn webgpu_create_sampler_desc(ctx: u32, mag_filter: u32, min_filter: u32, mipmap_filter: u32, address_mode_u: u32, address_mode_v: u32, address_mode_w: u32) u32;
extern "env" fn webgpu_destroy_sampler(ctx: u32, handle: u32) void;
extern "env" fn webgpu_create_texture_rgba8(ctx: u32, sampler_handle: u32, data_ptr: [*]const u8, data_len: usize, width: u32, height: u32) u32;
extern "env" fn webgpu_create_texture_rgba8_linear(ctx: u32, sampler_handle: u32, data_ptr: [*]const u8, data_len: usize, width: u32, height: u32) u32;
extern "env" fn webgpu_create_texture_rgba16f(ctx: u32, sampler_handle: u32, data_ptr: [*]const f32, data_len: usize, width: u32, height: u32) u32;
extern "env" fn webgpu_destroy_texture(ctx: u32, handle: u32) void;
extern "env" fn webgpu_create_mesh(ctx: u32, vertex_layout: u32, vertices_ptr: [*]const u8, vertices_len: usize, indices_ptr: [*]const u8, indices_len: usize) u32;
extern "env" fn webgpu_update_mesh(ctx: u32, handle: u32, vertices_ptr: [*]const u8, vertices_len: usize, indices_ptr: [*]const u8, indices_len: usize) void;
extern "env" fn webgpu_destroy_mesh(ctx: u32, handle: u32) void;
extern "env" fn webgpu_create_shader(ctx: u32, wgsl_ptr: [*]const u8, wgsl_len: usize) u32;
extern "env" fn webgpu_create_shader_configured(ctx: u32, wgsl_ptr: [*]const u8, wgsl_len: usize, vertex_layout: u32, binding_mode: u32) u32;
extern "env" fn webgpu_create_shadow_shader_configured(ctx: u32, wgsl_ptr: [*]const u8, wgsl_len: usize, vertex_layout: u32, binding_mode: u32) u32;
extern "env" fn webgpu_destroy_shader(ctx: u32, handle: u32) void;
extern "env" fn webgpu_destroy_shadow_shader(ctx: u32, handle: u32) void;
extern "env" fn webgpu_create_post_process_shader(ctx: u32, wgsl_ptr: [*]const u8, wgsl_len: usize) u32;
extern "env" fn webgpu_destroy_post_process_shader(ctx: u32, handle: u32) void;
extern "env" fn webgpu_create_material(ctx: u32, texture_handle: u32, sampler_handle: u32) u32;
extern "env" fn webgpu_create_scene_material(ctx: u32, base_color_texture_handle: u32, metallic_roughness_texture_handle: u32, occlusion_texture_handle: u32, normal_texture_handle: u32, sampler_handle: u32) u32;
extern "env" fn webgpu_destroy_material(ctx: u32, handle: u32) void;
extern "env" fn webgpu_set_scene_environment(ctx: u32, texture_handle: u32) void;
extern "env" fn webgpu_reset_scene_environment(ctx: u32) void;
extern "env" fn webgpu_stats(ctx: u32, out_ptr: *RendererStats) void;
extern "env" fn webgpu_ensure_shadow_map_slot(ctx: u32, slot: u32, width: u32, height: u32) u32;

pub const Renderer = struct {
    ctx: u32,
    surface_size: Size,

    pub fn init(_: std.mem.Allocator, target: SurfaceTarget, config: RendererConfig) !Renderer {
        if (!builtin.target.cpu.arch.isWasm()) return error.InvalidTarget;
        if (target != .web) return error.InvalidSurfaceTarget;
        const canvas = target.web;
        const ctx = webgpu_init(canvas.canvas_id.ptr, canvas.canvas_id.len, config.enable_validation);
        if (ctx == 0) return error.WebGpuInitFailed;
        return Renderer{
            .ctx = ctx,
            .surface_size = canvas.size,
        };
    }

    pub fn deinit(self: *Renderer) void {
        webgpu_deinit(self.ctx);
    }

    pub fn resize(self: *Renderer, width: u32, height: u32) void {
        if (width == 0 or height == 0) return;
        self.surface_size = .{ .width = width, .height = height };
        webgpu_resize(self.ctx, width, height);
    }

    pub fn beginFrame(self: *Renderer) !Frame {
        webgpu_begin_frame(self.ctx, 0.0, 0.0, 0.0, 0.0);
        return Frame{ .renderer = self };
    }

    pub fn createSampler(self: *Renderer) !Sampler {
        return self.createSamplerWithDescriptor(.{});
    }

    pub fn createSamplerWithDescriptor(self: *Renderer, descriptor: SamplerDescriptor) !Sampler {
        return Sampler{ .handle = webgpu_create_sampler_desc(
            self.ctx,
            @intFromEnum(descriptor.mag_filter),
            @intFromEnum(descriptor.min_filter),
            @intFromEnum(descriptor.mipmap_filter),
            @intFromEnum(descriptor.address_mode_u),
            @intFromEnum(descriptor.address_mode_v),
            @intFromEnum(descriptor.address_mode_w),
        ) };
    }

    pub fn destroySampler(self: *Renderer, sampler: *Sampler) void {
        if (sampler.handle == 0) return;
        webgpu_destroy_sampler(self.ctx, sampler.handle);
        sampler.handle = 0;
    }

    pub fn createTextureRgba8(self: *Renderer, width: u32, height: u32, data: []const u8) !Texture {
        const handle = webgpu_create_texture_rgba8(self.ctx, 0, data.ptr, data.len, width, height);
        return Texture{
            .handle = handle,
            .width = width,
            .height = height,
        };
    }

    pub fn createTextureRgba8Linear(self: *Renderer, width: u32, height: u32, data: []const u8) !Texture {
        const handle = webgpu_create_texture_rgba8_linear(self.ctx, 0, data.ptr, data.len, width, height);
        return Texture{
            .handle = handle,
            .width = width,
            .height = height,
        };
    }

    pub fn createTextureRgba16Float(self: *Renderer, width: u32, height: u32, data: []const f32) !Texture {
        const handle = webgpu_create_texture_rgba16f(self.ctx, 0, data.ptr, data.len, width, height);
        return Texture{
            .handle = handle,
            .width = width,
            .height = height,
        };
    }

    pub fn createTextureRgba16FloatMipmapped(self: *Renderer, width: u32, height: u32, data: []const f32) !Texture {
        // The WebGPU bridge currently uploads a single rgba16float level only.
        return self.createTextureRgba16Float(width, height, data);
    }

    pub fn destroyTexture(self: *Renderer, texture: *Texture) void {
        if (texture.handle == 0) return;
        webgpu_destroy_texture(self.ctx, texture.handle);
        texture.handle = 0;
    }

    pub fn createMaterial(self: *Renderer, texture: Texture, sampler: Sampler) !Material {
        const handle = webgpu_create_material(self.ctx, texture.handle, sampler.handle);
        return Material{ .handle = handle };
    }

    pub fn createSceneMaterial(self: *Renderer, binding: SceneMaterialBinding, sampler: Sampler) !Material {
        const handle = webgpu_create_scene_material(
            self.ctx,
            binding.base_color_texture.handle,
            binding.metallic_roughness_texture.handle,
            binding.occlusion_texture.handle,
            binding.normal_texture.handle,
            sampler.handle,
        );
        return Material{ .handle = handle };
    }

    pub fn destroyMaterial(self: *Renderer, material: *Material) void {
        if (material.handle == 0) return;
        webgpu_destroy_material(self.ctx, material.handle);
        material.handle = 0;
    }

    pub fn setSceneEnvironment(self: *Renderer, texture: Texture) !void {
        if (texture.handle == 0) return error.InvalidTexture;
        webgpu_set_scene_environment(self.ctx, texture.handle);
    }

    pub fn resetSceneEnvironment(self: *Renderer) !void {
        webgpu_reset_scene_environment(self.ctx);
    }

    pub fn createMeshUv(self: *Renderer, vertices: []const VertexUv, indices: []const u16) !Mesh {
        const vbytes = std.mem.sliceAsBytes(vertices);
        const ibytes = std.mem.sliceAsBytes(indices);
        const handle = webgpu_create_mesh(self.ctx, @intFromEnum(MeshVertexLayout.uv2), vbytes.ptr, vbytes.len, ibytes.ptr, ibytes.len);
        const bounds = boundsFromVertexUv(vertices);
        return Mesh{ .handle = handle, .vertex_layout = .uv2, .local_bounds_min = bounds[0], .local_bounds_max = bounds[1] };
    }

    pub fn updateMeshUv(self: *Renderer, mesh: *Mesh, vertices: []const VertexUv, indices: []const u16) !void {
        if (mesh.vertex_layout != .uv2) return error.InvalidMeshLayout;
        if (mesh.handle == 0) return;
        const vbytes = std.mem.sliceAsBytes(vertices);
        const ibytes = std.mem.sliceAsBytes(indices);
        webgpu_update_mesh(self.ctx, mesh.handle, vbytes.ptr, vbytes.len, ibytes.ptr, ibytes.len);
        const bounds = boundsFromVertexUv(vertices);
        mesh.local_bounds_min = bounds[0];
        mesh.local_bounds_max = bounds[1];
    }

    pub fn createMeshPos3Uv(self: *Renderer, vertices: []const VertexPos3Uv, indices: []const u16) !Mesh {
        const vbytes = std.mem.sliceAsBytes(vertices);
        const ibytes = std.mem.sliceAsBytes(indices);
        const handle = webgpu_create_mesh(self.ctx, @intFromEnum(MeshVertexLayout.pos3_uv2), vbytes.ptr, vbytes.len, ibytes.ptr, ibytes.len);
        const bounds = boundsFromVertexPos3Uv(vertices);
        return Mesh{ .handle = handle, .vertex_layout = .pos3_uv2, .local_bounds_min = bounds[0], .local_bounds_max = bounds[1] };
    }

    pub fn updateMeshPos3Uv(self: *Renderer, mesh: *Mesh, vertices: []const VertexPos3Uv, indices: []const u16) !void {
        if (mesh.vertex_layout != .pos3_uv2) return error.InvalidMeshLayout;
        if (mesh.handle == 0) return;
        const vbytes = std.mem.sliceAsBytes(vertices);
        const ibytes = std.mem.sliceAsBytes(indices);
        webgpu_update_mesh(self.ctx, mesh.handle, vbytes.ptr, vbytes.len, ibytes.ptr, ibytes.len);
        const bounds = boundsFromVertexPos3Uv(vertices);
        mesh.local_bounds_min = bounds[0];
        mesh.local_bounds_max = bounds[1];
    }

    pub fn createMeshPos3NormUv(self: *Renderer, vertices: []const VertexPos3NormUv, indices: []const u16) !Mesh {
        const vbytes = std.mem.sliceAsBytes(vertices);
        const ibytes = std.mem.sliceAsBytes(indices);
        const handle = webgpu_create_mesh(self.ctx, @intFromEnum(MeshVertexLayout.pos3_norm_uv2), vbytes.ptr, vbytes.len, ibytes.ptr, ibytes.len);
        const bounds = boundsFromVertexPos3NormUv(vertices);
        return Mesh{ .handle = handle, .vertex_layout = .pos3_norm_uv2, .local_bounds_min = bounds[0], .local_bounds_max = bounds[1] };
    }

    pub fn updateMeshPos3NormUv(self: *Renderer, mesh: *Mesh, vertices: []const VertexPos3NormUv, indices: []const u16) !void {
        if (mesh.vertex_layout != .pos3_norm_uv2) return error.InvalidMeshLayout;
        if (mesh.handle == 0) return;
        const vbytes = std.mem.sliceAsBytes(vertices);
        const ibytes = std.mem.sliceAsBytes(indices);
        webgpu_update_mesh(self.ctx, mesh.handle, vbytes.ptr, vbytes.len, ibytes.ptr, ibytes.len);
        const bounds = boundsFromVertexPos3NormUv(vertices);
        mesh.local_bounds_min = bounds[0];
        mesh.local_bounds_max = bounds[1];
    }

    pub fn createMeshPos3NormTangentUv(self: *Renderer, vertices: []const VertexPos3NormTangentUv, indices: []const u16) !Mesh {
        const vbytes = std.mem.sliceAsBytes(vertices);
        const ibytes = std.mem.sliceAsBytes(indices);
        const handle = webgpu_create_mesh(self.ctx, @intFromEnum(MeshVertexLayout.pos3_norm_tangent_uv2), vbytes.ptr, vbytes.len, ibytes.ptr, ibytes.len);
        const bounds = boundsFromVertexPos3NormTangentUv(vertices);
        return Mesh{ .handle = handle, .vertex_layout = .pos3_norm_tangent_uv2, .local_bounds_min = bounds[0], .local_bounds_max = bounds[1] };
    }

    pub fn updateMeshPos3NormTangentUv(self: *Renderer, mesh: *Mesh, vertices: []const VertexPos3NormTangentUv, indices: []const u16) !void {
        if (mesh.vertex_layout != .pos3_norm_tangent_uv2) return error.InvalidMeshLayout;
        if (mesh.handle == 0) return;
        const vbytes = std.mem.sliceAsBytes(vertices);
        const ibytes = std.mem.sliceAsBytes(indices);
        webgpu_update_mesh(self.ctx, mesh.handle, vbytes.ptr, vbytes.len, ibytes.ptr, ibytes.len);
        const bounds = boundsFromVertexPos3NormTangentUv(vertices);
        mesh.local_bounds_min = bounds[0];
        mesh.local_bounds_max = bounds[1];
    }

    pub fn createMeshPos3Color(self: *Renderer, vertices: []const VertexPos3Color, indices: []const u16) !Mesh {
        const vbytes = std.mem.sliceAsBytes(vertices);
        const ibytes = std.mem.sliceAsBytes(indices);
        const handle = webgpu_create_mesh(self.ctx, @intFromEnum(MeshVertexLayout.pos3_color4), vbytes.ptr, vbytes.len, ibytes.ptr, ibytes.len);
        const bounds = boundsFromVertexPos3Color(vertices);
        return Mesh{ .handle = handle, .vertex_layout = .pos3_color4, .local_bounds_min = bounds[0], .local_bounds_max = bounds[1] };
    }

    pub fn updateMeshPos3Color(self: *Renderer, mesh: *Mesh, vertices: []const VertexPos3Color, indices: []const u16) !void {
        if (mesh.vertex_layout != .pos3_color4) return error.InvalidMeshLayout;
        if (mesh.handle == 0) return;
        const vbytes = std.mem.sliceAsBytes(vertices);
        const ibytes = std.mem.sliceAsBytes(indices);
        webgpu_update_mesh(self.ctx, mesh.handle, vbytes.ptr, vbytes.len, ibytes.ptr, ibytes.len);
        const bounds = boundsFromVertexPos3Color(vertices);
        mesh.local_bounds_min = bounds[0];
        mesh.local_bounds_max = bounds[1];
    }

    pub fn destroyMesh(self: *Renderer, mesh: *Mesh) void {
        if (mesh.handle == 0) return;
        webgpu_destroy_mesh(self.ctx, mesh.handle);
        mesh.handle = 0;
    }

    pub fn createShader(self: *Renderer, source: ShaderSource) !Shader {
        const wgsl = source.wgsl orelse return error.MissingShaderSource;
        const handle = webgpu_create_shader_configured(
            self.ctx,
            wgsl.ptr,
            wgsl.len,
            @intFromEnum(source.vertex_layout),
            @intFromEnum(source.binding_mode),
        );
        if (handle == 0) return error.ShaderCreationFailed;
        return Shader{
            .handle = handle,
            .vertex_layout = source.vertex_layout,
            .binding_mode = source.binding_mode,
        };
    }

    pub fn createShadowShader(self: *Renderer, source: ShaderSource) !ShadowShader {
        const wgsl = source.wgsl orelse return error.MissingShaderSource;
        const handle = webgpu_create_shadow_shader_configured(
            self.ctx,
            wgsl.ptr,
            wgsl.len,
            @intFromEnum(source.vertex_layout),
            @intFromEnum(source.binding_mode),
        );
        if (handle == 0) return error.ShaderCreationFailed;
        return .{
            .handle = handle,
            .vertex_layout = source.vertex_layout,
            .binding_mode = source.binding_mode,
        };
    }

    pub fn destroyShader(self: *Renderer, shader: *Shader) void {
        if (shader.handle == 0) return;
        webgpu_destroy_shader(self.ctx, shader.handle);
        shader.handle = 0;
    }

    pub fn destroyShadowShader(self: *Renderer, shader: *ShadowShader) void {
        if (shader.handle == 0) return;
        webgpu_destroy_shadow_shader(self.ctx, shader.handle);
        shader.handle = 0;
    }

    pub fn createPostProcessShader(self: *Renderer, source: ShaderSource) !PostProcessShader {
        const wgsl = source.wgsl orelse return error.MissingShaderSource;
        const handle = webgpu_create_post_process_shader(self.ctx, wgsl.ptr, wgsl.len);
        if (handle == 0) return error.ShaderCreationFailed;
        return PostProcessShader{ .handle = handle };
    }

    pub fn destroyPostProcessShader(self: *Renderer, shader: *PostProcessShader) void {
        if (shader.handle == 0) return;
        webgpu_destroy_post_process_shader(self.ctx, shader.handle);
        shader.handle = 0;
    }

    pub fn ensurePostProcessSlot(_: *Renderer, slot_index: u32, _: u32, _: u32) !u32 {
        return slot_index;
    }

    pub fn ensureShadowMapSlot(self: *Renderer, slot_index: u32, width: u32, height: u32) !u32 {
        return webgpu_ensure_shadow_map_slot(self.ctx, slot_index, width, height);
    }

    pub fn stats(self: *const Renderer) RendererStats {
        var out: RendererStats = .{};
        webgpu_stats(self.ctx, &out);
        return out;
    }
};

pub const Frame = struct {
    renderer: *Renderer,

    pub fn draw(self: *Frame, cmd: DrawCmd) void {
        switch (cmd) {
            .triangle => webgpu_draw_triangle(self.renderer.ctx),
            .textured_quad => |quad| self.drawTexturedQuad(quad),
        }
    }

    pub fn beginScenePass(self: *Frame, target: FrameTarget, clear: Color) !void {
        const clear_f = Color.F32.fromColor(clear);
        webgpu_begin_scene_pass(self.renderer.ctx, targetSlotValue(target), clear_f.r, clear_f.g, clear_f.b, clear_f.a);
    }

    pub fn beginScenePassLoad(self: *Frame, target: FrameTarget) !void {
        webgpu_begin_scene_pass_load(self.renderer.ctx, targetSlotValue(target));
    }

    pub fn beginShadowPass(self: *Frame, target: FrameTarget, clear: Color) !void {
        _ = clear;
        webgpu_begin_shadow_pass(self.renderer.ctx, targetSlotValue(target));
    }

    pub fn beginPostProcessPass(self: *Frame, target: FrameTarget, clear: Color) !void {
        const clear_f = Color.F32.fromColor(clear);
        webgpu_begin_post_process_pass(self.renderer.ctx, targetSlotValue(target), clear_f.r, clear_f.g, clear_f.b, clear_f.a);
    }

    pub fn setViewportScissor(self: *Frame, x: f32, y: f32, width: f32, height: f32) void {
        webgpu_set_viewport_scissor(self.renderer.ctx, x, y, width, height);
    }

    pub fn setSceneUniforms(self: *Frame, uniforms: scene_uniforms.SceneUniforms) void {
        const bytes = std.mem.asBytes(&uniforms);
        webgpu_set_scene_uniforms(self.renderer.ctx, bytes.ptr, bytes.len);
    }

    pub fn setShadowUniforms(self: *Frame, uniforms: shadow_uniforms.ShadowUniforms, slot_index: u32, slot_size: Size) void {
        const bytes = std.mem.asBytes(&uniforms);
        webgpu_set_shadow_state(
            self.renderer.ctx,
            slot_index,
            slot_size.width,
            slot_size.height,
            bytes.ptr,
            bytes.len,
        );
    }

    pub fn drawShadowTexturedMeshesWithShader(self: *Frame, mesh: Mesh, material: Material, shader: ShadowShader, instances: []const MeshInstance) void {
        if (instances.len == 0) return;
        webgpu_draw_shadow_textured_meshes_with_shader(
            self.renderer.ctx,
            mesh.handle,
            material.handle,
            shader.handle,
            instances.ptr,
            @intCast(instances.len),
        );
    }

    pub fn drawShadowColoredMeshes(self: *Frame, mesh: Mesh, shader: ShadowShader, instances: []const MeshInstance) void {
        if (instances.len == 0) return;
        webgpu_draw_shadow_colored_meshes(
            self.renderer.ctx,
            mesh.handle,
            shader.handle,
            instances.ptr,
            @intCast(instances.len),
        );
    }

    fn drawTexturedQuad(self: *Frame, quad: TexturedQuad) void {
        if (quad.mesh.vertex_layout != .uv2) return;
        const instance = buildInstanceData(quad.instance);
        const blend: u32 = if (quad.blend) 1 else 0;
        webgpu_draw_textured_quad(self.renderer.ctx, quad.mesh.handle, quad.material.handle, &instance, blend);
    }

    pub fn drawTexturedQuads(self: *Frame, mesh: Mesh, material: Material, instances: []const MeshInstance, blend: bool) void {
        switch (mesh.vertex_layout) {
            .uv2, .pos3_uv2 => {},
            else => return,
        }
        if (instances.len == 0) return;
        const blend_flag: u32 = if (blend) 1 else 0;
        webgpu_draw_textured_quads(
            self.renderer.ctx,
            mesh.handle,
            material.handle,
            instances.ptr,
            @intCast(instances.len),
            blend_flag,
        );
    }

    pub fn drawColoredMeshes(self: *Frame, mesh: Mesh, shader: Shader, instances: []const MeshInstance, blend: bool) void {
        if (mesh.vertex_layout != .pos3_color4) return;
        if (instances.len == 0) return;
        const blend_flag: u32 = if (blend) 1 else 0;
        webgpu_draw_colored_meshes(
            self.renderer.ctx,
            mesh.handle,
            shader.handle,
            instances.ptr,
            @intCast(instances.len),
            blend_flag,
        );
    }

    pub fn drawTexturedMeshesWithShader(self: *Frame, mesh: Mesh, material: Material, shader: Shader, instances: []const MeshInstance, blend: bool) void {
        if (instances.len == 0) return;
        const blend_flag: u32 = if (blend) 1 else 0;
        webgpu_draw_textured_meshes_with_shader(
            self.renderer.ctx,
            mesh.handle,
            material.handle,
            shader.handle,
            instances.ptr,
            @intCast(instances.len),
            blend_flag,
        );
    }

    pub fn drawPostProcess(
        self: *Frame,
        shader: PostProcessShader,
        source_slot: u32,
        params: [16]f32,
        source_size: Size,
        blend: bool,
    ) void {
        if (shader.handle == 0) return;
        var uniforms = [20]f32{
            params[0],                                                 params[1],                                                  params[2],                        params[3],
            params[4],                                                 params[5],                                                  params[6],                        params[7],
            params[8],                                                 params[9],                                                  params[10],                       params[11],
            params[12],                                                params[13],                                                 params[14],                       params[15],
            1.0 / @as(f32, @floatFromInt(@max(source_size.width, 1))), 1.0 / @as(f32, @floatFromInt(@max(source_size.height, 1))), @floatFromInt(source_size.width), @floatFromInt(source_size.height),
        };
        const blend_flag: u32 = if (blend) 1 else 0;
        webgpu_draw_post_process(self.renderer.ctx, shader.handle, source_slot, &uniforms, blend_flag);
    }

    pub fn endFrame(self: *Frame) !void {
        webgpu_end_frame(self.renderer.ctx);
    }
};

fn targetSlotValue(target: FrameTarget) u32 {
    return switch (target) {
        .surface => std.math.maxInt(u32),
        .slot => |slot| slot,
    };
}

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

// Imports
const std = @import("std");
const builtin = @import("builtin");
const utils = @import("utils.zig");
const common = @import("common");
const scene_uniforms = @import("scene_uniforms.zig");
const shadow_uniforms = @import("shadow_uniforms.zig");

const Color = common.Color;
const Size = utils.Size;
const SurfaceTarget = utils.SurfaceTarget;
