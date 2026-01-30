const Ball = struct {
    radius: f32,
};

const Velocity = struct {
    v: common.Vec2 = .{},
};

const SceneReady = struct {};

const Bounds = struct {
    width: f32,
    height: f32,
};

const Runner = if (is_wasm)
    struct {
        app: ecs.App,
        io: std.Io,
    }
else
    struct {
        app: ecs.App,
        io_threaded: std.Io.Threaded,
        io: std.Io,
    };

fn nativeMain(init: std.process.Init) !u8 {
    const allocator = std.heap.c_allocator;

    var app = try ecs.App.init(allocator, &init.io);
    defer app.deinit();

    try configureApp(&app);

    return try app.run();
}

fn wasmMain() u8 {
    return 0;
}

pub const main = if (is_wasm) wasmMain else nativeMain;

pub export fn wasmCreate() u32 {
    if (!is_wasm) return 0;

    const allocator = std.heap.page_allocator;
    const runner = allocator.create(Runner) catch return 0;
    errdefer allocator.destroy(runner);

    runner.io = wasm.io();
    runner.app = ecs.App.init(allocator, &runner.io) catch return 0;
    errdefer runner.app.deinit();

    configureApp(&runner.app) catch return 0;
    runner.app.start() catch return 0;

    return @intCast(@intFromPtr(runner));
}

pub export fn wasmFrame(handle: u32) void {
    if (!is_wasm) return;
    if (handle == 0) return;

    const runner: *Runner = @ptrFromInt(handle);
    _ = runner.app.step() catch {};
}

pub export fn wasmDeinit(handle: u32) void {
    if (!is_wasm) return;
    if (handle == 0) return;

    const allocator = std.heap.page_allocator;
    const runner: *Runner = @ptrFromInt(handle);
    runner.app.deinit();
    allocator.destroy(runner);
}

fn configureApp(app: *ecs.App) !void {
    if (!is_wasm) {
        var commands = ecs.Commands.init(app.allocator, app.io, &app.world);
        defer commands.deinit();
        try commands.insertResource(window.WindowSettings{
            .title = "Phasor Lite - Bouncing Ball",
            .width = 800,
            .height = 600,
        });
        if (!commands.isEmpty()) {
            try commands.apply();
        }
        try app.installModule(window.WindowModule);
    }

    try app.installModule(modules.TimeModule);
    try app.installModule(modules.RenderModule);
    try app.installModule(modules.MetricsModule{ .font_size = 60.0 });

    try app.addSystemTo(ecs.schedule.DefaultSchedule.Startup, setupSurface);
    try app.addSystemTo(ecs.schedule.DefaultSchedule.BeforeFrame, setupScene);
    try app.addSystemTo(ecs.schedule.DefaultSchedule.Update, integrateMotion);
    try app.addSystemTo(ecs.schedule.DefaultSchedule.Update, bounceBall);
}

fn setupSurface(commands: *ecs.Commands) !void {
    if (commands.hasResource(RenderSurface)) return;

    if (is_wasm) {
        const surface = render.surface_canvas.fromCanvasId("#canvas");
        try commands.insertResource(RenderSurface{ .target = surface });
        return;
    }

    const window_res = commands.getResource(window.Window) orelse return error.MissingWindow;
    const handle = window_res.handle orelse return error.MissingWindow;
    const surface = try render.surface_glfw.fromGlfwWindow(handle);
    try commands.insertResource(RenderSurface{ .target = surface });
}

fn setupScene(
    commands: *ecs.Commands,
    viewport_opt: ResOpt(ViewportSize),
    window_bounds_opt: ResOpt(common.WindowBounds),
    render_bounds_opt: ResOpt(common.RenderBounds),
    render_state_opt: ResOpt(RenderState),
) !void {
    if (commands.hasResource(SceneReady)) return;

    const state = commands.getResourceMut(RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    const bounds = resolveBounds(viewport_opt, window_bounds_opt, render_bounds_opt, render_state_opt) orelse return;

    const radius: f32 = 40.0;
    var factory = render.MeshFactory.init(commands.allocator, mesh_library);
    const mesh_handle = try factory.circle(&state.renderer, radius, 48);

    const start = common.Vec3{ .x = bounds.width * 0.5, .y = bounds.height * 0.5, .z = -10.0 };
    _ = try commands.createEntity(.{
        Ball{ .radius = radius },
        Velocity{ .v = .{ .x = 220.0, .y = 160.0 } },
        common.Transform{ .translation = start },
        render.MeshInstance{ .mesh_handle = mesh_handle, .color = common.Color.RED },
    });

    try commands.insertResource(common.ClearColor{ .color = common.Color.WHITE });
    try commands.insertResource(common.Camera3d{ .Viewport = .{ .mode = .TopLeft } });
    try commands.insertResource(SceneReady{});
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
const std = @import("std");
const builtin = @import("builtin");
const phasor = @import("phasor");

const is_wasm = builtin.target.cpu.arch.isWasm();
const wasm = if (is_wasm) @import("wasm") else struct {
    pub fn io() std.Io {
        return undefined;
    }
};

const ecs = phasor.ecs;
const modules = phasor.modules;
const render = phasor.renderer;
const common = phasor.common;
const window = if (is_wasm) struct {} else phasor.window;

const RenderSurface = modules.RenderModule.RenderSurface;
const RenderState = modules.RenderModule.RenderState;
const ViewportSize = modules.RenderModule.ViewportSize;
const DeltaTime = modules.TimeModule.DeltaTime;
const system_params = ecs.system_params;
const Query = system_params.Query;
const Res = system_params.Res;
const ResOpt = system_params.ResOpt;
