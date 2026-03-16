test "import tests" {
    _ = components;
    _ = resources;
}

pub const components = @import("components.zig");
pub const resources = @import("resources.zig");

pub const Light = components.Light;
pub const LightVisibility = components.LightVisibility;
pub const DirectionalLight = components.DirectionalLight;
pub const PointLight = components.PointLight;
pub const SpotLight = components.SpotLight;

pub const AmbientLight = resources.AmbientLight;
pub const EnvironmentLight = resources.EnvironmentLight;
pub const ExposureSettings = resources.ExposureSettings;
pub const AuthoringStats = resources.AuthoringStats;
pub const buildEnvironmentLightFromHdrBytes = @import("environment.zig").buildEnvironmentLightFromHdrBytes;
