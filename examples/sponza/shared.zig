pub const Player = struct {};
pub const PlayerCamera = struct {};
pub const SceneReady = struct {};
pub const SceneRoot = struct {};
pub const LoadingScreen = struct {};
pub const LoadingScreenText = struct {};
pub const LoadingScreenBarFill = struct {};
pub const LoadingScreenBarTrack = struct {};
pub const HudCameraTag = struct {};
pub const LightingReady = struct {};
pub const SkyCycleReady = struct {};

pub const SkyMode = enum {
    procedural,
    hdri,
};

pub const DayNightSettings = struct {
    start_hour: f32 = 14.5,
    day_length_seconds: f32 = 720.0,
    latitude_deg: f32 = 47.0,
};

pub const WeatherSettings = struct {
    cloud_coverage: f32 = 0.35,
    cloud_density: f32 = 0.52,
    haze: f32 = 0.18,
    wind_speed: f32 = 0.9,
    weather_cycle_seconds: f32 = 240.0,
};

pub const SkyCycleState = struct {
    mode: SkyMode = .procedural,
    day_night: DayNightSettings = .{},
    weather: WeatherSettings = .{},
    hdri_environment: ?lighting.EnvironmentLight = null,
    hdri_ambient: ?lighting.AmbientLight = null,
};

pub const SceneSpawnPlan = struct {
    scene_size: Vec3,
};

pub const SceneMetrics = struct {
    scene_size: Vec3,
};

pub const FpsPhysics = modules.FpsPhysicsModule(Player);
pub const FpsController = FpsPhysics.FpsController;

pub const sponza_scene_path = "examples/sponza/assets/sponza/glTF/Sponza.gltf";
pub const sponza_panorama_bytes = @embedFile("assets/hdr/furstenstein_2k.hdr");
pub const sponza_ui_serif_font_bytes = @embedFile("assets/fonts/CormorantGaramond/CormorantGaramond[wght].ttf");

pub const StatusOverlay = struct {
    buffer: [512]u8 = [_]u8{0} ** 512,
};

pub const LoadingScreenState = struct {
    camera_entity: u64,
    text_entity: u64,
    overlay: StatusOverlay = .{},
};

pub const LoadingScreenVisualState = struct {
    track_entity: u64,
    fill_entity: u64,
    bar_width: f32 = 420.0,
    bar_height: f32 = 18.0,
};

pub const HudCameraState = struct {
    camera_entity: u64,
};

pub const SceneLoaderCommand = enum {
    shutdown,
};

pub const SceneLoaderProgress = struct {
    label: []const u8,
    fraction: f32,
};

pub const SceneBake = struct {
    bounds: SceneBounds,
    collision_blob: []u8,
};

pub const LoadedScenePayload = struct {
    prepared_scene: assets.PreparedImportedScene,
    bake: SceneBake,

    pub fn deinit(self: *LoadedScenePayload, allocator: std.mem.Allocator) void {
        self.prepared_scene.deinit();
        allocator.free(self.bake.collision_blob);
        self.* = undefined;
    }
};

pub const SceneLoaderMessage = union(enum) {
    progress: SceneLoaderProgress,
    ready: LoadedScenePayload,
    failed: []const u8,
};

pub const SceneLoader = common.Agent(SceneLoaderCommand, SceneLoaderMessage);

pub const SceneLoaderTaskContext = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
};

pub const FinalizeStage = enum {
    inspect_bake,
    create_scene_root,
    parse_collision,
    instantiate_collision,
    instantiate_scene,
};

