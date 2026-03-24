pub const RenderSurface = struct {
    target: render.SurfaceTarget,
};

pub const RenderState = struct {
    renderer: render.Renderer,
    surface: render.SurfaceTarget,
    default_sampler: render.Sampler,
    default_texture: render.Texture,
    default_material: render.BackendMaterial,
    shadow_shader_uv2: render.ShadowShader,
    shadow_shader_pos3_uv2: render.ShadowShader,
    shadow_shader_pos3_norm_uv2: render.ShadowShader,
    shadow_shader_pos3_norm_tangent_uv2: render.ShadowShader,
    shadow_shader_pos3_color4: render.ShadowShader,
    current_scene_environment: render.TextureHandle = render.TextureHandle.invalid(),
    submit_scratch: SubmitScratch,

    pub fn deinit(self: *RenderState) void {
        self.submit_scratch.deinit();
        self.renderer.destroyShadowShader(&self.shadow_shader_uv2);
        self.renderer.destroyShadowShader(&self.shadow_shader_pos3_uv2);
        self.renderer.destroyShadowShader(&self.shadow_shader_pos3_norm_uv2);
        self.renderer.destroyShadowShader(&self.shadow_shader_pos3_norm_tangent_uv2);
        self.renderer.destroyShadowShader(&self.shadow_shader_pos3_color4);
        self.renderer.destroyMaterial(&self.default_material);
        self.renderer.destroyTexture(&self.default_texture);
        self.renderer.destroySampler(&self.default_sampler);
        self.renderer.deinit();
        self.* = undefined;
    }
};

pub const ExtractedSceneLighting = struct {
    ambient_color: common.Color.F32 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    exposure_enabled: bool = false,
    exposure: f32 = 1.0,
    light_count: u32 = 0,
    environment_intensity: f32 = 1.0,
    environment_diffuse_strength: f32 = 1.0,
    environment_specular_strength: f32 = 1.0,
    environment_average_luminance: f32 = 1.0,
    environment_dominant_direction: common.Vec3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    environment_dominant_color: common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    environment_irradiance_sh: [9][4]f32 = [_][4]f32{[_]f32{ 0.0, 0.0, 0.0, 0.0 }} ** 9,
    lights: [render.max_scene_lights]render.SceneLight = [_]render.SceneLight{render.SceneLight{}} ** render.max_scene_lights,
};

pub const ViewportSize = struct {
    /// Logical viewport size used by viewport cameras, UI, and layout math.
    width: f32,
    height: f32,
};

pub const FramebufferSize = struct {
    /// Physical framebuffer size used for render-surface sizing and scissor rectangles.
    width: f32,
    height: f32,
};

pub const RenderRecovery = struct {
    lost: bool = false,
    restored: bool = false,
};

pub const ShadowSettings = @import("shadows.zig").ShadowSettings;

pub const SpriteMeshCache = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap(u64, render.MeshHandle),

    pub fn init(allocator: std.mem.Allocator) SpriteMeshCache {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(u64, render.MeshHandle).init(allocator),
        };
    }

    pub fn deinit(self: *SpriteMeshCache) void {
        self.map.deinit();
        self.* = undefined;
    }
};

pub const LayerCameras = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap(i32, LayerCamera),

    pub fn init(allocator: std.mem.Allocator) LayerCameras {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(i32, LayerCamera).init(allocator),
        };
    }

    pub fn deinit(self: *LayerCameras) void {
        self.map.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *LayerCameras) void {
        self.map.clearRetainingCapacity();
    }
};

pub const ViewportRect = struct {
    /// Logical viewport rectangle. The renderer converts this into physical pixels per frame.
    x: f32 = 0.0,
    y: f32 = 0.0,
    width: f32 = 0.0,
    height: f32 = 0.0,
};

pub const LayerViewports = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap(i32, ViewportRect),

    pub fn init(allocator: std.mem.Allocator) LayerViewports {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(i32, ViewportRect).init(allocator),
        };
    }

    pub fn deinit(self: *LayerViewports) void {
        self.map.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *LayerViewports) void {
        self.map.clearRetainingCapacity();
    }
};

