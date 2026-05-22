//! A simple bouncing ball example using Phasor.

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

    // TODO: move VSync into the WindowSettings resource?
    try app.insertResource(VSync{ .enabled = false });

    // ClearColor is used by the RenderModule to clear the screen at the beginning of each frame.
    try app.insertResource(ClearColor{ .color = Color.WHITE });

    // This installs the time, timer, window, render, input, audio, and parent modules.
    try app.installDefaultModules();

    // This displays diagnostic text such as the FPS counter and frame time in the
    // bottom-right corner of the screen.
    try app.installModule(MetricsModule(.{ .font_size = 24.0 }));

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

// Ball marks which circle should use the bounce behavior.
const Ball = struct {};

// Velocity stores the ball's movement speed in pixels per second.
const Velocity = struct {
    v: Vec3 = .{},
};

// Systems

fn setup(
    commands: *Commands,
    r_window: Res(WindowBounds),
) !void {
    // The ball will be rendered as a circle with this radius.
    const radius: f32 = 40.0;

    // WindowBounds is inserted by the WindowModule and stores the current window size.
    const window = r_window.ptr;

    // Put the ball in the middle of the window.
    const center_screen = Vec3{
        .x = @as(f32, @floatFromInt(window.width)) * 0.5,
        .y = @as(f32, @floatFromInt(window.height)) * 0.5,
    };

    // Create a camera. The TopLeft viewport mode makes 2D coordinates start
    // in the top-left corner of the window instead of the center.
    _ = try commands.createEntity(.{
        Transform{},
        Camera{ .Viewport = .{ .mode = .TopLeft } },
    });

    // Create the ball entity itself.
    _ = try commands.createEntity(.{
        Ball{},
        Velocity{ .v = .{ .x = 220.0, .y = 160.0 } },
        Transform{ .translation = center_screen },
        Circle{ .radius = radius, .segments = 48, .color = Color.RED },
    });
}

fn updateBallMotion(dt: Res(DeltaTime), query: Query(.{ Transform, Velocity })) !void {
    // DeltaTime tells us how much time passed since the last frame.
    const step = dt.deref().seconds32();

    // Query gives us every entity that has both Transform and Velocity.
    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const velocity = row.get(Velocity) orelse continue;

        // Move the ball by velocity * time so the speed is framerate-independent.
        transform.translation.x += velocity.v.x * step;
        transform.translation.y += velocity.v.y * step;
    }
}

fn updateBallBounce(
    query: Query(.{ Transform, Velocity, Ball, Circle }),
    r_window: Res(WindowBounds),
) !void {
    // Convert the window dimensions to floats so we can compare them with the ball position.
    const window = r_window.ptr;
    const window_width: f32 = @floatFromInt(window.width);
    const window_height: f32 = @floatFromInt(window.height);

    // This query includes Ball so only the ball bounces, and Circle because the
    // bounce checks need the circle radius.
    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const velocity = row.get(Velocity) orelse continue;
        const circle = row.get(Circle) orelse continue;
        const radius = circle.radius;

        // Clamp the ball to the left or right edge and flip its horizontal velocity.
        if (transform.translation.x - radius < 0.0) {
            transform.translation.x = radius;
            velocity.v.x *= -1.0;
        } else if (transform.translation.x + radius > window_width) {
            transform.translation.x = window_width - radius;
            velocity.v.x *= -1.0;
        }

        // Clamp the ball to the top or bottom edge and flip its vertical velocity.
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

const Camera = phasor.Camera;
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
