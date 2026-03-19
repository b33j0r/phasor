const common = @import("common");

pub const ShadowUniforms = extern struct {
    light_view_proj: common.Mat4 = common.Mat4.identity(),
    params0: [4]f32 = .{ 0.0, 0.0, 0.0015, 0.0025 }, // texel_x, texel_y, depth_bias, normal_bias
    params1: [4]f32 = .{ 1.0, 0.0, 0.0, 0.0 }, // strength, enabled, technique, reserved
};
