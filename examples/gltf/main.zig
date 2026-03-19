const builtin = @import("builtin");
const std = @import("std");
const phasor = @import("phasor");
const embedded_assets = @import("gltf_embedded_assets");

pub const std_options = phasor.common.logging.stdOptions(.debug);

const GltfPivot = struct {};
const SceneReady = struct {};
const SceneHydrated = struct {};
const DebugReported = struct {};

const App = struct {
    pub const options = platform.Options{
        .window = .{
            .title = "Phasor Lite - glTF",
            .width = 1280,
            .height = 900,
        },
    };

    pub fn configure(app: *ecs.App) !void {
        try platform.installDefaultModules(app);
        try app.installModule(modules.ParentModule);
        try app.installModule(modules.AssetsModule(Assets));
        try app.installModule(modules.MetricsModuleLayered(render.Layer(1000)){
            .font_size = 28.0,
            .text_color = Color.WHITE,
        });

        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("BeforeFrame", setupScene);
        try app.addSystemTo("Update", updatePivot);
        try app.addSystemTo("AfterFrame", debugSceneStatus);
        try app.addSystemTo("Shutdown", unloadImportedScene);
    }
};

pub const main = platform.main(App);

fn setupScene(
    commands: *ecs.Commands,
    build_ctx: ResOpt(render.BuildContext),
    assets_ctx: ResOpt(assets.AssetsContext),
    gltf_assets: ResMut(Assets),
) !void {
    if (commands.hasResource(SceneReady)) return;
    const scene_asset = &gltf_assets.ptr.flight_helmet;
    if (!commands.hasResource(SceneHydrated)) {
        try hydrateEmbeddedFlightHelmet(commands.allocator, scene_asset);
        try commands.insertResource(SceneHydrated{});
    }
    const build_ctx_res = build_ctx.ptr orelse return;
    const assets_ctx_res = assets_ctx.ptr orelse return;
    const scene_data = scene_asset.scene_data orelse return;

    try commands.insertResource(ClearColor{ .color = Color.rgb(10, 12, 18) });

    const pivot = try commands.createEntity(.{
        Transform{},
        GltfPivot{},
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
            .parent = pivot,
        },
    );
    try commands.insertResource(imported);
    try commands.insertResource(SceneReady{});

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
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(1000){},
    });
}

fn updatePivot(
    elapsed: Res(ElapsedTime),
    imported: ResOpt(assets.ImportedScene),
    query: Query(.{ Transform, GltfPivot }),
) void {
    const imported_scene = imported.ptr orelse return;
    const bounds = imported_scene.bounds;
    const center = bounds.center();
    const max_dim = @max(bounds.maxDimension(), 0.001);
    const scale = 1.8 / max_dim;
    const t: f32 = @floatCast(elapsed.ptr.seconds);

    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.translation = .{
            .x = -center.x * scale,
            .y = -center.y * scale,
            .z = -3.8,
        };
        transform.scale = Vec3.splat(scale);
        transform.rotation = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, t * 0.6);
    }
}

fn unloadImportedScene(commands: *ecs.Commands) void {
    _ = commands.removeResource(assets.ImportedScene);
    _ = commands.removeResource(SceneReady);
    _ = commands.removeResource(SceneHydrated);
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
    std.log.debug(
        "scene ready: mesh_entities={} queue_items={} imported_meshes={} imported_materials={}",
        .{
            mesh_count,
            queue.ptr.items.items.len,
            imported_scene.mesh_handles.len,
            imported_scene.material_handles.len,
        },
    );
    try commands.insertResource(DebugReported{});
}

const Assets = struct {
    flight_helmet: assets.Scene = .embedded(embedded_assets.flight_helmet_gltf),
};

fn hydrateEmbeddedFlightHelmet(allocator: std.mem.Allocator, scene_asset: *assets.Scene) !void {
    const scene_data = if (scene_asset.scene_data) |*data| data else return;

    for (scene_data.buffers) |*buffer| {
        if (buffer.bytes != null) continue;
        const uri = buffer.uri orelse continue;
        if (std.mem.eql(u8, uri, "FlightHelmet.bin")) {
            buffer.bytes = try allocator.dupe(u8, embedded_assets.flight_helmet_bin);
        }
    }

    for (scene_data.images) |*image| {
        if (image.bytes != null) continue;
        const uri = image.uri orelse continue;
        image.bytes = try allocator.dupe(u8, embeddedFlightHelmetImage(uri) orelse continue);
    }
}

fn embeddedFlightHelmetImage(uri: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, uri, "FlightHelmet_Materials_GlassPlasticMat_BaseColor.png")) {
        return embedded_assets.glass_plastic_base_color;
    }
    if (std.mem.eql(u8, uri, "FlightHelmet_Materials_LeatherPartsMat_BaseColor.png")) {
        return embedded_assets.leather_parts_base_color;
    }
    if (std.mem.eql(u8, uri, "FlightHelmet_Materials_LensesMat_BaseColor.png")) {
        return embedded_assets.lenses_base_color;
    }
    if (std.mem.eql(u8, uri, "FlightHelmet_Materials_MetalPartsMat_BaseColor.png")) {
        return embedded_assets.metal_parts_base_color;
    }
    if (std.mem.eql(u8, uri, "FlightHelmet_Materials_RubberWoodMat_BaseColor.png")) {
        return embedded_assets.rubber_wood_base_color;
    }
    return null;
}

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
const ClearColor = common.ClearColor;
const Color = common.Color;
const Quat = common.Quat;
const Transform = common.Transform;
const Vec3 = common.Vec3;
const CameraLayer = render.CameraLayer;
