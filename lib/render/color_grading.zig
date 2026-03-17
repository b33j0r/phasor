const std = @import("std");

pub const ColorGrade = enum(u32) {
    none = 0,
    filmic = 1,
    aces_fitted = 2,
    agx = 3,
    pbr_neutral = 4,
};

pub const ColorGradingSettings = struct {
    grade: ColorGrade = .none,
    amount: f32 = 1.0,

    pub fn uniformVec4(self: ColorGradingSettings) [4]f32 {
        return .{
            @floatFromInt(@intFromEnum(self.grade)),
            std.math.clamp(self.amount, 0.0, 1.0),
            0.0,
            0.0,
        };
    }
};

test "color grading settings pack into uniforms" {
    const settings = ColorGradingSettings{
        .grade = .filmic,
        .amount = 2.0,
    };
    const uniform_values = settings.uniformVec4();
    try std.testing.expectEqual(@as(u32, 1), @as(u32, @intFromFloat(uniform_values[0])));
    try std.testing.expectEqual(@as(f32, 1.0), uniform_values[1]);
}
