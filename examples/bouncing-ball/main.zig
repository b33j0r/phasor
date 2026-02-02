const Ball = struct {
    radius: f32,
};

const Velocity = struct {
    v: common.Vec2 = .{},
};

const Bounds = struct {
    width: f32,
    height: f32,
};

const Assets = struct {
    favicon: assets.Texture = .{
        .data = @embedFile("assets/textures/favicon.png"),
    },
};

const App = struct {
    pub const options = platform.Options{
        .window = .{
            .title = "Phasor Lite - Bouncing Ball",
            .width = 800,
            .height = 600,
        },
    };

    pub fn configure(app: *ecs.App) !void {
        try app.installModule(modules.TimeModule);
        try app.installModule(modules.ParentModule);
        try app.installModule(modules.RenderModule);
        try app.installModule(modules.AssetsModule(Assets));
        try app.installModule(modules.MetricsModule{ .font_size = 60.0 });

        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("Update", integrateMotion);
        try app.addSystemTo("Update", bounceBall);
    }
};

pub const main = platform.main(App);

fn setupScene(
    commands: *ecs.Commands,
    viewport_opt: ResOpt(ViewportSize),
    window_bounds_opt: ResOpt(common.WindowBounds),
    render_bounds_opt: ResOpt(common.RenderBounds),
    render_state_opt: ResOpt(RenderState),
) !void {
    const state = commands.getResourceMut(RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    var decal_material: ?render.Material = null;
    if (commands.getResource(Assets)) |asset_data| {
        decal_material = asset_data.favicon.material;
    }
    const bounds = resolveBounds(viewport_opt, window_bounds_opt, render_bounds_opt, render_state_opt) orelse return;

    const radius: f32 = 40.0;
    var factory = render.MeshFactory.init(commands.allocator, mesh_library);
    const mesh_handle = try factory.circle(&state.renderer, radius, 48);

    const start = common.Vec3{ .x = bounds.width * 0.5, .y = bounds.height * 0.5, .z = -10.0 };
    const ball_entity = try commands.createEntity(.{
        Ball{ .radius = radius },
        Velocity{ .v = .{ .x = 220.0, .y = 160.0 } },
        common.Transform{ .translation = start },
        render.MeshInstance{ .mesh_handle = mesh_handle, .color = common.Color.RED },
    });

    if (decal_material) |material| {
        const decal_size: f32 = 60.0;
        _ = try commands.createEntity(.{
            common.Parent{ .id = ball_entity },
            common.LocalTransform{
                .translation = .{ .x = 0.0, .y = 0.0, .z = 1.0 },
            },
            common.Transform{},
            render.Sprite{
                .color = common.Color.WHITE,
                .size_mode = .{ .Manual = .{ .width = decal_size, .height = decal_size } },
            },
            render.MaterialInstance{ .material = material },
        });
    }

    try commands.insertResource(common.ClearColor{ .color = common.Color.WHITE });
    _ = try commands.createEntity(.{
        common.Transform{},
        common.Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        render.CameraLayer(0){},
    });
}

fn integrateMotion(dt: Res(DeltaTime), query: Query(.{ common.Transform, Velocity })) void {
    const step: f32 = @floatCast(dt.deref().seconds);
    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(common.Transform) orelse continue;
        const velocity = row.get(Velocity) orelse continue;
        transform.translation.x += velocity.v.x * step;
        transform.translation.y += velocity.v.y * step;
    }
}

fn bounceBall(
    viewport_opt: ResOpt(ViewportSize),
    window_bounds_opt: ResOpt(common.WindowBounds),
    render_bounds_opt: ResOpt(common.RenderBounds),
    render_state_opt: ResOpt(RenderState),
    query: Query(.{ common.Transform, Velocity, Ball }),
) void {
    const bounds = resolveBounds(viewport_opt, window_bounds_opt, render_bounds_opt, render_state_opt) orelse return;

    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(common.Transform) orelse continue;
        const velocity = row.get(Velocity) orelse continue;
        const ball = row.get(Ball) orelse continue;
        const radius = ball.radius;

        if (transform.translation.x - radius < 0.0) {
            transform.translation.x = radius;
            velocity.v.x *= -1.0;
        } else if (transform.translation.x + radius > bounds.width) {
            transform.translation.x = bounds.width - radius;
            velocity.v.x *= -1.0;
        }

        if (transform.translation.y - radius < 0.0) {
            transform.translation.y = radius;
            velocity.v.y *= -1.0;
        } else if (transform.translation.y + radius > bounds.height) {
            transform.translation.y = bounds.height - radius;
            velocity.v.y *= -1.0;
        }
    }
}

fn resolveBounds(
    viewport_opt: ResOpt(ViewportSize),
    window_bounds_opt: ResOpt(common.WindowBounds),
    render_bounds_opt: ResOpt(common.RenderBounds),
    render_state_opt: ResOpt(RenderState),
) ?Bounds {
    if (viewport_opt.ptr) |vp| {
        return .{ .width = vp.width, .height = vp.height };
    }
    if (window_bounds_opt.ptr) |bounds| {
        return .{
            .width = @floatFromInt(bounds.width),
            .height = @floatFromInt(bounds.height),
        };
    }
    if (render_bounds_opt.ptr) |bounds| {
        return .{ .width = bounds.width, .height = bounds.height };
    }
    if (render_state_opt.ptr) |state| {
        const size = state.surface.size();
        return .{
            .width = @floatFromInt(size.width),
            .height = @floatFromInt(size.height),
        };
    }
    return null;
}

// Imports
const phasor = @import("phasor");

const ecs = phasor.ecs;
const modules = phasor.modules;
const render = phasor.renderer;
const assets = phasor.assets;
const common = phasor.common;
const platform = phasor.platform;

const RenderState = modules.RenderModule.RenderState;
const ViewportSize = modules.RenderModule.ViewportSize;
const DeltaTime = modules.TimeModule.DeltaTime;
const system_params = ecs.system_params;
const Query = system_params.Query;
const Res = system_params.Res;
const ResOpt = system_params.ResOpt;
