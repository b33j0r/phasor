//! A simple example using sprites in the Phasor game engine.

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
        .title = "Sprites",
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

    // AssetsModule loads the texture data declared in the Assets struct below.
    try app.installModule(AssetsModule(Assets));

    // This displays diagnostic text such as the FPS counter and frame time in the
    // bottom-right corner of the screen.
    try app.installModule(MetricsModule{ .font_size = 24.0 });

    // Register our system functions. The first argument is the schedule that the system should
    // run in, and the second argument is the system function itself.

    // Startup happens once when the app starts.
    try app.addSystem("Startup", setup);

    // Finally, run the app. This will block until the app is exited.
    return try app.run();
}

// Assets

// This struct declares the assets that AssetsModule should load.
// The logo texture is embedded in the executable at compile time.
const Assets = struct { logo: Texture = .{
    .data = @embedFile("assets/textures/logo.png"),
} };

// Systems

fn setup(
    commands: *Commands,
    r_window: Res(WindowBounds),
    r_assets: Res(Assets),
) !void {
    // WindowBounds is inserted by the WindowModule and stores the current window size.
    const window = r_window.ptr;

    // Put the sprite in the middle of the window.
    const center_screen = Vec3{
        .x = @as(f32, @floatFromInt(window.width)) * 0.5,
        .y = @as(f32, @floatFromInt(window.height)) * 0.5,
    };

    // This replaces the startup clear color with the named Color.WHITE constant.
    try commands.insertResource(ClearColor{ .color = Color.WHITE });

    // Create a camera. The TopLeft viewport mode makes 2D coordinates start
    // in the top-left corner of the window instead of the center.
    // CameraLayer(0) tells the camera to render entities on layer 0.
    _ = try commands.createEntity(.{
        Transform{},
        Camera{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(0){},
    });

    // Create a parent entity at the center of the screen.
    const centroid = try commands.createEntity(.{
        Transform{ .translation = center_screen },
    });

    // Draw the logo as a 60 by 60 pixel sprite.
    const sprite_size: f32 = 60.0;

    // Create the sprite entity. It has:
    // - Parent and LocalTransform so its position is relative to the centered parent.
    // - Transform for the final world-space position.
    // - Sprite so the renderer knows what texture to draw.
    _ = try commands.createEntity(.{
        Parent{ .id = centroid },
        LocalTransform{
            .translation = .{ .x = 0.0, .y = 0.0, .z = 1.0 },
        },
        Transform{},
        Sprite{
            .material = r_assets.ptr.logo.material,
            .color = Color.WHITE,
            // Manual size mode overrides the texture's natural pixel dimensions.
            .size_mode = .{ .Manual = .{ .width = sprite_size, .height = sprite_size } },
        },
    });
}

// Imports
const std = @import("std");
const phasor = @import("phasor");

const App = phasor.App;
const AssetsModule = phasor.AssetsModule;
const BuildContext = phasor.BuildContext;
const Camera = phasor.Camera;
const CameraLayer = phasor.CameraLayer;
const ClearColor = phasor.ClearColor;
const Color = phasor.Color;
const Commands = phasor.Commands;
const DeltaTime = phasor.DeltaTime;
const LocalTransform = phasor.LocalTransform;
const MetricsModule = phasor.MetricsModule;
const Parent = phasor.Parent;
const ParentModule = phasor.ParentModule;
const Query = phasor.Query;
const Res = phasor.Res;
const ResMut = phasor.ResMut;
const ResOpt = phasor.ResOpt;
const Sprite = phasor.Sprite;
const Transform = phasor.Transform;
const Vec3 = phasor.Vec3;
const Texture = phasor.Texture;
const WindowSettings = phasor.WindowSettings;
const WindowBounds = phasor.WindowBounds;
const VSync = phasor.VSync;
