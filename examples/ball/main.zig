pub fn main(init: std.process.Init) !u8 {
    var app = try App.init(&init, .{
        .command_queue_capacity = 64,
        .parallel_systems = true,
    });
    defer app.deinit();

    try app.insertResource(WindowSettings{
        .title = "Ball",
        .width = 800,
        .height = 600,
    });
    try app.insertResource(VSync{ .enabled = false });
    try app.insertResource(ClearColor{ .color = .{
        .r = 255,
        .g = 255,
        .b = 255,
        .a = 255,
    } });

    try app.installDefaultModules();

    try app.addSystem("Startup", setup);
    try app.addSystem("Update", updateBallMotion);
    try app.addSystem("Update", updateBallBounce);

    return try app.run();
}

const Ball = struct {
    radius: f32,
};

const Velocity = struct {
    v: Vec3 = .{},
};

fn setup(
    commands: *Commands,
    r_window: Res(WindowBounds),
    r_build_ctx: ResMut(BuildContext),
) !void {
    const radius: f32 = 40.0;
    const window = r_window.ptr;
    const build_ctx = r_build_ctx.ptr;

    const center_screen = Vec3{
        .x = @as(f32, @floatFromInt(window.width)) * 0.5,
        .y = @as(f32, @floatFromInt(window.height)) * 0.5,
    };

    var factory = build_ctx.meshFactory();
    const circle_mesh = try factory.circle(radius, 48);

    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
    });

    _ = try commands.createEntity(.{
        Ball{ .radius = radius },
        Velocity{ .v = .{ .x = 220.0, .y = 160.0 } },
        Transform{ .translation = center_screen },
        MeshInstance{ .mesh_handle = circle_mesh, .color = Color.RED },
    });
}

fn updateBallMotion(dt: Res(DeltaTime), query: Query(.{ Transform, Velocity })) !void {
    const step: f32 = @floatCast(dt.deref().seconds);
    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const velocity = row.get(Velocity) orelse continue;
        transform.translation.x += velocity.v.x * step;
        transform.translation.y += velocity.v.y * step;
    }
}

fn updateBallBounce(
    query: Query(.{ Transform, Velocity, Ball }),
    r_window: Res(WindowBounds),
) !void {
    const window = r_window.ptr;
    const window_width: f32 = @floatFromInt(window.width);
    const window_height: f32 = @floatFromInt(window.height);

    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const velocity = row.get(Velocity) orelse continue;
        const ball = row.get(Ball) orelse continue;
        const radius = ball.radius;

        if (transform.translation.x - radius < 0.0) {
            transform.translation.x = radius;
            velocity.v.x *= -1.0;
        } else if (transform.translation.x + radius > window_width) {
            transform.translation.x = window_width - radius;
            velocity.v.x *= -1.0;
        }

        if (transform.translation.y - radius < 0.0) {
            transform.translation.y = radius;
            velocity.v.y *= -1.0;
        } else if (transform.translation.y + radius > window_height) {
            transform.translation.y = window_height - radius;
            velocity.v.y *= -1.0;
        }
    }
}

// Imports
const std = @import("std");
const phasor = @import("phasor");
const common = phasor.common;
const ecs = phasor.ecs;
const platform = phasor.platform;
const modules = phasor.modules;
const renderer = phasor.renderer;
const system_params = ecs.system_params;

const App = phasor.App;

const Color = common.Color;
const ClearColor = common.ClearColor;
const DeltaTime = modules.TimeModule.DeltaTime;
const Camera3d = common.Camera3d;
const Transform = common.Transform;
const Vec3 = common.Vec3;

const Commands = ecs.Commands;
const Query = system_params.Query;
const Res = system_params.Res;
const ResMut = system_params.ResMut;

const WindowBounds = common.WindowBounds;
const WindowSettings = platform.WindowSettings;

const BuildContext = renderer.BuildContext;
const MeshInstance = renderer.MeshInstance;
const VSync = renderer.VSync;
