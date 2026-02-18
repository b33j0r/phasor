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
        try app.installModule(modules.TimeModule);
        try app.installModule(modules.ParentModule);
        try app.installModule(modules.RenderModule);
        try app.installModule(modules.MetricsModuleLayered(render.Layer(1000)){
            .font_size = 36.0,
            .text_color = Color.WHITE,
        });

        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("Update", spinCube);
    }
};

pub const main = platform.main(App);

fn setupScene(commands: *ecs.Commands) !void {
    const state = commands.getResourceMut(RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    var factory = render.MeshFactory.init(commands.allocator, mesh_library);
    const quad = try factory.quad(&state.renderer);

    const cube_entity = try commands.createEntity(.{
        Transform{ .translation = .{ .x = 0.0, .y = 0.0, .z = -4.0 } },
        CubeRoot{},
    });

    const size: f32 = 1.6;
    const half = size * 0.5;
    try spawnFace(commands, cube_entity, quad, size, .{ .x = 0.0, .y = 0.0, .z = half }, Quat.identity(), Color.RED);
    try spawnFace(commands, cube_entity, quad, size, .{ .x = 0.0, .y = 0.0, .z = -half }, Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, std.math.pi), Color.BLUE);
    try spawnFace(commands, cube_entity, quad, size, .{ .x = half, .y = 0.0, .z = 0.0 }, Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, -std.math.pi / 2.0), Color.GREEN);
    try spawnFace(commands, cube_entity, quad, size, .{ .x = -half, .y = 0.0, .z = 0.0 }, Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, std.math.pi / 2.0), Color.ORANGE);
    try spawnFace(commands, cube_entity, quad, size, .{ .x = 0.0, .y = half, .z = 0.0 }, Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, std.math.pi / 2.0), Color.YELLOW);
    try spawnFace(commands, cube_entity, quad, size, .{ .x = 0.0, .y = -half, .z = 0.0 }, Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, -std.math.pi / 2.0), Color.PURPLE);

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

fn spawnFace(
    commands: *ecs.Commands,
    cube_entity: u64,
    quad: render.MeshHandle,
    size: f32,
    translation: Vec3,
    rotation: Quat,
    color: Color,
) !void {
    _ = try commands.createEntity(.{
        Parent{ .id = cube_entity },
        LocalTransform{
            .translation = translation,
            .rotation = rotation,
            .scale = .{ .x = size, .y = size, .z = size },
        },
        Transform{},
        render.MeshInstance{ .mesh_handle = quad, .color = color },
        render.Layer(0){},
    });
}

// Imports
const std = @import("std");
const phasor = @import("phasor");

const ecs = phasor.ecs;
const modules = phasor.modules;
const render = phasor.renderer;
const common = phasor.common;
const platform = phasor.platform;

const RenderState = modules.RenderModule.RenderState;
const ElapsedTime = modules.TimeModule.ElapsedTime;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;

const Vec3 = common.Vec3;
const Quat = common.Quat;
const Color = common.Color;
const Parent = common.Parent;
const Transform = common.Transform;
const LocalTransform = common.LocalTransform;
const Camera3d = common.Camera3d;
const ClearColor = common.ClearColor;
const CameraLayer = render.CameraLayer;
