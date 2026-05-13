//! A simple example using the Phasor game engine.

pub fn main(init: std.process.Init) !u8 {
    var app = try App.init(&init, .{
        // This is the maximum number of commands that a system can issue in a single frame.
        // If this limit is exceeded, the app will crash with an error.
        .command_queue_capacity = 64,

        // Enabling parallel systems allows the app to execute systems in parallel when possible,
        // which can improve performance on multi-core CPUs. It won't make a difference in this example.
        .parallel_systems = true,
    });

    // Clean up the app at the end of this function.
    defer app.deinit();

    // Several of the modules use one or more resources for configuration.
    // WindowSettings works with the WindowModule to configure the window.
    try app.insertResource(WindowSettings{
        .title = "Ball",
        .width = 800,
        .height = 600,
    });

    // TODO: move VSync into the WindowSettings resource.
    try app.insertResource(VSync{ .enabled = false });

    // ClearColor is used by the RenderModule to clear the screen at the beginning of each frame.
    try app.insertResource(ClearColor{ .color = .{
        .r = 255,
        .g = 255,
        .b = 255,
        .a = 255,
    } });

    // This installs the time, timer, window, render, input, audio, and parent modules.
    try app.installDefaultModules();

    // This displays diagnostic text such as the FPS counter and frame time in the
    // bottom-right corner of the screen.
    try app.installModule(MetricsModule{ .font_size = 24.0 });

    // Register our system functions. The first argument is the schedule that the system should
    // run in, and the second argument is the system function itself.

    // Startup happens once when the app starts.
    try app.addSystem("Startup", setup);

    // Update happens every frame after Startup.
    try app.addSystem("Update", updateBallMotion);

    // Systems are executed in the order they are added unless they can be run in parallel
    // (and parallel_systems is true in App.init).

    // Here, this system will run after updateBallMotion.
    try app.addSystem("Update", updateBallBounce);

    // Finally, run the app. This will block until the app is exited.
    return try app.run();
}


// Components

const Ball = struct {
    radius: f32,
};

const Velocity = struct {
    v: Vec3 = .{},
};


// Systems

fn setup(
    commands: *Commands,
    r_window: Res(WindowBounds),
) !void {
    const radius: f32 = 40.0;
    const window = r_window.ptr;

    const center_screen = Vec3{
        .x = @as(f32, @floatFromInt(window.width)) * 0.5,
        .y = @as(f32, @floatFromInt(window.height)) * 0.5,
    };

    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
    });

    _ = try commands.createEntity(.{
        Ball{ .radius = radius },
        Velocity{ .v = .{ .x = 220.0, .y = 160.0 } },
        Transform{ .translation = center_screen },
        Circle{ .radius = radius, .segments = 48, .color = Color.RED },
    });
}

fn updateBallMotion(dt: Res(DeltaTime), query: Query(.{ Transform, Velocity })) !void {
    const step = dt.deref().seconds32();
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

const App = phasor.App;

const Camera3d = phasor.Camera3d;
const Circle = phasor.Circle;
const ClearColor = phasor.ClearColor;
const Color = phasor.Color;
const Commands = phasor.Commands;
const DeltaTime = phasor.DeltaTime;
const MetricsModule = phasor.MetricsModule;
const Query = phasor.Query;
const Res = phasor.Res;
const Transform = phasor.Transform;
const Vec3 = phasor.Vec3;
const VSync = phasor.VSync;
const WindowBounds = phasor.WindowBounds;
const WindowSettings = phasor.WindowSettings;
