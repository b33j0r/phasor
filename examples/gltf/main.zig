const std = @import("std");
const phasor = @import("phasor");

const SceneId = enum {
    helmet,
    box,
};

const SceneBinding = struct {
    id: SceneId,
    key: Key,
    asset_name: []const u8,
    overlay: []const u8,
};

const scene_bindings = [_]SceneBinding{
    .{
        .id = .helmet,
        .key = .one,
        .asset_name = "FlightHelmet.gltf",
        .overlay = "Viewing FlightHelmet.gltf  |  Press 2 for Box.glb",
    },
    .{
        .id = .box,
        .key = .two,
        .asset_name = "Box.glb",
        .overlay = "Viewing Box.glb  |  Press 1 for FlightHelmet.gltf",
    },
};

const Assets = struct {
    helmet: Scene = Scene.file("assets/models/FlightHelmet.gltf"),
    box: Scene = Scene.file("assets/models/Box.glb"),
};

const LoaderState = phasor.AssetsLoadState(Assets);

const ActiveScene = struct {
    id: SceneId,
};

const OverlayText = struct {};
const LoadingStatusText = struct {};
const LoadingBarTrack = struct {};
const LoadingBarFill = struct {};

const LoadingUi = struct {
    last_stage: AssetsLoadStage = .idle,
    last_asset_name: []const u8 = "bundle",
    status_buf: [160]u8 = @splat(0),
    status_len: usize = 0,

    fn status(self: *const LoadingUi) []const u8 {
        return self.status_buf[0..self.status_len];
    }
};

const loading_bar_width: f32 = 360.0;
const loading_bar_left: f32 = 220.0;
const loading_bar_center_x: f32 = loading_bar_left + loading_bar_width * 0.5;

pub fn main(init: std.process.Init) !u8 {
    var app = try App.init(&init, .{
        .command_queue_capacity = 128,
        .parallel_systems = true,
    });
    defer app.deinit();

    try app.insertResource(WindowSettings{
        .title = "GLTF",
        .width = 800,
        .height = 600,
    });
    try app.insertResource(VSync{ .enabled = false });
    try app.insertResource(ClearColor{ .color = Color.rgb(10, 12, 18) });
    try app.insertResource(AmbientLight{ .intensity = 0.65 });

    try app.installDefaultModules();
    try app.installModule(AssetsModuleConfigured(Assets, .{
        .loading_policy = .manual,
        .scene_primitives_per_frame = 1,
    }));
    try app.installModule(MetricsModuleLayered(Layer(1000)){
        .font_size = 24.0,
        .text_color = Color.WHITE,
    });

    try app.addSystem("Startup", setup);
    try app.addSystem("Startup", beginLoading);
    try app.addSystem("Update", updateLoadingUi);
    try app.addSystem("Update", switchSceneOnInput);
    try app.addSystem("Update", spinActiveScene);
    try app.addSystem("Update", syncOverlayText);

    return try app.run();
}

fn setup(commands: *Commands, assets: ResMut(Assets)) !void {
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
        Transform{
            .rotation = Quat.lookRotation(.{ .x = 0.35, .y = -0.65, .z = -0.7 }, .{ .y = 1.0 }),
        },
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

    _ = try commands.createEntity(.{
        LoadingStatusText{},
        Transform{ .translation = .{ .x = loading_bar_center_x, .y = 268.0, .z = 0.0 } },
        Text{
            .font_size = 18.0,
            .color = Color.rgb(214, 227, 242),
            .content = "",
            .horizontal_alignment = .Center,
            .vertical_alignment = .Center,
        },
        Layer(1000){},
    });

    _ = try commands.createEntity(.{
        LoadingBarTrack{},
        Transform{ .translation = .{ .x = 400.0, .y = 318.0, .z = 0.0 }, .scale = Vec3.splat(0.0) },
        Rectangle{ .width = loading_bar_width, .height = 18.0, .color = Color.rgb(38, 46, 58) },
        Layer(1000){},
    });

    _ = try commands.createEntity(.{
        LoadingBarFill{},
        Transform{ .translation = .{ .x = loading_bar_left, .y = 318.0, .z = 0.0 }, .scale = Vec3.splat(0.0) },
        Rectangle{ .width = 1.0, .height = 18.0, .color = Color.rgb(90, 190, 255) },
        Layer(1000){},
    });

    _ = try commands.createEntity(.{
        ActiveScene{ .id = .helmet },
        Transform{},
        assets.ptr.helmet.instance(),
    });

    try commands.insertResource(LoadingUi{});
}

