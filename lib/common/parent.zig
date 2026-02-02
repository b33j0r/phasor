const Vec3 = @import("vec.zig").Vec3;
const Quat = @import("quat.zig").Quat;

/// Parent component that references another entity by id.
pub const Parent = struct {
    id: u64,
    inherit_translation: bool = true,
    inherit_rotation: bool = true,
    inherit_scale: bool = true,
};

/// Local transform relative to a parent entity.
pub const LocalTransform = extern struct {
    translation: Vec3 = .{},
    rotation: Quat = Quat.identity(),
    scale: Vec3 = Vec3.splat(1.0),

    pub fn identity() LocalTransform {
        return .{};
    }
};
