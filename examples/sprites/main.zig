pub fn main(init: std.process.Init) !u8 {
    var app = try App.init(&init, .{
        .command_queue_capacity = 64,
        .parallel_systems = true,
    });
    defer app.deinit();

    try app.insertResource(WindowSettings{
        .title = "Sprites",
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
    try app.installModule(AssetsModule(Assets));

    try app.addSystem("Startup", setup);

    return try app.run();
}

const Assets = struct {
    logo: Texture = .{
        .data = @embedFile("assets/textures/logo.png"),
    }
};

fn setup(
    commands: *Commands,
    r_window: Res(WindowBounds),
    r_assets: Res(Assets),
) !void {
    const window = r_window.ptr;
    const material = r_assets.ptr.logo.material;

    const center_screen = Vec3{
        .x = @as(f32, @floatFromInt(window.width)) * 0.5,
        .y = @as(f32, @floatFromInt(window.height)) * 0.5,
    };

    try commands.insertResource(ClearColor{ .color = Color.WHITE });
    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(0){},
    });

    const centroid = try commands.createEntity(.{
        Transform{ .translation = center_screen },
    });

    const sprite_size: f32 = 60.0;
    _ = try commands.createEntity(.{
        Parent{ .id = centroid },
        LocalTransform{
            .translation = .{ .x = 0.0, .y = 0.0, .z = 1.0 },
        },
        Transform{},
        Sprite{
            .color = Color.WHITE,
            .size_mode = .{ .Manual = .{ .width = sprite_size, .height = sprite_size } },
        },
        MeshInstance{ .material = material },
    });
}

// Imports
const std = @import("std");
const phasor = @import("phasor");

const App = phasor.App;
const AssetsModule = phasor.AssetsModule;
const BuildContext = phasor.BuildContext;
const Camera3d = phasor.Camera3d;
const CameraLayer = phasor.CameraLayer;
const ClearColor = phasor.ClearColor;
const Color = phasor.Color;
const Commands = phasor.Commands;
const DeltaTime = phasor.DeltaTime;
const LocalTransform = phasor.LocalTransform;
const MeshInstance = phasor.MeshInstance;
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
