pub const std_options = phasor.common.logging.stdOptions(.debug);

const max_particles: usize = 480;
const hidden_position = Vec3{ .x = 0.0, .y = -2000.0, .z = 0.0 };

const OrbitCamera = struct {};

pub fn main(init: std.process.Init) !u8 {
    var app = try App.default(&init);
    defer app.deinit();

    try app.insertResource(platform.WindowSettings{
        .title = "Phasor - Particles",
        .width = 1400,
        .height = 900,
    });
    try app.insertResource(render.VSync{ .enabled = false });

    try app.installDefaultModules();
    try app.installModule(particles.ParticlesModule(max_particles));
    try app.installModule(modules.MetricsModuleLayered(render.Layer(1000)){
        .font_size = 26.0,
        .text_color = Color.WHITE,
    });

    try app.addSystemTo("Startup", setupScene);
    try app.addSystemTo("Update", updateCamera);

    return try app.run();
}

fn setupScene(commands: *ecs.Commands, build_ctx: ResMut(render.BuildContext)) !void {
    const build = build_ctx.ptr;
    const ground_mesh = try createGroundPlane(build);
    const particle_shader = try build.createShader(.{
        .wgsl = @embedFile("shaders/particle_fountain.wgsl"),
        .vertex_layout = .pos3_uv2,
        .binding_mode = .none,
    });
    const ground_shader = try build.createShader(.{
        .wgsl = @embedFile("shaders/ground_plane.wgsl"),
        .vertex_layout = .pos3_color4,
        .binding_mode = .none,
    });

    try commands.insertResource(ClearColor{ .color = Color.rgb(2, 2, 4) });
    try commands.insertResource(particles.ParticleSystemConfig{
        .capacity = max_particles,
        .profiles = particleProfiles(particle_shader),
        .profile_count = 3,
        .hidden_position = hidden_position,
        .layer = 0,
        .sort_key = 500,
    });

    _ = try commands.createEntity(.{
        Transform{},
        render.MeshInstance{
            .mesh_handle = ground_mesh,
            .shader_handle = ground_shader,
            .material = render.Material.default,
            .color = Color.rgb(42, 34, 30),
        },
        render.Layer(0){},
        render.LayerSortKey{ .value = 0 },
    });

    _ = try commands.createEntity(.{
        OrbitCamera{},
        Transform{
            .translation = .{ .x = 8.2, .y = 5.4, .z = 10.8 },
            .rotation = Quat.lookAt(
                .{ .x = 8.2, .y = 5.4, .z = 10.8 },
                .{ .x = 0.0, .y = 1.65, .z = 0.0 },
                .{ .x = 0.0, .y = 1.0, .z = 0.0 },
            ),
        },
        Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.1,
            .near = 0.1,
            .far = 120.0,
        } },
        CameraLayer(0){},
    });

    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(1000){},
    });

    try createFountainEmitters(commands);
}

fn updateCamera(elapsed: Res(ElapsedTime), query: Query(.{ Transform, OrbitCamera })) void {
    const t: f32 = @floatCast(elapsed.ptr.seconds);
    const radius = 11.0 + std.math.sin(t * 0.19) * 1.2;
    const angle = t * 0.22 + 0.35;
    const height = 5.0 + std.math.sin(t * 0.31) * 0.8;
    const target = Vec3{ .x = 0.0, .y = 1.85 + std.math.sin(t * 1.35) * 0.12, .z = 0.0 };

    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.translation = .{
            .x = std.math.cos(angle) * radius,
            .y = height,
            .z = std.math.sin(angle) * radius,
        };
        transform.rotation = Quat.lookAt(transform.translation, target, .{ .x = 0.0, .y = 1.0, .z = 0.0 });
    }
}

fn particleProfiles(particle_shader: render.ShaderHandle) [particles.max_profiles]particles.ParticleProfile {
    var profiles = [_]particles.ParticleProfile{.{}} ** particles.max_profiles;
    profiles[0] = .{
        .geometry = .billboard,
        .mesh_instance = particleMeshInstance(particle_shader, Color.rgba(255, 180, 72, 210)),
        .base_scale = .{ .x = 0.85, .y = 1.15, .z = 1.0 },
        .end_scale = .{ .x = 1.65, .y = 2.80, .z = 1.0 },
        .color_gradient = FlameGradient,
    };
    profiles[1] = .{
        .geometry = .sprite,
        .mesh_instance = particleMeshInstance(particle_shader, Color.rgba(180, 222, 255, 120)),
        .base_scale = .{ .x = 0.06, .y = 4.0, .z = 1.0 },
        .end_scale = .{ .x = 0.12, .y = 8.0, .z = 1.0 },
        .color_gradient = SparkGradient,
    };
    profiles[2] = .{
        .geometry = .billboard,
        .mesh_instance = particleMeshInstance(particle_shader, Color.rgba(62, 58, 56, 46)),
        .base_scale = .{ .x = 1.50, .y = 1.00, .z = 1.0 },
        .end_scale = .{ .x = 3.56, .y = 1.20, .z = 1.0 },
        .color_gradient = SmokeGradient,
    };
    return profiles;
}

fn particleMeshInstance(shader: render.ShaderHandle, color: Color) render.MeshInstance {
    return .{
        .shader_handle = shader,
        .material = render.Material{ .alpha_mode = .Blend },
        .color = color,
    };
}

