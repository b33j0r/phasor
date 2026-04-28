const App = phasor.App;

pub fn main(init: std.process.Init) !u8 {
    var app = try App.default(&init);
    defer app.deinit();

    try app.installDefaultModules();
    try app.addSystemTo("Startup", setupScene);

    return try app.run();
}

fn setupScene(commands: *ecs.Commands) !void {
    _ = try commands.createEntity(.{
        Triangle{
            .vertices = .{
                .{ .position = .{ 0.0, 160.0 }, .color = .{ 1.0, 0.2, 0.2 } },
                .{ .position = .{ -160.0, -140.0 }, .color = .{ 0.2, 1.0, 0.2 } },
                .{ .position = .{ 160.0, -140.0 }, .color = .{ 0.2, 0.4, 1.0 } },
            },
        },
    });

    try commands.insertResource(ClearColor{ .color = Color.BLACK });
    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .Center } },
        CameraLayer(0){},
    });
}

// Imports
const std = @import("std");
const phasor = @import("phasor");

const ecs = phasor.ecs;
const render = phasor.renderer;
const common = phasor.common;

const Transform = common.Transform;
const Camera3d = common.Camera3d;
const ClearColor = common.ClearColor;
const Color = common.Color;
const CameraLayer = render.CameraLayer;
const Triangle = render.Triangle;
