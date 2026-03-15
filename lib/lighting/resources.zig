const common = @import("common");

pub const AmbientLight = struct {
    color: common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    intensity: f32 = 0.03,
};

pub const ExposureSettings = struct {
    enabled: bool = false,
    exposure: f32 = 1.0,
};

pub const AuthoringStats = struct {
    total_lights: u32 = 0,
    enabled_lights: u32 = 0,
    dynamic_lights: u32 = 0,
    static_lights: u32 = 0,
    directional_lights: u32 = 0,
    point_lights: u32 = 0,
    spot_lights: u32 = 0,
};
