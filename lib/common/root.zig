test "import tests" {
    _ = fixtures;
    _ = vec;
    _ = mat4;
    _ = quat;
    _ = camera;
}

// Imports
pub const fixtures = @import("fixtures.zig");
pub const vec = @import("vec.zig");
pub const mat4 = @import("mat4.zig");
pub const quat = @import("quat.zig");
pub const camera = @import("camera.zig");

pub const Vec2 = vec.Vec2;
pub const Vec3 = vec.Vec3;
pub const Mat4 = mat4.Mat4;
pub const Quat = quat.Quat;
pub const Camera3d = camera.Camera3d;
