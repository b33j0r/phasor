const Ball = struct {
    radius: f32,
};

const Velocity = struct {
    v: Vec2 = .{},
};

const DecalSpinTag = struct {};
const decal_spin_speed: f32 = 2.5;
const decal_centroid_offset = Vec3{
    // favicon.png alpha centroid (~47.49,56.20) in a 96x96 image -> ~8.70px below center.
    .x = 0.0,
    .y = 8.7043 * (60.0 / 96.0),
    .z = 0.0,
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
            .title = "Phasor - Bouncing Ball",
            .width = 800,
            .height = 600,
        },
    };

    pub fn configure(app: *ecs.App) !void {
        try platform.installDefaultModules(app);
        try app.installModule(modules.ParentModule);
        try app.installModule(modules.AssetsModule(Assets));
        try app.installModule(modules.MetricsModule{ .font_size = 24.0 });

        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("Update", integrateMotion);
        try app.addSystemTo("Update", bounceBall);
        try app.addSystemTo("Update", spinDecalLocal);
    }
};

pub const main = platform.main(App);

fn setupScene(
    commands: *ecs.Commands,
    viewport_opt: ResOpt(ViewportSize),
    window_bounds_opt: ResOpt(WindowBounds),
    render_bounds_opt: ResOpt(RenderBounds),
    render_state_opt: ResOpt(RenderState),
    build_ctx: ResMut(render.BuildContext),
    assets_res: Res(Assets),
) !void {
    var decal_material: ?Material = null;
    decal_material = assets_res.ptr.favicon.material;
    const bounds = resolveBounds(viewport_opt, window_bounds_opt, render_bounds_opt, render_state_opt) orelse return;

    const radius: f32 = 40.0;
    const inset_radius: f32 = 34.0;
    var factory = build_ctx.ptr.meshFactory();
    const outer_mesh = try factory.circle(radius, 48);
    const inner_mesh = try factory.circle(inset_radius, 48);

    const start = Vec3{ .x = bounds.width * 0.5, .y = bounds.height * 0.5, .z = -10.0 };
    const ball_entity = try commands.createEntity(.{
        Ball{ .radius = radius },
        Velocity{ .v = .{ .x = 220.0, .y = 160.0 } },
        Transform{ .translation = start },
        MeshInstance{ .mesh_handle = outer_mesh, .color = Color.BLACK },
    });

    _ = try commands.createEntity(.{
        Parent{ .id = ball_entity },
        LocalTransform{
            .translation = .{ .x = 0.0, .y = 0.0, .z = 0.5 },
        },
        Transform{},
        MeshInstance{ .mesh_handle = inner_mesh, .color = Color.WHITE },
    });

    if (decal_material) |material| {
        const decal_size: f32 = 60.0;
        _ = try commands.createEntity(.{
            Parent{ .id = ball_entity },
            LocalTransform{
                .translation = .{ .x = 0.0, .y = 0.0, .z = 1.0 },
            },
            Transform{},
            Sprite{
                .color = Color.WHITE,
                .size_mode = .{ .Manual = .{ .width = decal_size, .height = decal_size } },
            },
            MeshInstance{ .material = material },
            DecalSpinTag{},
        });
    }

    try commands.insertResource(ClearColor{ .color = Color.WHITE });
    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(0){},
    });
}

fn spinDecalLocal(elapsed: Res(ElapsedTime), query: Query(.{ LocalTransform, DecalSpinTag })) void {
    const t: f32 = @floatCast(elapsed.deref().seconds);
    var it = query.iterator();
    while (it.next()) |row| {
        const local = row.get(LocalTransform) orelse continue;
        const rotation = Quat.fromAxisAngle(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, t * decal_spin_speed);
        const rotated_offset = rotation.rotateVec3(decal_centroid_offset);
        local.rotation = rotation;
        local.translation.x = -rotated_offset.x;
        local.translation.y = -rotated_offset.y;
        local.translation.z = 1.0;
    }
}

fn integrateMotion(dt: Res(DeltaTime), query: Query(.{ Transform, Velocity })) void {
    const step: f32 = @floatCast(dt.deref().seconds);
    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const velocity = row.get(Velocity) orelse continue;
        transform.translation.x += velocity.v.x * step;
        transform.translation.y += velocity.v.y * step;
    }
}

fn bounceBall(
    viewport_opt: ResOpt(ViewportSize),
    window_bounds_opt: ResOpt(WindowBounds),
    render_bounds_opt: ResOpt(RenderBounds),
    render_state_opt: ResOpt(RenderState),
    query: Query(.{ Transform, Velocity, Ball }),
) void {
    const bounds = resolveBounds(viewport_opt, window_bounds_opt, render_bounds_opt, render_state_opt) orelse return;

    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
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
    window_bounds_opt: ResOpt(WindowBounds),
    render_bounds_opt: ResOpt(RenderBounds),
    render_state_opt: ResOpt(RenderState),
) ?Bounds {
    // Gameplay uses logical viewport size so larger windows reveal more world without changing sprite scale.
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
const ElapsedTime = modules.TimeModule.ElapsedTime;
const system_params = ecs.system_params;
const Query = system_params.Query;
const Res = system_params.Res;
const ResMut = system_params.ResMut;
const ResOpt = system_params.ResOpt;

const Vec2 = common.Vec2;
const Vec3 = common.Vec3;
const Quat = common.Quat;
const Color = common.Color;
const Parent = common.Parent;
const Transform = common.Transform;
const LocalTransform = common.LocalTransform;
const Camera3d = common.Camera3d;
const WindowBounds = common.WindowBounds;
const RenderBounds = common.RenderBounds;
const ClearColor = common.ClearColor;

const Material = render.Material;
const MeshInstance = render.MeshInstance;
const Sprite = render.Sprite;
const CameraLayer = render.CameraLayer;
