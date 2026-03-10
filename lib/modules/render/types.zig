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