fn beginLoading(commands: *Commands, loader: ResMut(LoaderState)) void {
    loader.ptr.beginDefaultSession(commands.io);
}

fn updateLoadingUi(
    events: EventReader(AssetsProgressEvent),
    loader: Res(LoaderState),
    ui: ResMut(LoadingUi),
    status_query: Query(.{ Text, LoadingStatusText }),
    fill_query: Query(.{ Rectangle, Transform, LoadingBarFill }),
    track_query: Query(.{ Transform, LoadingBarTrack }),
) !void {
    while (events.next()) |event| {
        ui.ptr.last_stage = event.stage;
        if (event.asset_name) |name| ui.ptr.last_asset_name = name;
    }

    const loading_visible = !loader.ptr.isComplete();
    const progress = loader.ptr.overallProgress01();
    const counts = loader.ptr.currentCounts();
    const percent: usize = @intFromFloat(progress * 100.0);
    const asset_name = std.fs.path.basename(ui.ptr.last_asset_name);

    ui.ptr.status_len = (try std.fmt.bufPrint(
        &ui.ptr.status_buf,
        "{s} {s}\n{d}% complete ({d}/{d})",
        .{
            stageLabel(ui.ptr.last_stage),
            asset_name,
            percent,
            counts.completed,
            counts.total,
        },
    )).len;

    var status_it = status_query.iterator();
    while (status_it.next()) |row| {
        const text = row.get(Text) orelse continue;
        text.content = if (loading_visible) ui.ptr.status() else "";
    }

    updateLoadingBar(fill_query, track_query, loading_visible, progress);
}

fn switchSceneOnInput(
    commands: *Commands,
    keyboard: Res(Keyboard),
    assets: ResMut(Assets),
    loader: ResMut(LoaderState),
    active_scene: Query(.{ActiveScene}),
) !void {
    const next_scene = requestedScene(keyboard.deref()) orelse return;
    const current = active_scene.first() orelse return;
    const current_scene = current.get(ActiveScene) orelse return;
    if (current_scene.id == next_scene) return;

    var it = active_scene.iterator();
    while (it.next()) |row| {
        try commands.removeEntityTree(row.entity_id);
    }
    loader.ptr.beginDefaultSession(commands.io);
    try spawnScene(commands, assets.ptr, next_scene);
}

fn spinActiveScene(
    elapsed: Res(ElapsedTime),
    assets: Res(Assets),
    active_scene: Query(.{ Transform, ActiveScene }),
) void {
    const seconds: f32 = @floatCast(elapsed.deref().seconds);
    var it = active_scene.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const scene = row.get(ActiveScene) orelse continue;
        transform.* = sceneTransform(sceneBounds(assets.ptr, scene.id), seconds);
    }
}

fn syncOverlayText(
    overlay_query: Query(.{ Text, OverlayText }),
    active_scene: Query(.{ActiveScene}),
) void {
    const overlay = if (active_scene.first()) |row|
        sceneBinding((row.get(ActiveScene) orelse return).id).overlay
    else
        "";

    var it = overlay_query.iterator();
    while (it.next()) |row| {
        const text = row.get(Text) orelse continue;
        text.content = overlay;
    }
}

fn spawnScene(commands: *Commands, assets: *Assets, scene_id: SceneId) !void {
    const scene = switch (scene_id) {
        .helmet => assets.helmet.instance(),
        .box => assets.box.instance(),
    };

    _ = try commands.createEntity(.{
        ActiveScene{ .id = scene_id },
        sceneTransform(sceneBounds(assets, scene_id), 0.0),
        scene,
    });
}

