const ecs = @import("ecs");
const common = @import("common");

pub const ContactBegan = struct {
    a: ecs.Entity.Id,
    b: ecs.Entity.Id,
    normal: common.Vec3 = .{},
};

pub const ContactEnded = struct {
    a: ecs.Entity.Id,
    b: ecs.Entity.Id,
};

pub const TriggerEntered = struct {
    sensor: ecs.Entity.Id,
    other: ecs.Entity.Id,
};

pub const TriggerExited = struct {
    sensor: ecs.Entity.Id,
    other: ecs.Entity.Id,
};