fn createFountainEmitters(commands: *ecs.Commands) !void {
    _ = try commands.createEntity(.{particles.ParticleEmitter{
        .profile_index = 0,
        .position = .{ .x = 0.0, .y = 0.10, .z = 0.0 },
        .direction = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .rate = 230.0,
        .radius = 0.18,
        .spread_radians = 0.24,
        .speed = .{ .min = 3.8, .max = 6.4 },
        .lifetime = .{ .min = 0.48, .max = 0.95 },
        .size = .{ .min = 0.18, .max = 0.34 },
        .stretch = .{ .min = 1.2, .max = 1.9 },
        .drag = .{ .min = 1.8, .max = 3.0 },
        .acceleration = .{ .x = 0.0, .y = 2.1, .z = 0.0 },
        .turbulence = 0.55,
        .spin_speed = .{ .min = -2.8, .max = 2.8 },
        .rng_state = 0x21d7_3141_baad_f00d,
    }});
    _ = try commands.createEntity(.{particles.ParticleEmitter{
        .profile_index = 1,
        .position = .{ .x = 0.0, .y = 0.10, .z = 0.0 },
        .direction = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .rate = 70.0,
        .radius = 0.16,
        .spread_radians = 0.32,
        .speed = .{ .min = 5.4, .max = 8.2 },
        .lifetime = .{ .min = 0.34, .max = 0.68 },
        .size = .{ .min = 0.08, .max = 0.15 },
        .stretch = .{ .min = 1.8, .max = 2.7 },
        .drag = .{ .min = 2.4, .max = 4.1 },
        .acceleration = .{ .x = 0.0, .y = 0.8, .z = 0.0 },
        .turbulence = 0.75,
        .spin_speed = .{ .min = -3.5, .max = 3.5 },
        .rng_state = 0x77aa_9931_52f0_1234,
    }});
    _ = try commands.createEntity(.{particles.ParticleEmitter{
        .profile_index = 2,
        .position = .{ .x = 0.0, .y = 0.10, .z = 0.0 },
        .direction = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .rate = 48.0,
        .radius = 0.22,
        .spread_radians = 0.38,
        .speed = .{ .min = 1.3, .max = 2.6 },
        .lifetime = .{ .min = 1.1, .max = 2.2 },
        .size = .{ .min = 0.18, .max = 0.32 },
        .stretch = .{ .min = 1.0, .max = 1.35 },
        .drag = .{ .min = 0.45, .max = 1.0 },
        .acceleration = .{ .x = 0.0, .y = 0.35, .z = 0.0 },
        .turbulence = 0.46,
        .spin_speed = .{ .min = -1.4, .max = 1.4 },
        .rng_state = 0xc001_d00d_1234_7777,
    }});
}

fn createGroundPlane(build: *const render.BuildContext) !render.MeshHandle {
    const size = 22.0;
    const vertices = [_]render.VertexPos3Color{
        .{ .position = .{ -size, 0.0, -size }, .color = .{ 0.34, 0.28, 0.26, 1.0 } },
        .{ .position = .{ size, 0.0, -size }, .color = .{ 0.30, 0.24, 0.22, 1.0 } },
        .{ .position = .{ size, 0.0, size }, .color = .{ 0.22, 0.18, 0.17, 1.0 } },
        .{ .position = .{ -size, 0.0, size }, .color = .{ 0.26, 0.22, 0.20, 1.0 } },
    };
    const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };
    return build.addMeshPos3Color(vertices[0..], indices[0..]);
}

const FlameGradient = common.Gradient.initComptime(.{
    .stops = .{
        .{ .at = 0.0, .color = Color.rgba(255, 244, 214, 230) },
        .{ .at = 0.34, .color = Color.rgba(255, 164, 62, 218) },
        .{ .at = 0.72, .color = Color.rgba(255, 66, 18, 132) },
        .{ .at = 1.0, .color = Color.rgba(34, 6, 2, 0) },
    },
});

const SparkGradient = common.Gradient.initComptime(.{
    .stops = .{
        .{ .at = 0.0, .color = Color.rgba(142, 225, 255, 128) },
        .{ .at = 0.42, .color = Color.rgba(255, 190, 80, 108) },
        .{ .at = 1.0, .color = Color.rgba(255, 96, 18, 0) },
    },
});

const SmokeGradient = common.Gradient.initComptime(.{
    .stops = .{
        .{ .at = 0.0, .color = Color.rgba(70, 66, 64, 0) },
        .{ .at = 0.18, .color = Color.rgba(70, 66, 64, 46) },
        .{ .at = 1.0, .color = Color.rgba(18, 18, 20, 0) },
    },
});

// Imports

const std = @import("std");
const phasor = @import("phasor");

const ecs = phasor.ecs;
const modules = phasor.modules;
const particles = phasor.particles;
const render = phasor.renderer;
const common = phasor.common;
const platform = phasor.platform;

const ElapsedTime = modules.TimeModule.ElapsedTime;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;

const Vec3 = common.Vec3;
const Quat = common.Quat;
const Color = common.Color;
const Transform = common.Transform;
const Camera3d = common.Camera3d;
const ClearColor = common.ClearColor;
const CameraLayer = render.CameraLayer;

const App = phasor.App;
