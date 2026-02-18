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
            .text_color = common.Color.WHITE,
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
        common.Transform{ .translation = .{ .x = 0.0, .y = 0.0, .z = -4.0 } },
        CubeRoot{},
    });

    const size: f32 = 1.6;
    const half = size * 0.5;
    try spawnFace(commands, cube_entity, quad, size, .{ .x = 0.0, .y = 0.0, .z = half }, common.Quat.identity(), common.Color.RED);
    try spawnFace(commands, cube_entity, quad, size, .{ .x = 0.0, .y = 0.0, .z = -half }, common.Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, std.math.pi), common.Color.BLUE);
    try spawnFace(commands, cube_entity, quad, size, .{ .x = half, .y = 0.0, .z = 0.0 }, common.Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, -std.math.pi / 2.0), common.Color.GREEN);
    try spawnFace(commands, cube_entity, quad, size, .{ .x = -half, .y = 0.0, .z = 0.0 }, common.Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, std.math.pi / 2.0), common.Color.ORANGE);
    try spawnFace(commands, cube_entity, quad, size, .{ .x = 0.0, .y = half, .z = 0.0 }, common.Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, std.math.pi / 2.0), common.Color.YELLOW);
    try spawnFace(commands, cube_entity, quad, size, .{ .x = 0.0, .y = -half, .z = 0.0 }, common.Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, -std.math.pi / 2.0), common.Color.PURPLE);

    try commands.insertResource(common.ClearColor{ .color = common.Color.DARKBLUE });
    _ = try commands.createEntity(.{
        common.Transform{},
        common.Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.0,
            .near = 0.1,
            .far = 100.0,
        } },
        render.CameraLayer(0){},
    });
    _ = try commands.createEntity(.{
        common.Transform{},
        common.Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        render.CameraLayer(1000){},
    });
}

fn spinCube(elapsed: Res(ElapsedTime), query: Query(.{ common.Transform, CubeRoot })) void {
    const t: f32 = @floatCast(elapsed.deref().seconds);
    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(common.Transform) orelse continue;
        const rot_x = common.Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, t * 0.7);
        const rot_y = common.Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, t * 1.1);
        transform.rotation = rot_y.mul(rot_x).normalize();
    }
}

fn spawnFace(
    commands: *ecs.Commands,
    cube_entity: u64,
    quad: render.MeshHandle,
    size: f32,
    translation: common.Vec3,
    rotation: common.Quat,
    color: common.Color,
) !void {
    _ = try commands.createEntity(.{
        common.Parent{ .id = cube_entity },
        common.LocalTransform{
            .translation = translation,
            .rotation = rotation,
            .scale = .{ .x = size, .y = size, .z = size },
        },
        common.Transform{},
        render.MeshInstance{ .mesh_handle = quad, .color = color },
        render.Layer(0){},
    });
}

// Imports
const std = @import("std");
