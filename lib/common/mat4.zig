//! 4x4 Matrix for homogeneous 3D transformations.
//! Column-major layout for compatibility with WebGPU.

pub const Mat4 = extern struct {
    // Column-major storage: m[column][row].
    m: [4][4]f32,

    pub fn identity() Mat4 {
        return .{
            .m = .{
                .{ 1, 0, 0, 0 },
                .{ 0, 1, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    pub fn translate(x: f32, y: f32, z: f32) Mat4 {
        return .{
            .m = .{
                .{ 1, 0, 0, 0 },
                .{ 0, 1, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ x, y, z, 1 },
            },
        };
    }

    pub fn translateVec3(v: Vec3) Mat4 {
        return translate(v.x, v.y, v.z);
    }

    pub fn scale(x: f32, y: f32, z: f32) Mat4 {
        return .{
            .m = .{
                .{ x, 0, 0, 0 },
                .{ 0, y, 0, 0 },
                .{ 0, 0, z, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    pub fn scaleUniform(s: f32) Mat4 {
        return scale(s, s, s);
    }

    pub fn scaleVec3(v: Vec3) Mat4 {
        return scale(v.x, v.y, v.z);
    }

    pub fn rotateZ(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{
            .m = .{
                .{ c, s, 0, 0 },
                .{ -s, c, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    pub fn rotateX(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{
            .m = .{
                .{ 1, 0, 0, 0 },
                .{ 0, c, s, 0 },
                .{ 0, -s, c, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    pub fn rotateY(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{
            .m = .{
                .{ c, 0, -s, 0 },
                .{ 0, 1, 0, 0 },
                .{ s, 0, c, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    pub fn fromQuaternion(q: Quat) Mat4 {
        const xx = q.x * q.x;
        const yy = q.y * q.y;
        const zz = q.z * q.z;
        const xy = q.x * q.y;
        const xz = q.x * q.z;
        const yz = q.y * q.z;
        const wx = q.w * q.x;
        const wy = q.w * q.y;
        const wz = q.w * q.z;

        return .{
            .m = .{
                .{ 1.0 - 2.0 * (yy + zz), 2.0 * (xy + wz), 2.0 * (xz - wy), 0.0 },
                .{ 2.0 * (xy - wz), 1.0 - 2.0 * (xx + zz), 2.0 * (yz + wx), 0.0 },
                .{ 2.0 * (xz + wy), 2.0 * (yz - wx), 1.0 - 2.0 * (xx + yy), 0.0 },
                .{ 0.0, 0.0, 0.0, 1.0 },
            },
        };
    }

    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var result: Mat4 = undefined;
        for (0..4) |col| {
            for (0..4) |row| {
                result.m[col][row] = a.m[0][row] * b.m[col][0] +
                    a.m[1][row] * b.m[col][1] +
                    a.m[2][row] * b.m[col][2] +
                    a.m[3][row] * b.m[col][3];
            }
        }
        return result;
    }

    pub fn transformVec2(self: Mat4, v: Vec2) Vec2 {
        const x = self.m[0][0] * v.x + self.m[1][0] * v.y + self.m[3][0];
        const y = self.m[0][1] * v.x + self.m[1][1] * v.y + self.m[3][1];
        return .{ .x = x, .y = y };
    }

    pub fn transformVec3(self: Mat4, v: Vec3) Vec3 {
        const x = self.m[0][0] * v.x + self.m[1][0] * v.y + self.m[2][0] * v.z + self.m[3][0];
        const y = self.m[0][1] * v.x + self.m[1][1] * v.y + self.m[2][1] * v.z + self.m[3][1];
        const z = self.m[0][2] * v.x + self.m[1][2] * v.y + self.m[2][2] * v.z + self.m[3][2];
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn rotate2DPoint(x: f32, y: f32, angle: f32) Vec2 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{
            .x = x * c - y * s,
            .y = x * s + y * c,
        };
    }

    pub fn orthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4 {
        const w = right - left;
        const h = top - bottom;
        const d = far - near;
        return .{
            .m = .{
                .{ 2.0 / w, 0, 0, 0 },
                .{ 0, 2.0 / h, 0, 0 },
                .{ 0, 0, -1.0 / d, 0 },
                .{ -(right + left) / w, -(top + bottom) / h, -near / d, 1 },
            },
        };
    }

    pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const f = 1.0 / @tan(fovy / 2.0);
        const d = far - near;
        return .{
            .m = .{
                .{ f / aspect, 0, 0, 0 },
                .{ 0, f, 0, 0 },
                .{ 0, 0, -far / d, -1 },
                .{ 0, 0, -(far * near) / d, 0 },
            },
        };
    }

    pub fn orthographic2D(left: f32, right: f32, bottom: f32, top: f32) Mat4 {
        return orthographic(left, right, bottom, top, -1.0, 1.0);
    }
};

test "Mat4 identity" {
    const mat = Mat4.identity();
    try std.testing.expectEqual(@as(f32, 1.0), mat.m[0][0]);
    try std.testing.expectEqual(@as(f32, 0.0), mat.m[0][1]);
    try std.testing.expectEqual(@as(f32, 1.0), mat.m[1][1]);
    try std.testing.expectEqual(@as(f32, 1.0), mat.m[3][3]);
}

test "Mat4 translate" {
    const mat = Mat4.translate(10.0, 20.0, 30.0);
    const v = Vec3{ .x = 1.0, .y = 2.0, .z = 3.0 };
    const vt = mat.transformVec3(v);
    try std.testing.expectEqual(@as(f32, 11.0), vt.x);
    try std.testing.expectEqual(@as(f32, 22.0), vt.y);
    try std.testing.expectEqual(@as(f32, 33.0), vt.z);
}

test "Mat4 scale" {
    const mat = Mat4.scale(2.0, 3.0, 4.0);
    const v = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 };
    const vs = mat.transformVec3(v);
    try std.testing.expectEqual(@as(f32, 2.0), vs.x);
    try std.testing.expectEqual(@as(f32, 3.0), vs.y);
    try std.testing.expectEqual(@as(f32, 4.0), vs.z);
}

test "Mat4 rotateZ" {
    const angle = std.math.pi / 2.0;
    const mat = Mat4.rotateZ(angle);
    const v = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 };
    const vr = mat.transformVec3(v);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), vr.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), vr.y, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), vr.z, 1e-6);
}

test "Mat4 multiply" {
    const t = Mat4.translate(10, 0, 0);
    const s = Mat4.scale(2, 2, 2);
    const ts = Mat4.mul(t, s);
    const v = Vec3{ .x = 1, .y = 1, .z = 1 };
    const v_res = ts.transformVec3(v);
    try std.testing.expectEqual(@as(f32, 12.0), v_res.x);
    try std.testing.expectEqual(@as(f32, 2.0), v_res.y);
    try std.testing.expectEqual(@as(f32, 2.0), v_res.z);
}

// Imports
const std = @import("std");
const Vec2 = @import("vec.zig").Vec2;
const Vec3 = @import("vec.zig").Vec3;
const Quat = @import("quat.zig").Quat;
