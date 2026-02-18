pub const RenderSurface = struct {
    target: render.SurfaceTarget,
};

pub const RenderState = struct {
    renderer: render.Renderer,
    surface: render.SurfaceTarget,
    default_sampler: render.Sampler,
    default_texture: render.Texture,
    default_material: render.BackendMaterial,

    pub fn deinit(self: *RenderState) void {
        self.renderer.destroyMaterial(&self.default_material);
        self.renderer.destroyTexture(&self.default_texture);
        self.renderer.destroySampler(&self.default_sampler);
        self.renderer.deinit();
        self.* = undefined;
    }
};

pub const ViewportSize = struct {
    width: f32,
    height: f32,
};

pub const RenderRecovery = struct {
    lost: bool = false,
    restored: bool = false,
};

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

pub const LayerCamera = struct {
    camera: common.Camera3d,
    view: common.Mat4,
};

const std = @import("std");
const common = @import("common");
const render = @import("render");