pub const LayerCamera = struct {
    camera: common.Camera3d,
    view: common.Mat4,
    transform: common.Transform,
};

pub const BatchKey = struct {
    mesh: render.MeshHandle,
    material: usize,
};

pub const BatchItem = struct {
    key: BatchKey,
    mesh: render.Mesh,
    material: render.BackendMaterial,
    instance: render.BackendMeshInstance,
};

pub const ShaderBatchKey = struct {
    mesh: render.MeshHandle,
    shader: render.ShaderHandle,
};

pub const TexturedShaderBatchKey = struct {
    mesh: render.MeshHandle,
    shader: render.ShaderHandle,
    material: usize,
};

pub const ShaderBatchItem = struct {
    key: ShaderBatchKey,
    mesh: render.Mesh,
    shader: render.Shader,
    instance: render.BackendMeshInstance,
};

pub const TexturedShaderBatchItem = struct {
    key: TexturedShaderBatchKey,
    mesh: render.Mesh,
    shader: render.Shader,
    material: render.BackendMaterial,
    instance: render.BackendMeshInstance,
};

pub const BlendItem = struct {
    sort_key: i32,
    depth: f32,
    entity_id: u64,
    mesh: render.Mesh,
    material: render.BackendMaterial,
    instance: render.BackendMeshInstance,
};

pub const PostProcessPassItem = struct {
    order: i32,
    pass: render.PostProcessPass,
};

pub const SubmitScratch = struct {
    allocator: std.mem.Allocator,
    layers: std.ArrayListUnmanaged(i32) = .empty,
    post_process_passes: std.ArrayListUnmanaged(PostProcessPassItem) = .empty,
    batch_items: std.ArrayListUnmanaged(BatchItem) = .empty,
    shader_batch_items: std.ArrayListUnmanaged(ShaderBatchItem) = .empty,
    textured_shader_batch_items: std.ArrayListUnmanaged(TexturedShaderBatchItem) = .empty,
    batch_instances: std.ArrayListUnmanaged(render.BackendMeshInstance) = .empty,
    shader_instances: std.ArrayListUnmanaged(render.BackendMeshInstance) = .empty,
    textured_shader_instances: std.ArrayListUnmanaged(render.BackendMeshInstance) = .empty,
    blended: std.ArrayListUnmanaged(BlendItem) = .empty,

    pub fn init(allocator: std.mem.Allocator) SubmitScratch {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SubmitScratch) void {
        self.layers.deinit(self.allocator);
        self.post_process_passes.deinit(self.allocator);
        self.batch_items.deinit(self.allocator);
        self.shader_batch_items.deinit(self.allocator);
        self.textured_shader_batch_items.deinit(self.allocator);
        self.batch_instances.deinit(self.allocator);
        self.shader_instances.deinit(self.allocator);
        self.textured_shader_instances.deinit(self.allocator);
        self.blended.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clearFrame(self: *SubmitScratch) void {
        self.layers.clearRetainingCapacity();
        self.post_process_passes.clearRetainingCapacity();
        self.batch_items.clearRetainingCapacity();
        self.shader_batch_items.clearRetainingCapacity();
        self.textured_shader_batch_items.clearRetainingCapacity();
        self.batch_instances.clearRetainingCapacity();
        self.shader_instances.clearRetainingCapacity();
        self.textured_shader_instances.clearRetainingCapacity();
        self.blended.clearRetainingCapacity();
    }
};

pub fn cameraLayerKeyForRow(row: db.QueryResult.Row) i32 {
    const table = &row.database.tables.items[row.table_index];
    const trait_id = db.meta.typeId(render.CameraLayerN);
    for (table.columns) |column| {
        for (column.group_traits) |group_trait| {
            if (group_trait.trait_id != trait_id) continue;
            return group_trait.key;
        }
    }
    return 0;
}

const std = @import("std");
const common = @import("common");
const render = @import("render");
const db = @import("db");
const ecs = @import("ecs");
