const Vec3 = @import("vec.zig").Vec3;
const Quat = @import("quat.zig").Quat;
const Mat4 = @import("mat4.zig").Mat4;

pub const Transform = extern struct {
    translation: Vec3 = .{},
    rotation: Quat = Quat.identity(),
    scale: Vec3 = Vec3.splat(1.0),

    pub fn identity() Transform {
        return .{};
    }

    pub fn fromTranslation(translation: Vec3) Transform {
        return .{ .translation = translation };
    }

    pub fn fromScale(scale: Vec3) Transform {
        return .{ .scale = scale };
    }

    pub fn fromRotation(rotation: Quat) Transform {
        return .{ .rotation = rotation };
    }

    pub fn withTranslation(self: Transform, translation: Vec3) Transform {
        var out = self;
        out.translation = translation;
        return out;
    }

    pub fn withScale(self: Transform, scale: Vec3) Transform {
        var out = self;
        out.scale = scale;
        return out;
    }

    pub fn withRotation(self: Transform, rotation: Quat) Transform {
        var out = self;
        out.rotation = rotation;
        return out;
    }

    pub fn toMat4(self: Transform) Mat4 {
        const translate = Mat4.translateVec3(self.translation);
        const rotate = Mat4.fromQuaternion(self.rotation);
        const scale = Mat4.scaleVec3(self.scale);
        return Mat4.mul(Mat4.mul(translate, rotate), scale);
    }
};
