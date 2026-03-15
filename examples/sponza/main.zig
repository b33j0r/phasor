const std = @import("std");
const phasor = @import("phasor");

pub const std_options = phasor.common.logging.stdOptions(.debug);

const SceneReady = struct {};
const SceneRoot = struct {};
const SceneCamera = struct {};
const DebugReported = struct {};

const sponza_scene_path = "local/cache/sponza/source/Models/Sponza/glTF/Sponza.gltf";

const App = struct {
    pub const options = platform.Options{
        .window = .{
            .title = "Phasor Lite - Sponza",
            .width = 1440,
            .height = 900,
        },
    };

    pub fn configure(app: *ecs.App) !void {
        try platform.installDefaultModules(app);
        try app.installModule(modules.AssetsModule(Assets));
        try app.installModule(modules.MetricsModuleLayered(render.Layer(1000)){
            .font_size = 28.0,
            .text_color = Color.WHITE,
        });

        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("BeforeFrame", setupScene);
        try app.addSystemTo("Update", updatePresentation);
        try app.addSystemTo("AfterFrame", debugSceneStatus);
        try app.addSystemTo("Shutdown", unloadImportedScene);
    }
};

pub const main = platform.main(App);

fn setupScene(
    commands: *ecs.Commands,
    build_ctx: ResOpt(render.BuildContext),
    assets_ctx: ResOpt(assets.AssetsContext),
    scene_assets: ResMut(Assets),
) !void {
    if (commands.hasResource(SceneReady)) return;

    const build_ctx_res = build_ctx.ptr orelse return;
    const assets_ctx_res = assets_ctx.ptr orelse return;
    const scene_asset = &scene_assets.ptr.sponza;
    const scene_data = scene_asset.scene_data orelse return;

    try commands.insertResource(ClearColor{ .color = Color.rgb(8, 10, 14) });

    const root = try commands.createEntity(.{
        Transform{},
        SceneRoot{},
        render.Layer(0){},
    });

    const imported = try assets.ImportedScene.instantiate(
        commands.allocator,
        assets_ctx_res.io,
        commands,
        build_ctx_res,
        scene_asset.resolved_path,
        &scene_data,
        .{
            .parent = root,
        },
    );
    try commands.insertResource(imported);
    try commands.insertResource(SceneReady{});

    _ = try commands.createEntity(.{
        Transform{},
        SceneCamera{},
        Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.0,
            .near = 0.1,
            .far = 500.0,
        } },
        CameraLayer(0){},
    });

    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(1000){},
    });
}

fn updatePresentation(
    elapsed: Res(ElapsedTime),
    imported: ResOpt(assets.ImportedScene),
    roots: Query(.{ Transform, SceneRoot }),
    cameras: Query(.{ Transform, SceneCamera }),
) void {
    const imported_scene = imported.ptr orelse return;
    if (!imported_scene.bounds.valid) return;

    const bounds = imported_scene.bounds;
    const center = bounds.center();
    const size = bounds.size();
    const horizontal_span = @max(size.x, size.z);
    const t: f32 = @floatCast(elapsed.ptr.seconds);

    var root_it = roots.iterator();
    while (root_it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.translation = .{
            .x = -center.x,
            .y = -bounds.min.y,
            .z = -center.z,
        };
        transform.rotation = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, t * 0.08);
        transform.scale = Vec3.splat(1.0);
    }

    var camera_it = cameras.iterator();
    while (camera_it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.translation = .{
            .x = 0.0,
            .y = @max(size.y * 0.26, 7.0),
            .z = horizontal_span * 0.85 + 12.0,
        };
        transform.rotation = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, -0.24);
    }
}

fn unloadImportedScene(commands: *ecs.Commands) void {
    _ = commands.removeResource(assets.ImportedScene);
    _ = commands.removeResource(SceneReady);
    _ = commands.removeResource(DebugReported);
}

fn debugSceneStatus(
    commands: *ecs.Commands,
    imported: ResOpt(assets.ImportedScene),
    queue: Res(render.RenderQueue),
    meshes: Query(.{render.MeshInstance}),
) !void {
    if (!commands.hasResource(SceneReady)) return;
    if (commands.hasResource(DebugReported)) return;

    var mesh_count: usize = 0;
    var it = meshes.iterator();
    while (it.next()) |_| {
        mesh_count += 1;
    }

    const imported_scene = imported.ptr orelse return;
    std.log.info(
        "sponza ready: mesh_entities={} queue_items={} imported_meshes={} imported_materials={} bounds=({d:.2}, {d:.2}, {d:.2})",
        .{
            mesh_count,
            queue.ptr.items.items.len,
            imported_scene.mesh_handles.len,
            imported_scene.material_handles.len,
            imported_scene.bounds.size().x,
            imported_scene.bounds.size().y,
            imported_scene.bounds.size().z,
        },
    );
    try commands.insertResource(DebugReported{});
}

const Assets = struct {
    sponza: assets.Scene = .file(sponza_scene_path),
};

const ecs = phasor.ecs;
const assets = phasor.assets;
const common = phasor.common;
const modules = phasor.modules;
const platform = phasor.platform;
const render = phasor.renderer;

const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;
const ElapsedTime = modules.TimeModule.ElapsedTime;

const Camera3d = common.Camera3d;
const CameraLayer = render.CameraLayer;
const ClearColor = common.ClearColor;
const Color = common.Color;
const Quat = common.Quat;
const Transform = common.Transform;
const Vec3 = common.Vec3;
