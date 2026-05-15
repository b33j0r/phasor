// Assets
const Assets = struct {
    helmet: Scene = Scene.file("assets/models/FlightHelmet.gltf"),
    box: Scene = Scene.file("assets/models/Box.glb"),
};

const LoaderState = AssetsLoadState(Assets);

// Components
const OverlayText = struct {};
const LoadingStatusText = struct {};
const LoadingBarTrack = struct {};
const LoadingBarFill = struct {};
const HelmetRoot = struct {};
const BoxRoot = struct {};

const LoadingUi = struct {
    last_stage: AssetsLoadStage = .idle,
    last_asset_name: []const u8 = "bundle",
    status_buf: [160]u8 = [_]u8{0} ** 160,
    status_len: usize = 0,

    pub fn status(self: *const LoadingUi) []const u8 {
        return self.status_buf[0..self.status_len];
    }
};

// Main
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
    try app.installModule(ViewerPhases);
    try app.installModule(AssetsModuleConfigured(Assets, .{
        .loading_policy = .manual,
        .scene_primitives_per_frame = 1,
    }));
    try app.installModule(MetricsModuleLayered(Layer(1000)){
        .font_size = 24.0,
        .text_color = Color.WHITE,
    });

    try app.addSystem("Startup", setupViewer);
    try app.addSystem("Update", switchModels);
    try app.addSystem("Update", updateModelView);

    return try app.run();
}

// Phases
const Phases = union(enum) {
    Loading: struct {
        pub fn enter(_: anytype, ctx: *PhaseContext) !void {
            const loader = ctx.getResourceMut(LoaderState) orelse return error.MissingAssetsLoader;
            loader.beginDefaultSession(ctx.io);
            try hideAllModels(ctx);
            try setOverlay(ctx, "");
            try updateLoadingText(ctx, "Planning scene bundle...");
            try setLoadingBar(ctx, true, 0.0);
            try ctx.addSystem("Update", updateLoadingUi);
            try ctx.addSystem("Update", transitionFromLoading);
        }

        pub fn exit(_: anytype, ctx: *PhaseContext) !void {
            try updateLoadingText(ctx, "");
            try setLoadingBar(ctx, false, 0.0);
        }
    },
    Helmet: struct {
        pub fn enter(_: anytype, ctx: *PhaseContext) !void {
            const assets = ctx.getResourceMut(Assets) orelse return error.MissingAssets;
            try setModelState(ctx, HelmetRoot, assets.helmet.bounds(), true);
            try setModelState(ctx, BoxRoot, assets.box.bounds(), false);
            try setOverlay(ctx, "Viewing FlightHelmet.gltf  |  Press 2 for Box.glb");
            try updateLoadingText(ctx, "");
            try setLoadingBar(ctx, false, 0.0);
        }

        pub fn exit(_: anytype, _: *PhaseContext) !void {}
    },
    Box: struct {
        pub fn enter(_: anytype, ctx: *PhaseContext) !void {
            const assets = ctx.getResourceMut(Assets) orelse return error.MissingAssets;
            try setModelState(ctx, HelmetRoot, assets.helmet.bounds(), false);
            try setModelState(ctx, BoxRoot, assets.box.bounds(), true);
            try setOverlay(ctx, "Viewing Box.glb  |  Press 1 for FlightHelmet.gltf");
            try updateLoadingText(ctx, "");
            try setLoadingBar(ctx, false, 0.0);
        }

        pub fn exit(_: anytype, _: *PhaseContext) !void {}
    },
};

const ViewerPhases = PhasesModule.Definition(Phases, .{ .Loading = .{} });

