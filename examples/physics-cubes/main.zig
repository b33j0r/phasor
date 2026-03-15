const DemoConfig = struct {
    cube_count: u32 = 128,
    cubes_per_second: f32 = 24.0,
};

const SpawnState = struct {
    spawned: u32 = 0,
    accumulator: f32 = 0.0,
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) SpawnState {
        return .{
            .prng = std.Random.DefaultPrng.init(seed),
        };
    }
};

const App = struct {
    pub const options = platform.Options{
        .window = .{
            .title = "Phasor Lite - Physics Cubes",
            .width = 1280,
            .height = 800,
        },
    };

    pub fn configure(app: *ecs.App) !void {
        try platform.installDefaultModules(app);
        try app.installModule(modules.ParentModule);
        try app.installModule(modules.AssetsModule(Assets));
        try app.installModule(physics.PhysicsModule{
            .config = .{
                .backend = .Jolt,
                .fixed_dt = 1.0 / 60.0,
                .max_substeps = 8,
                .gravity = .{ .x = 0.0, .y = -9.81, .z = 0.0 },
            },
        });
        try app.installModule(modules.MetricsModuleLayered(render.Layer(1000)){
            .font_size = 24.0,
            .text_color = Color.WHITE,
        });

        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("Update", spawnCubes);
    }
};

pub const std_options = phasor.common.logging.stdOptions(.debug);

var g_demo_config = DemoConfig{};

pub fn main(init: std.process.Init) !u8 {
    g_demo_config = .{};
    if (!try parseArgs(init, &g_demo_config)) return 0;

    const entry = platform.main(App);
    return try entry(init);
}

fn setupScene(commands: *ecs.Commands, demo_assets: Res(Assets)) !void {
    const assets_ptr = demo_assets.ptr;
    if (!assets_ptr.cube_mesh.handle.isValid()) return error.CubeMeshMissing;
    if (!assets_ptr.cube_shader.handle.isValid()) return error.CubeShaderMissing;

    try commands.insertResource(SpawnState.init(0xC0B_E123));
    try commands.insertResource(ClearColor{ .color = Color.rgb(18, 24, 34) });

    std.log.info(
        "physics cubes demo: count={d} rate={d:.2} cubes/s gravity={d:.2} m/s^2",
        .{ g_demo_config.cube_count, g_demo_config.cubes_per_second, 9.81 },
    );

    const cube_material = render.Material.withShader(assets_ptr.cube_shader.handle);

    _ = try commands.createEntity(.{
        Transform{
            .translation = .{ .x = 0.0, .y = -0.5, .z = 0.0 },
            .scale = .{ .x = 20.0, .y = 0.5, .z = 20.0 },
        },
        render.MeshInstance{
            .mesh_handle = assets_ptr.cube_mesh.handle,
            .material = cube_material,
            .color = Color.rgb(110, 118, 132),
        },
        render.Layer(0){},
        physics.Body{ .kind = .Static },
        physics.Collider{
            .shape = .{ .Box = .{ .half_extents = .{ .x = 20.0, .y = 0.5, .z = 20.0 } } },
            .material = .{ .friction = 0.85, .restitution = 0.02 },
        },
    });

    _ = try commands.createEntity(.{
        Transform{
            .translation = .{ .x = 0.0, .y = 9.5, .z = 18.0 },
            .rotation = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, -0.42),
        },
        Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.0,
            .near = 0.1,
            .far = 250.0,
        } },
        CameraLayer(0){},
    });

    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(1000){},
    });
}

fn spawnCubes(
    commands: *ecs.Commands,
    dt: Res(DeltaTime),
    spawn_state: ResMut(SpawnState),
    demo_assets: Res(Assets),
) !void {
    if (spawn_state.ptr.spawned >= g_demo_config.cube_count) return;

    const step: f32 = @floatCast(dt.deref().seconds);
    spawn_state.ptr.accumulator += step * g_demo_config.cubes_per_second;

    while (spawn_state.ptr.accumulator >= 1.0 and spawn_state.ptr.spawned < g_demo_config.cube_count) {
        spawn_state.ptr.accumulator -= 1.0;
        try spawnCube(commands, spawn_state.ptr, demo_assets.ptr);
    }
}

fn spawnCube(commands: *ecs.Commands, spawn_state: *SpawnState, demo_assets: *const Assets) !void {
    const rand = spawn_state.prng.random();
    const stack_layer = spawn_state.spawned / 16;
    const layer_y = 8.0 + @as(f32, @floatFromInt(stack_layer)) * 1.35;
    const spawn_position = Vec3{
        .x = (rand.float(f32) - 0.5) * 3.5,
        .y = layer_y,
        .z = (rand.float(f32) - 0.5) * 3.5,
    };
    const color = cube_palette[@intCast(spawn_state.spawned % cube_palette.len)];

    _ = try commands.createEntity(.{
        Transform{
            .translation = spawn_position,
            .scale = Vec3.splat(0.5),
        },
        render.MeshInstance{
            .mesh_handle = demo_assets.cube_mesh.handle,
            .material = render.Material.withShader(demo_assets.cube_shader.handle),
            .color = color,
        },
        render.Layer(0){},
        physics.Body{
            .kind = .Dynamic,
            .linear_damping = 0.02,
            .angular_damping = 0.05,
            .is_ccd = true,
        },
        physics.Collider{
            .shape = .{ .Box = .{ .half_extents = Vec3.splat(0.5) } },
            .material = .{ .friction = 0.7, .restitution = 0.05 },
            .density = 80.0,
        },
        physics.MassProperties{
            .mode = .Explicit,
            .mass = 12.0,
        },
    });

    spawn_state.spawned += 1;
}