pub const SceneFinalizeState = struct {
    allocator: std.mem.Allocator,
    payload: LoadedScenePayload,
    stage: FinalizeStage = .inspect_bake,
    root_translation: Vec3 = .{},
    scene_size: Vec3 = .{},
    scene_root: ?u64 = null,
    parsed_collision: ?physics.CollisionBake.File = null,
    next_collision_mesh: usize = 0,
    scene_apply: ?assets.PreparedImportedScene.ApplyState = null,

    pub fn deinit(self: *SceneFinalizeState) void {
        if (self.parsed_collision) |*parsed| parsed.deinit(self.allocator);
        if (self.scene_apply) |*apply| apply.deinit();
        self.payload.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const SceneLoaderState = struct {
    allocator: std.mem.Allocator,
    io: *const std.Io,
    agent: SceneLoader,
    started: bool = false,
    progress: SceneLoaderProgress = .{ .label = "Booting", .fraction = 0.0 },
    payload: ?LoadedScenePayload = null,
    failed: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, io: *const std.Io) !SceneLoaderState {
        return .{
            .allocator = allocator,
            .io = io,
            .agent = try SceneLoader.init(allocator, io, 1, 8),
        };
    }

    pub fn deinit(self: *SceneLoaderState) void {
        if (self.payload) |*payload| payload.deinit(self.allocator);
        self.agent.deinit(self.io.*);
        self.* = undefined;
    }
};

pub const SpawnChoice = struct {
    position: Vec3,
    yaw: f32,
};

pub const AnimatedLight = struct {
    center: Vec3,
    orbit_radius: f32 = 0.0,
    angular_speed: f32 = 0.0,
    phase: f32 = 0.0,
    base_height: f32,
    pulse_base: f32,
    pulse_amplitude: f32 = 0.0,
    pulse_speed: f32 = 0.0,
};

pub const SceneBounds = struct {
    min: Vec3 = .{},
    max: Vec3 = .{},
    valid: bool = false,

    pub fn include(self: *SceneBounds, point: Vec3) void {
        if (!self.valid) {
            self.min = point;
            self.max = point;
            self.valid = true;
            return;
        }
        self.min.x = @min(self.min.x, point.x);
        self.min.y = @min(self.min.y, point.y);
        self.min.z = @min(self.min.z, point.z);
        self.max.x = @max(self.max.x, point.x);
        self.max.y = @max(self.max.y, point.y);
        self.max.z = @max(self.max.z, point.z);
    }

    pub fn center(self: SceneBounds) Vec3 {
        if (!self.valid) return .{};
        return .{
            .x = (self.min.x + self.max.x) * 0.5,
            .y = (self.min.y + self.max.y) * 0.5,
            .z = (self.min.z + self.max.z) * 0.5,
        };
    }

    pub fn size(self: SceneBounds) Vec3 {
        if (!self.valid) return .{};
        return .{
            .x = self.max.x - self.min.x,
            .y = self.max.y - self.min.y,
            .z = self.max.z - self.min.z,
        };
    }
};

pub const Assets = struct {
    ui_serif_font: assets.Font = assets.Font
        .embedded("Cormorant Garamond", sponza_ui_serif_font_bytes)
        .withPixelHeight(72.0)
        .withAtlasSize(1024, 1024),
    sky_panorama: assets.Texture = assets.Texture.embedded(sponza_panorama_bytes).asHdr().asOpaque().equirectangularLinear(),
    scene_shader: assets.Shader = .{
        .wgsl_source = @embedFile("shaders/scene_pbr_lit.wgsl"),
        .vertex_layout = .pos3_norm_uv2,
        .binding_mode = .material_scene,
    },
    color_shader: assets.Shader = .{
        .wgsl_source = @embedFile("shaders/ui_color.wgsl"),
    },
    sky_shader: assets.Shader = .{
        .wgsl_source = @embedFile("shaders/sky_panorama_hdr.wgsl"),
        .vertex_layout = .pos3_uv2,
        .binding_mode = .material_scene,
    },
    sky_procedural_shader: assets.Shader = .{
        .wgsl_source = @embedFile("shaders/sky_procedural.wgsl"),
        .vertex_layout = .pos3_uv2,
        .binding_mode = .material_scene,
    },
};

pub fn quatFromEuler(pitch: f32, yaw: f32, roll: f32) Quat {
    const qy = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, yaw);
    const qx = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, pitch);
    const qz = Quat.fromAxisAngle(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, roll);
    return qy.mul(qx).mul(qz);
}

// Imports
const std = @import("std");
const phasor = @import("phasor");
const assets = phasor.assets;
const common = phasor.common;
const modules = phasor.modules;
const physics = phasor.physics;
const lighting = phasor.lighting;

const Quat = common.Quat;
const Vec3 = common.Vec3;