fn requestedScene(keyboard: *const Keyboard) ?SceneId {
    inline for (scene_bindings) |binding| {
        if (keyboard.isKeyPressed(binding.key)) return binding.id;
    }
    return null;
}

fn sceneBinding(scene_id: SceneId) SceneBinding {
    inline for (scene_bindings) |binding| {
        if (binding.id == scene_id) return binding;
    }
    unreachable;
}

fn sceneBounds(assets: *const Assets, scene_id: SceneId) ImportedScene.Bounds {
    return switch (scene_id) {
        .helmet => assets.helmet.bounds(),
        .box => assets.box.bounds(),
    };
}

fn sceneTransform(bounds: ImportedScene.Bounds, seconds: f32) Transform {
    const scale = 1.8 / @max(bounds.maxDimension(), 0.001);
    const center = bounds.center();
    const rotation = Quat.fromAxisAngle(.{ .y = 1.0 }, seconds * 0.45);
    return .{
        .translation = .{ .x = -center.x * scale, .y = -center.y * scale, .z = -3.8 },
        .scale = Vec3.splat(scale),
        .rotation = rotation,
    };
}

fn updateLoadingBar(
    fill_query: Query(.{ Rectangle, Transform, LoadingBarFill }),
    track_query: Query(.{ Transform, LoadingBarTrack }),
    visible: bool,
    progress01: f32,
) void {
    const scale = if (visible) Vec3.splat(1.0) else Vec3.splat(0.0);

    var track_it = track_query.iterator();
    while (track_it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.scale = scale;
    }

    const fill_width = @max(1.0, loading_bar_width * std.math.clamp(progress01, 0.0, 1.0));
    var fill_it = fill_query.iterator();
    while (fill_it.next()) |row| {
        const rectangle = row.get(Rectangle) orelse continue;
        const transform = row.get(Transform) orelse continue;
        rectangle.width = fill_width;
        transform.translation.x = loading_bar_left + fill_width * 0.5;
        transform.scale = scale;
    }
}

fn stageLabel(stage: AssetsLoadStage) []const u8 {
    return switch (stage) {
        .idle => "idle",
        .bundle_started => "Starting",
        .bundle_planning => "Planning",
        .bundle_plan_complete => "Planned",
        .bundle_executing => "Loading",
        .asset_discovered => "Found",
        .asset_planned => "Planned",
        .asset_execute => "Loading",
        .scene_prepared => "Prepared",
        .scene_instance_gpu_started => "Uploading",
        .scene_instance_gpu_progress => "Uploading",
        .asset_complete => "Loaded",
        .bundle_complete => "Ready",
    };
}

const AmbientLight = phasor.AmbientLight;
const App = phasor.App;
const AssetsLoadStage = phasor.AssetsLoadStage;
const AssetsModuleConfigured = phasor.AssetsModuleConfigured;
const Camera3d = phasor.Camera3d;
const CameraLayer = phasor.CameraLayer;
const ClearColor = phasor.ClearColor;
const Color = phasor.Color;
const Commands = phasor.Commands;
const ElapsedTime = phasor.ElapsedTime;
const EventReader = phasor.EventReader;
const ImportedScene = phasor.ImportedScene;
const Key = phasor.Key;
const Keyboard = phasor.Keyboard;
const Layer = phasor.Layer;
const Light = phasor.Light;
const MetricsModuleLayered = phasor.MetricsModuleLayered;
const Query = phasor.Query;
const Quat = phasor.Quat;
const Rectangle = phasor.Rectangle;
const Res = phasor.Res;
const ResMut = phasor.ResMut;
const Scene = phasor.Scene;
const Text = phasor.Text;
const Transform = phasor.Transform;
const Vec3 = phasor.Vec3;
const VSync = phasor.VSync;
const WindowSettings = phasor.WindowSettings;
const AssetsProgressEvent = phasor.AssetsProgressEvent;