// Systems
fn setupViewer(commands: *Commands, assets: ResMut(Assets)) !void {
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

    _ = try commands.createEntity(.{
        LoadingStatusText{},
        Transform{ .translation = .{ .x = 250.0, .y = 270.0, .z = 0.0 } },
        Text{
            .font_size = 22.0,
            .color = Color.WHITE,
            .content = "",
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
        HelmetRoot{},
        Transform{ .scale = Vec3.splat(0.0) },
        assets.ptr.helmet.instance(),
    });
    _ = try commands.createEntity(.{
        BoxRoot{},
        Transform{ .scale = Vec3.splat(0.0) },
        assets.ptr.box.instance(),
    });

    try commands.insertResource(LoadingUi{});
}

fn switchModels(
    commands: *Commands,
    keyboard: Res(Keyboard),
    phase_opt: ResOpt(ViewerPhases.CurrentPhase),
) !void {
    const current = if (phase_opt.ptr) |phase| phase.phase else return;
    switch (current) {
        .Loading => return,
        .Helmet => {},
        .Box => {},
    }

    const keys = keyboard.deref();
    if (keys.isKeyPressed(.one)) {
        try commands.insertResource(ViewerPhases.NextPhase{ .phase = .{ .Helmet = .{} } });
    } else if (keys.isKeyPressed(.two)) {
        try commands.insertResource(ViewerPhases.NextPhase{ .phase = .{ .Box = .{} } });
    }
}

fn updateModelView(
    elapsed: Res(ElapsedTime),
    phase_opt: ResOpt(ViewerPhases.CurrentPhase),
    assets: Res(Assets),
    helmets: Query(.{ Transform, HelmetRoot }),
    boxes: Query(.{ Transform, BoxRoot }),
    overlay: Query(.{ Text, OverlayText }),
) void {
    const current = if (phase_opt.ptr) |phase| phase.phase else return;
    const helmet_visible = switch (current) {
        .Loading => return,
        .Helmet => true,
        .Box => false,
    };
    const seconds: f32 = @floatCast(elapsed.deref().seconds);

    setModelTransform(helmets, assets.ptr.helmet.bounds(), seconds, helmet_visible);
    setModelTransform(boxes, assets.ptr.box.bounds(), seconds, !helmet_visible);
    setOverlayText(
        overlay,
        if (helmet_visible)
            "Viewing FlightHelmet.gltf  |  Press 2 for Box.glb"
        else
            "Viewing Box.glb  |  Press 1 for FlightHelmet.gltf",
    );
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
        if (event.asset_name) |name| {
            ui.ptr.last_asset_name = name;
        }
    }

    const counts = loader.ptr.currentCounts();
    const progress = loader.ptr.overallProgress01();
    const percent: usize = @intFromFloat(progress * 100.0);
    ui.ptr.status_len = (try std.fmt.bufPrint(
        &ui.ptr.status_buf,
        "{s} {s}  {d}% ({d}/{d})",
        .{
            stageLabel(ui.ptr.last_stage),
            ui.ptr.last_asset_name,
            percent,
            counts.completed,
            counts.total,
        },
    )).len;

    var status_it = status_query.iterator();
    while (status_it.next()) |row| {
        const text = row.get(Text) orelse continue;
        text.content = ui.ptr.status();
    }

    updateLoadingBarRows(fill_query, track_query, true, progress);
}

fn updateLoadingBarRows(
    fill_query: anytype,
    track_query: anytype,
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

fn transitionFromLoading(commands: *Commands, loader: Res(LoaderState)) !void {
    if (!loader.ptr.isComplete()) return;
    try commands.insertResource(ViewerPhases.NextPhase{ .phase = .{ .Helmet = .{} } });
}

fn hideAllModels(ctx: *PhaseContext) !void {
    try setHidden(ctx, HelmetRoot);
    try setHidden(ctx, BoxRoot);
}

fn setModelState(
    ctx: *PhaseContext,
    comptime Tag: type,
    bounds: ImportedScene.Bounds,
    visible: bool,
) !void {
    var roots = try ctx.query(.{ Transform, Tag });
    defer roots.deinit();

    var it = roots.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.* = if (visible) modelTransform(bounds) else hiddenTransform();
    }
}

fn setModelTransform(
    roots: anytype,
    bounds: ImportedScene.Bounds,
    seconds: f32,
    visible: bool,
) void {
    const scale = if (visible) 1.8 / @max(bounds.maxDimension(), 0.001) else 0.0;
    const center = bounds.center();
    const rotation = Quat.fromAxisAngle(.{ .y = 1.0 }, seconds * 0.45);

    var it = roots.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.translation = .{ .x = -center.x * scale, .y = -center.y * scale, .z = -3.8 };
        transform.scale = Vec3.splat(scale);
        transform.rotation = rotation;
    }
}

