const phasor = @import("phasor");

const ecs = phasor.ecs;
const modules = phasor.modules;
const render = phasor.renderer;
const common = phasor.common;
const platform = phasor.platform;

const RenderState = modules.RenderModule.RenderState;
const DeltaTime = modules.TimeModule.DeltaTime;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;

const Rotator = struct {
    angle_x: f32 = 0.0,
    angle_y: f32 = 0.0,
};

const Face = struct {
    translation: common.Vec3,
    rotation: common.Quat,
    color: common.Color,
};

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
        Rotator{},
    });

    const size: f32 = 1.6;
    const half = size * 0.5;
    const faces = [_]Face{
        .{
            .translation = .{ .x = 0.0, .y = 0.0, .z = half },
            .rotation = common.Quat.identity(),
            .color = common.Color.RED,
        },
        .{
            .translation = .{ .x = 0.0, .y = 0.0, .z = -half },
            .rotation = common.Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, std.math.pi),
            .color = common.Color.BLUE,
        },
        .{
            .translation = .{ .x = half, .y = 0.0, .z = 0.0 },
            .rotation = common.Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, -std.math.pi / 2.0),
            .color = common.Color.GREEN,
        },
        .{
            .translation = .{ .x = -half, .y = 0.0, .z = 0.0 },
            .rotation = common.Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, std.math.pi / 2.0),
            .color = common.Color.ORANGE,
        },
        .{
            .translation = .{ .x = 0.0, .y = half, .z = 0.0 },
            .rotation = common.Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, std.math.pi / 2.0),
            .color = common.Color.YELLOW,
        },
        .{
            .translation = .{ .x = 0.0, .y = -half, .z = 0.0 },
            .rotation = common.Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, -std.math.pi / 2.0),
            .color = common.Color.PURPLE,
        },
    };

    for (faces) |face| {
        _ = try commands.createEntity(.{
            common.Parent{ .id = cube_entity },
            common.LocalTransform{
                .translation = face.translation,
                .rotation = face.rotation,
                .scale = .{ .x = size, .y = size, .z = size },
            },
            common.Transform{},
            render.MeshInstance{ .mesh_handle = quad, .color = face.color },
            render.Layer(0){},
        });
    }

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

fn spinCube(dt: Res(DeltaTime), query: Query(.{ common.Transform, Rotator })) void {
    const step: f32 = @floatCast(dt.deref().seconds);
    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(common.Transform) orelse continue;
        const rotator = row.get(Rotator) orelse continue;

        rotator.angle_x += step * 0.7;
        rotator.angle_y += step * 1.1;

        const rot_x = common.Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, rotator.angle_x);
        const rot_y = common.Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, rotator.angle_y);
        transform.rotation = rot_y.mul(rot_x).normalize();
    }
}

// Imports
const std = @import("std");
