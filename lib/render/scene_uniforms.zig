const common = @import("common");

pub const max_scene_lights: usize = 32;

pub const SceneLightKind = enum(u32) {
    directional = 0,
    point = 1,
    spot = 2,
};

pub const SceneLight = extern struct {
    position_range: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
    direction_kind: [4]f32 = .{ 0.0, 0.0, -1.0, 0.0 },
    color_intensity: [4]f32 = .{ 1.0, 1.0, 1.0, 0.0 },
    spot_params: [4]f32 = .{ 1.0, 1.0, 0.0, 0.0 },
};

pub const SceneUniforms = extern struct {
    view_proj: common.Mat4 = common.Mat4.identity(),
    camera_position: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
    ambient_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
    exposure_settings: [4]f32 = .{ 1.0, 0.0, 1.0, 1.0 },
    environment_dominant_direction: [4]f32 = .{ 0.0, 1.0, 0.0, 0.0 },
    environment_dominant_color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
    light_counts: [4]u32 = .{ 0, 0, 0, 0 },
    environment_irradiance_sh: [9][4]f32 = [_][4]f32{[_]f32{ 0.0, 0.0, 0.0, 0.0 }} ** 9,
    lights: [max_scene_lights]SceneLight = [_]SceneLight{SceneLight{}} ** max_scene_lights,
};