fn setHidden(ctx: *PhaseContext, comptime Tag: type) !void {
    var roots = try ctx.query(.{ Transform, Tag });
    defer roots.deinit();

    var it = roots.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.* = hiddenTransform();
    }
}

fn setOverlay(ctx: *PhaseContext, content: []const u8) !void {
    var overlay = try ctx.query(.{ Text, OverlayText });
    defer overlay.deinit();

    var it = overlay.iterator();
    while (it.next()) |row| {
        const text = row.get(Text) orelse continue;
        text.content = content;
    }
}

fn setOverlayText(overlay: Query(.{ Text, OverlayText }), content: []const u8) void {
    var overlay_it = overlay.iterator();
    while (overlay_it.next()) |row| {
        const text = row.get(Text) orelse continue;
        text.content = content;
    }
}

fn updateLoadingText(ctx: *PhaseContext, status: []const u8) !void {
    var status_query = try ctx.query(.{ Text, LoadingStatusText });
    defer status_query.deinit();
    var status_it = status_query.iterator();
    while (status_it.next()) |row| {
        const text = row.get(Text) orelse continue;
        text.content = status;
    }
}

fn setLoadingBar(ctx: *PhaseContext, visible: bool, progress01: f32) !void {
    var fill_query = try ctx.query(.{ Rectangle, Transform, LoadingBarFill });
    defer fill_query.deinit();
    var track_query = try ctx.query(.{ Transform, LoadingBarTrack });
    defer track_query.deinit();

    updateLoadingBarRows(fill_query, track_query, visible, progress01);
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

const loading_bar_width: f32 = 360.0;
const loading_bar_left: f32 = 220.0;

fn modelTransform(bounds: ImportedScene.Bounds) Transform {
    const scale = 1.8 / @max(bounds.maxDimension(), 0.001);
    const center = bounds.center();
    return Transform{
        .translation = .{ .x = -center.x * scale, .y = -center.y * scale, .z = -3.8 },
        .scale = Vec3.splat(scale),
    };
}

fn hiddenTransform() Transform {
    return Transform{
        .translation = .{ .x = 0.0, .y = 0.0, .z = -3.8 },
        .scale = Vec3.splat(0.0),
    };
}

// Imports
const std = @import("std");
const phasor = @import("phasor");

const AmbientLight = phasor.AmbientLight;
const App = phasor.App;
const AssetsLoadStage = phasor.AssetsLoadStage;
const AssetsLoadState = phasor.AssetsLoadState;
const AssetsModule = phasor.AssetsModule;
const AssetsModuleConfigured = phasor.AssetsModuleConfigured;
const AssetsProgressEvent = phasor.AssetsProgressEvent;
const Camera3d = phasor.Camera3d;
const CameraLayer = phasor.CameraLayer;
const ClearColor = phasor.ClearColor;
const Color = phasor.Color;
const Commands = phasor.Commands;
const ElapsedTime = phasor.ElapsedTime;
const EventReader = phasor.EventReader;
const ImportedScene = phasor.ImportedScene;
const Keyboard = phasor.Keyboard;
const Layer = phasor.Layer;
const Light = phasor.Light;
const MetricsModuleLayered = phasor.MetricsModuleLayered;
const PhaseContext = phasor.PhaseContext;
const PhasesModule = phasor.PhasesModule;
const Quat = phasor.Quat;
const Query = phasor.Query;
const Rectangle = phasor.Rectangle;
const Res = phasor.Res;
const ResMut = phasor.ResMut;
const ResOpt = phasor.ResOpt;
const Scene = phasor.Scene;
const Text = phasor.Text;
const Transform = phasor.Transform;
const Vec3 = phasor.Vec3;
const VSync = phasor.VSync;
const WindowSettings = phasor.WindowSettings;
