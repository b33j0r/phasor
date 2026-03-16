const common = @import("common");

pub const Light = union(enum) {
    directional: DirectionalLight,
    point: PointLight,
    spot: SpotLight,

    pub fn kind(self: Light) Kind {
        return switch (self) {
            .directional => .directional,
            .point => .point,
            .spot => .spot,
        };
    }

    pub const Kind = enum {
        directional,
        point,
        spot,
    };
};

pub const LightVisibility = struct {
    enabled: bool = true,
    casts_shadows: bool = false,
    is_static: bool = false,
};

pub const DirectionalLight = struct {
    color: common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    illuminance_lux: f32 = 10000.0,
};

pub const PointLight = struct {
    color: common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    intensity_candela: f32 = 800.0,
    range: f32 = 10.0,
    radius: f32 = 0.05,
};

pub const SpotLight = struct {
    color: common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    intensity_candela: f32 = 1200.0,
    range: f32 = 15.0,
    inner_angle_rad: f32 = 0.35,
    outer_angle_rad: f32 = 0.55,
    radius: f32 = 0.05,
};
