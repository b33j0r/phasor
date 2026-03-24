const CubeRoot = struct {};

const App = struct {
    pub const options = platform.Options{
        .window = .{
            .title = "Phasor Lite - Cube",
            .width = 900,
            .height = 700,
        },
    };

    pub fn configure(app: *ecs.App) !void {
        try platform.installDefaultModules(app);
        try app.installModule(modules.ParentModule);
        try app.installModule(modules.AssetsModule(Assets));
        try app.installModule(modules.MetricsModuleLayered(render.Layer(1000)){
            .font_size = 36.0,
            .text_color = Color.WHITE,
        });

        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("Update", spinCube);
    }
};

pub const main = platform.main(App);

fn setupScene(
    commands: *ecs.Commands,
    build_ctx: ResMut(render.BuildContext),
    cube_assets: Res(Assets),
    core_shaders: ResMut(render.CoreShaders),
) !void {
    const assets_ptr = cube_assets.ptr;
    try build_ctx.ptr.ensureCoreColorPos3Color4Shader(&core_shaders.ptr.color_pos3_color4);
    if (!assets_ptr.cube_mesh.handle.isValid()) return error.CubeMeshMissing;
    if (!core_shaders.ptr.color_pos3_color4.isValid()) return error.CoreColorShaderMissing;

    _ = try commands.createEntity(.{
        Transform{ .translation = .{ .x = 0.0, .y = 0.0, .z = -4.0 } },
        CubeRoot{},
        render.MeshInstance{
            .mesh_handle = assets_ptr.cube_mesh.handle,
            .color = Color.WHITE,
            .material = render.Material.withShader(core_shaders.ptr.color_pos3_color4),
        },
        render.Layer(0){},
    });

    try commands.insertResource(ClearColor{ .color = Color.DARKBLUE });
    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.0,
            .near = 0.1,
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

fn spinCube(elapsed: Res(ElapsedTime), query: Query(.{ Transform, CubeRoot })) void {
    const t: f32 = @floatCast(elapsed.deref().seconds);
    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const rot_x = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, t * 0.7);
        const rot_y = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, t * 1.1);
        transform.rotation = rot_y.mul(rot_x).normalize();
    }
}

const Assets = struct {
    cube_mesh: assets.Mesh = .{
        .pos3_color_vertices = cube_vertices[0..],
        .indices = cube_indices[0..],
    },
};

const cube_vertices = [_]render.VertexPos3Color{
    .{ .position = .{ -1.0, -1.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, -1.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, 1.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .position = .{ -1.0, 1.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },

    .{ .position = .{ 1.0, -1.0, -1.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
    .{ .position = .{ -1.0, -1.0, -1.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
    .{ .position = .{ -1.0, 1.0, -1.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
    .{ .position = .{ 1.0, 1.0, -1.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },

    .{ .position = .{ 1.0, -1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, -1.0, -1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, 1.0, -1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, 1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },

    .{ .position = .{ -1.0, -1.0, -1.0 }, .color = .{ 1.0, 0.5, 0.0, 1.0 } },
    .{ .position = .{ -1.0, -1.0, 1.0 }, .color = .{ 1.0, 0.5, 0.0, 1.0 } },
    .{ .position = .{ -1.0, 1.0, 1.0 }, .color = .{ 1.0, 0.5, 0.0, 1.0 } },
    .{ .position = .{ -1.0, 1.0, -1.0 }, .color = .{ 1.0, 0.5, 0.0, 1.0 } },

    .{ .position = .{ -1.0, 1.0, 1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, 1.0, 1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ 1.0, 1.0, -1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ -1.0, 1.0, -1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },

    .{ .position = .{ -1.0, -1.0, -1.0 }, .color = .{ 0.6, 0.2, 0.8, 1.0 } },
    .{ .position = .{ 1.0, -1.0, -1.0 }, .color = .{ 0.6, 0.2, 0.8, 1.0 } },
    .{ .position = .{ 1.0, -1.0, 1.0 }, .color = .{ 0.6, 0.2, 0.8, 1.0 } },
    .{ .position = .{ -1.0, -1.0, 1.0 }, .color = .{ 0.6, 0.2, 0.8, 1.0 } },
};

const cube_indices = [_]u16{
    0,  1,  2,  0,  2,  3,
    4,  5,  6,  4,  6,  7,
    8,  9,  10, 8,  10, 11,
    12, 13, 14, 12, 14, 15,
    16, 17, 18, 16, 18, 19,
    20, 21, 22, 20, 22, 23,
};

// Imports
const std = @import("std");
const phasor = @import("phasor");

const ecs = phasor.ecs;
const modules = phasor.modules;
const render = phasor.renderer;
const common = phasor.common;
const platform = phasor.platform;
const assets = phasor.assets;

const ElapsedTime = modules.TimeModule.ElapsedTime;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;

const Quat = common.Quat;
const Color = common.Color;
const Transform = common.Transform;
const Camera3d = common.Camera3d;
const ClearColor = common.ClearColor;
const CameraLayer = render.CameraLayer;
