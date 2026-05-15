//! A simple glTF/glB model viewer using Phasor asset paths.

pub fn main(init: std.process.Init) !u8 {
    var app = try App.init(&init, .{
        .command_queue_capacity = 1024,
        .parallel_systems = true,
    });
    defer app.deinit();

    try app.insertResource(WindowSettings{
        .title = "glTF and GLB",
        .width = 1280,
        .height = 900,
    });
    try app.insertResource(VSync{ .enabled = false });
    try app.insertResource(ClearColor{ .color = Color.rgb(10, 12, 18) });
    try app.insertResource(AmbientLight{ .intensity = 0.65 });

    try app.installDefaultModules();
    try app.installModule(AssetsModule(Assets));
    try app.installModule(ViewerPhases);
    try app.installModule(MetricsModuleLayered(Layer(1000)){
        .font_size = 24.0,
        .text_color = Color.WHITE,
    });

    try app.addSystem("Startup", setupViewer);
    try app.addSystem("BeforeFrame", setupViewer);
    try app.addSystem("Update", switchModels);
    try app.addSystem("Update", updateModelView);

    return try app.run();
}

const Assets = struct {
    helmet: Scene = Scene.file("assets/models/FlightHelmet.gltf"),
    box: Scene = Scene.file("assets/models/Box.glb"),
};

const Helmet = struct {};
const Box = struct {};
const OverlayText = struct {};
const ViewerReady = struct {};
const LoadedScenes = struct {
    flight_helmet: ImportedScene,
    box: ImportedScene,

    pub fn deinit(self: *LoadedScenes) void {
        self.flight_helmet.deinit();
        self.box.deinit();
    }
};

const Phases = enum { helmet, box };

const ViewerPhases = PhasesModule.Definition(Phases, .helmet);

fn setupViewer(
    commands: *Commands,
    r_assets: ResMut(Assets),
    r_build_ctx: ResOpt(BuildContext),
    r_ready: HasResource(ViewerReady),
) !void {
    if (r_ready.value) return;
    const build_ctx = r_build_ctx.ptr orelse return;
    if (!r_assets.ptr.helmet.isLoaded() or !r_assets.ptr.box.isLoaded()) return;

    const helmet_root = try commands.createEntity(.{ Helmet{}, Transform{}, Layer(0){} });
    const box_root = try commands.createEntity(.{ Box{}, Transform{ .scale = Vec3.splat(0.0) }, Layer(0){} });

    const helmet_scene = try r_assets.ptr.helmet.instantiate(commands.allocator, commands, build_ctx, .{ .parent = helmet_root });
    const box_scene = try r_assets.ptr.box.instantiate(commands.allocator, commands, build_ctx, .{ .parent = box_root });
    try commands.insertResource(LoadedScenes{
        .flight_helmet = helmet_scene,
        .box = box_scene,
    });

    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.0,
            .near = 0.05,
            .far = 100.0,
        } },
        CameraLayer(0){},
    });

    _ = try commands.createEntity(.{
        Transform{ .rotation = Quat.lookRotation(.{ .x = -0.35, .y = -0.65, .z = -0.7 }, .{ .y = 1.0 }) },
        Light{ .directional = .{ .illuminance_lux = 65000.0 } },
    });

    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(1000){},
    });

    _ = try commands.createEntity(.{
        OverlayText{},
        Transform{ .translation = .{ .x = 24.0, .y = 24.0, .z = 0.0 } },
        Text{
            .font_size = 24.0,
            .color = Color.WHITE,
            .content = "",
        },
        Layer(1000){},
    });

    try commands.insertResource(ViewerReady{});
}

fn switchModels(commands: *Commands, keyboard: Res(Keyboard)) !void {
    const keys = keyboard.deref();
    if (keys.isKeyPressed(.one)) {
        try commands.insertResource(ViewerPhases.NextPhase{ .phase = .helmet });
    } else if (keys.isKeyPressed(.two)) {
        try commands.insertResource(ViewerPhases.NextPhase{ .phase = .box });
    }
}

fn updateModelView(
    elapsed: Res(ElapsedTime),
    phase: ResOpt(ViewerPhases.CurrentPhase),
    assets: Res(Assets),
    helmets: Query(.{ Transform, Helmet }),
    boxes: Query(.{ Transform, Box }),
    overlay: Query(.{ Text, OverlayText }),
) !void {
    const active = if (phase.ptr) |current| current.phase else .helmet;
    const t: f32 = @floatCast(elapsed.deref().seconds);

    setModelTransform(helmets, assets.ptr.helmet.bounds(), t, active == .helmet);
    setModelTransform(boxes, assets.ptr.box.bounds(), t, active == .box);
    setOverlay(
        overlay,
        switch (active) {
            .helmet => "Viewing FlightHelmet.gltf  |  Press 2 for Box.glb",
            .box => "Viewing Box.glb  |  Press 1 for FlightHelmet.gltf",
        },
    );
}

fn setModelTransform(
    roots: anytype,
    bounds: ImportedScene.Bounds,
    seconds: f32,
    visible: bool,
) void {
    const center = bounds.center();
    const scale = if (visible) 1.8 / @max(bounds.maxDimension(), 0.001) else 0.0;

    var it = roots.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.translation = .{ .x = -center.x * scale, .y = -center.y * scale, .z = -3.8 };
        transform.scale = Vec3.splat(scale);
        transform.rotation = Quat.fromAxisAngle(.{ .y = 1.0 }, seconds * 0.45);
    }
}

fn setOverlay(overlay: Query(.{ Text, OverlayText }), content: []const u8) void {
    var overlay_it = overlay.iterator();
    while (overlay_it.next()) |row| {
        const text = row.get(Text) orelse continue;
        text.content = content;
    }
}

const std = @import("std");
const phasor = @import("phasor");

const AmbientLight = phasor.AmbientLight;
const App = phasor.App;
const AssetsModule = phasor.AssetsModule;
const BuildContext = phasor.BuildContext;
const Camera3d = phasor.Camera3d;
const CameraLayer = phasor.CameraLayer;
const ClearColor = phasor.ClearColor;
const Color = phasor.Color;
const Commands = phasor.Commands;
const ElapsedTime = phasor.ElapsedTime;
const HasResource = phasor.HasResource;
const ImportedScene = phasor.ImportedScene;
const Keyboard = phasor.Keyboard;
const Layer = phasor.Layer;
const Light = phasor.Light;
const MetricsModuleLayered = phasor.MetricsModuleLayered;
const PhasesModule = phasor.PhasesModule;
const Quat = phasor.Quat;
const Query = phasor.Query;
const Res = phasor.Res;
const ResMut = phasor.ResMut;
const ResOpt = phasor.ResOpt;
const Scene = phasor.Scene;
const Text = phasor.Text;
const Transform = phasor.Transform;
const Vec3 = phasor.Vec3;
const VSync = phasor.VSync;
const WindowSettings = phasor.WindowSettings;
