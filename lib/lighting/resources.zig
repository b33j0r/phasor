const common = @import("common");

pub const AmbientLight = struct {
    color: common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    intensity: f32 = 0.03,
};

pub const EnvironmentLight = struct {
    enabled: bool = false,
    intensity: f32 = 1.0,
    diffuse_strength: f32 = 1.0,
    specular_strength: f32 = 1.0,
    average_luminance: f32 = 1.0,
    dominant_direction: common.Vec3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    dominant_color: common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    irradiance_sh: [9][4]f32 = [_][4]f32{[_]f32{ 0.0, 0.0, 0.0, 0.0 }} ** 9,
};

pub const ExposureSettings = struct {
    enabled: bool = false,
    exposure: f32 = 1.0,
    auto_enabled: bool = false,
    auto_key_value: f32 = 0.18,
    min_exposure: f32 = 0.08,
    max_exposure: f32 = 2.5,
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
