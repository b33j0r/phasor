const common = @import("common");
const ecs = @import("ecs");
const components = @import("components.zig");

pub const RayCast = struct {
    origin: common.Vec3,
    direction: common.Vec3,
    max_distance: f32,
    collision: components.CollisionFilter = .{},
};

pub const RayHit = struct {
    entity: ?ecs.Entity.Id = null,
    body: ?components.BodyHandle = null,
    position: common.Vec3 = .{},
    normal: common.Vec3 = .{},
    distance: f32 = 0.0,
};

pub const ShapeCast = struct {
    shape: components.Shape,
    start: common.Transform = .{},
    translation: common.Vec3 = .{},
    collision: components.CollisionFilter = .{},
};

pub const ShapeHit = struct {
    entity: ?ecs.Entity.Id = null,
    body: ?components.BodyHandle = null,
    position: common.Vec3 = .{},
    normal: common.Vec3 = .{},
    fraction: f32 = 0.0,
};
