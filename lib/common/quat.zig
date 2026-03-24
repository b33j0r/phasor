//! Quaternion for 3D rotations.

const std = @import("std");
const Vec3 = @import("vec.zig").Vec3;

pub const Quat = extern struct {
    w: f32 = 1.0,
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub fn identity() Quat {
        return .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 };
    }

    pub fn fromAxisAngle(axis: Vec3, angle: f32) Quat {
        const half_angle = angle * 0.5;
        const s = @sin(half_angle);
        const c = @cos(half_angle);
        return .{
            .w = c,
            .x = axis.x * s,
            .y = axis.y * s,
            .z = axis.z * s,
        };
    }

    pub fn mul(q1: Quat, q2: Quat) Quat {
        return .{
            .w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z,
            .x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
            .y = q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
            .z = q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w,
        };
    }

    pub fn normalize(self: Quat) Quat {
        const len = @sqrt(self.w * self.w + self.x * self.x + self.y * self.y + self.z * self.z);
        if (len < 0.00001) return identity();
        const inv_len = 1.0 / len;
        return .{
            .w = self.w * inv_len,
            .x = self.x * inv_len,
            .y = self.y * inv_len,
            .z = self.z * inv_len,
        };
    }

    pub fn conjugate(self: Quat) Quat {
        return .{
            .w = self.w,
            .x = -self.x,
            .y = -self.y,
            .z = -self.z,
        };
    }

    pub fn lerp(q1: Quat, q2: Quat, t: f32) Quat {
        return .{
            .w = q1.w + (q2.w - q1.w) * t,
            .x = q1.x + (q2.x - q1.x) * t,
            .y = q1.y + (q2.y - q1.y) * t,
            .z = q1.z + (q2.z - q1.z) * t,
        };
    }

    pub fn slerp(q1: Quat, q2: Quat, t: f32) Quat {
        var dot = q1.w * q2.w + q1.x * q2.x + q1.y * q2.y + q1.z * q2.z;
        var q2_adjusted = q2;
        if (dot < 0.0) {
            q2_adjusted = .{ .w = -q2.w, .x = -q2.x, .y = -q2.y, .z = -q2.z };
            dot = -dot;
        }

        if (dot > 0.9995) {
            return lerp(q1, q2_adjusted, t).normalize();
        }

        const theta = std.math.acos(dot);
        const sin_theta = @sin(theta);
        const a = @sin((1.0 - t) * theta) / sin_theta;
        const b = @sin(t * theta) / sin_theta;

        return .{
            .w = q1.w * a + q2_adjusted.w * b,
            .x = q1.x * a + q2_adjusted.x * b,
            .y = q1.y * a + q2_adjusted.y * b,
            .z = q1.z * a + q2_adjusted.z * b,
        };
    }

    pub fn rotateVec3(self: Quat, v: Vec3) Vec3 {
        const qvec = Vec3{ .x = self.x, .y = self.y, .z = self.z };
        const uv = qvec.cross(v);
        const uuv = qvec.cross(uv);
        const uv_scaled = uv.scale(2.0 * self.w);
        const uuv_scaled = uuv.scale(2.0);

        return Vec3{
            .x = v.x + uv_scaled.x + uuv_scaled.x,
            .y = v.y + uv_scaled.y + uuv_scaled.y,
            .z = v.z + uv_scaled.z + uuv_scaled.z,
        };
    }

    pub fn inverse(self: Quat) Quat {
        const len_sq = self.w * self.w + self.x * self.x + self.y * self.y + self.z * self.z;
        if (len_sq < 0.00001) return identity();
        const inv_len_sq = 1.0 / len_sq;
        return .{
            .w = self.w * inv_len_sq,
            .x = -self.x * inv_len_sq,
            .y = -self.y * inv_len_sq,
            .z = -self.z * inv_len_sq,
        };
    }

    pub const YawPitch = struct {
        yaw: f32 = 0.0,
        pitch: f32 = 0.0,
    };

    pub fn lookAt(eye: Vec3, target: Vec3, up_hint: Vec3) Quat {
        return lookRotation(target.sub(eye), up_hint);
    }

    pub fn lookRotation(forward_hint: Vec3, up_hint: Vec3) Quat {
        _ = up_hint;
        const angles = yawPitchFromForward(forward_hint);
        const qx = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, angles.pitch);
        const qy = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, angles.yaw);
        return qy.mul(qx).normalize();
    }

    pub fn yawPitchFromForward(forward_hint: Vec3) YawPitch {
        if (forward_hint.length_squared() <= 0.000001) return .{};
        const forward = forward_hint.normalize();
        return .{
            .yaw = std.math.atan2(-forward.x, -forward.z),
            .pitch = std.math.asin(std.math.clamp(forward.y, -1.0, 1.0)),
        };
    }
};

test "Quat identity" {
    const q = Quat.identity();
    try std.testing.expectEqual(@as(f32, 1.0), q.w);
    try std.testing.expectEqual(@as(f32, 0.0), q.x);
    try std.testing.expectEqual(@as(f32, 0.0), q.y);
    try std.testing.expectEqual(@as(f32, 0.0), q.z);
}

test "Quat fromAxisAngle" {
    const axis = Vec3{ .x = 0, .y = 1, .z = 0 };
    const angle = std.math.pi / 2.0;
    const q = Quat.fromAxisAngle(axis, angle);
    try std.testing.expectApproxEqAbs(@as(f32, 0.70710678), q.w, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.70710678), q.y, 1e-6);
}

test "Quat rotateVec3" {
    const axis = Vec3{ .x = 0, .y = 0, .z = 1 };
    const angle = std.math.pi / 2.0;
    const q = Quat.fromAxisAngle(axis, angle);
    const v = Vec3{ .x = 1, .y = 0, .z = 0 };
    const vr = q.rotateVec3(v);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), vr.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), vr.y, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), vr.z, 1e-6);
}

test "Quat mul" {
    const q1 = Quat.fromAxisAngle(.{ .x = 1, .y = 0, .z = 0 }, std.math.pi / 2.0);
    const q2 = Quat.fromAxisAngle(.{ .x = 1, .y = 0, .z = 0 }, std.math.pi / 2.0);
    const q3 = q1.mul(q2);
    const v = Vec3{ .x = 0, .y = 1, .z = 0 };
    const vr = q3.rotateVec3(v);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), vr.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), vr.y, 1e-6);
}

test "Quat lookAt identity forward" {
    const q = Quat.lookAt(.{ .x = 0.0, .y = 0.0, .z = 0.0 }, .{ .x = 0.0, .y = 0.0, .z = -1.0 }, .{ .x = 0.0, .y = 1.0, .z = 0.0 });
    const forward = q.rotateVec3(.{ .x = 0.0, .y = 0.0, .z = -1.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), forward.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), forward.y, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), forward.z, 1e-5);
}

test "Quat yawPitchFromForward matches engine forward convention" {
    const forward = (Vec3{ .x = 1.0, .y = 0.25, .z = -2.0 }).normalize();
    const angles = Quat.yawPitchFromForward(forward);
    const qx = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, angles.pitch);
    const qy = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, angles.yaw);
    const reconstructed = qy.mul(qx).normalize().rotateVec3(.{ .x = 0.0, .y = 0.0, .z = -1.0 });
    try std.testing.expectApproxEqAbs(forward.x, reconstructed.x, 1e-5);
    try std.testing.expectApproxEqAbs(forward.y, reconstructed.y, 1e-5);
    try std.testing.expectApproxEqAbs(forward.z, reconstructed.z, 1e-5);
}