fn parseArgs(init: std.process.Init, out: *DemoConfig) !bool {
    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    _ = it.skip();

    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--count")) {
            const value = nextArg(&it) orelse return invalidArguments("missing value for --count");
            out.cube_count = std.fmt.parseInt(u32, value, 10) catch return invalidArguments("invalid --count");
        } else if (std.mem.eql(u8, arg, "--rate")) {
            const value = nextArg(&it) orelse return invalidArguments("missing value for --rate");
            out.cubes_per_second = std.fmt.parseFloat(f32, value) catch return invalidArguments("invalid --rate");
        } else if (std.mem.eql(u8, arg, "--help")) {
            printUsage();
            return false;
        } else {
            return invalidArguments("unknown argument");
        }
    }

    if (out.cube_count == 0) return invalidArguments("--count must be > 0");
    if (!(out.cubes_per_second > 0.0)) return invalidArguments("--rate must be > 0");
    return true;
}

fn invalidArguments(message: []const u8) error{InvalidArguments}!bool {
    std.log.err("{s}", .{message});
    printUsage();
    return error.InvalidArguments;
}

fn nextArg(it: *std.process.Args.Iterator) ?[]const u8 {
    return it.next();
}

fn printUsage() void {
    std.debug.print(
        \\Usage: zig build run-physics-cubes-native -- [--count N] [--rate CUBES_PER_SECOND]
        \\  --count  Total number of 1 m cubes to spawn. Default: 128
        \\  --rate   Spawn rate in cubes per second. Default: 24
        \\Example:
        \\  zig build run-physics-cubes-native -- --count 250 --rate 40
        \\
    , .{});
}

const cube_palette = [_]Color{
    Color.rgb(218, 84, 62),
    Color.rgb(233, 167, 64),
    Color.rgb(223, 209, 96),
    Color.rgb(99, 181, 123),
    Color.rgb(83, 149, 214),
    Color.rgb(165, 124, 214),
};

const Assets = struct {
    cube_mesh: assets.Mesh = .{
        .pos3_color_vertices = cube_vertices[0..],
        .indices = cube_indices[0..],
    },
    cube_shader: assets.Shader = .{
        .wgsl_source = @embedFile("shaders/cube_color.wgsl"),
    },
};

const cube_vertices = [_]render.VertexPos3Color{
    .{ .position = .{ -1.0, -1.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, -1.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, 1.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .position = .{ -1.0, 1.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, -1.0, -1.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
    .{ .position = .{ -1.0, -1.0, -1.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
    .{ .position = .{ -1.0, 1.0, -1.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
    .{ .position = .{ 1.0, 1.0, -1.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
    .{ .position = .{ 1.0, -1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, -1.0, -1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, 1.0, -1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, 1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ -1.0, -1.0, -1.0 }, .color = .{ 1.0, 0.5, 0.0, 1.0 } },
    .{ .position = .{ -1.0, -1.0, 1.0 }, .color = .{ 1.0, 0.5, 0.0, 1.0 } },
    .{ .position = .{ -1.0, 1.0, 1.0 }, .color = .{ 1.0, 0.5, 0.0, 1.0 } },
    .{ .position = .{ -1.0, 1.0, -1.0 }, .color = .{ 1.0, 0.5, 0.0, 1.0 } },
    .{ .position = .{ -1.0, 1.0, 1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, 1.0, 1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, 1.0, -1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ -1.0, 1.0, -1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ -1.0, -1.0, -1.0 }, .color = .{ 0.6, 0.2, 0.8, 1.0 } },
    .{ .position = .{ 1.0, -1.0, -1.0 }, .color = .{ 0.6, 0.2, 0.8, 1.0 } },
    .{ .position = .{ 1.0, -1.0, 1.0 }, .color = .{ 0.6, 0.2, 0.8, 1.0 } },
    .{ .position = .{ -1.0, -1.0, 1.0 }, .color = .{ 0.6, 0.2, 0.8, 1.0 } },
};

const cube_indices = [_]u16{
    0,  1,  2,  0,  2,  3,
    4,  5,  6,  4,  6,  7,
    8,  9,  10, 8,  10, 11,
    12, 13, 14, 12, 14, 15,
    16, 17, 18, 16, 18, 19,
    20, 21, 22, 20, 22, 23,
};

const std = @import("std");
const phasor = @import("phasor");

const ecs = phasor.ecs;
const modules = phasor.modules;
const assets = phasor.assets;
const common = phasor.common;
const render = phasor.renderer;
const physics = phasor.physics;
const platform = phasor.platform;

const DeltaTime = modules.TimeModule.DeltaTime;
const system_params = ecs.system_params;
const Res = system_params.Res;
const ResMut = system_params.ResMut;

const Vec3 = common.Vec3;
const Quat = common.Quat;
const Color = common.Color;
const Transform = common.Transform;
const Camera3d = common.Camera3d;
const ClearColor = common.ClearColor;
const CameraLayer = render.CameraLayer;
