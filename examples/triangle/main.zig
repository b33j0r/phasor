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
const window = if (builtin.target.cpu.arch.isWasm()) struct {} else phasor.window;

const RenderSurface = modules.RenderModule.RenderSurface;
const RenderState = modules.RenderModule.RenderState;

const SceneReady = struct {};

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
    runner.app = ecs.App.init(allocator, &runner.io) catch {
        return 0;
    };
    errdefer runner.app.deinit();

    configureApp(&runner.app) catch {
        return 0;
    };
    runner.app.start() catch {
        return 0;
    };

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
    if (!builtin.target.cpu.arch.isWasm()) {
        try app.installModule(window.WindowModule);
    }
    try app.installModule(modules.RenderModule);

    try app.addSystemTo(ecs.schedule.DefaultSchedule.Startup, setupSurface);
    try app.addSystemTo(ecs.schedule.DefaultSchedule.BeforeFrame, setupScene);
}

fn setupSurface(commands: *ecs.Commands) !void {
    if (commands.hasResource(RenderSurface)) return;

    if (builtin.target.cpu.arch.isWasm()) {
        const surface = render.surface_canvas.fromCanvasId("#canvas");
        try commands.insertResource(RenderSurface{ .target = surface });
        return;
    }

    const window_res = commands.getResource(window.Window) orelse return error.MissingWindow;
    const handle = window_res.handle orelse return error.MissingWindow;
    const surface = try render.surface_glfw.fromGlfwWindow(handle);
    try commands.insertResource(RenderSurface{ .target = surface });
}

fn setupScene(commands: *ecs.Commands) !void {
    if (commands.hasResource(SceneReady)) return;

    _ = try commands.createEntity(.{
        render.Triangle{
            .vertices = .{
                .{ .position = .{ 0.0, 160.0 }, .color = .{ 1.0, 0.2, 0.2 } },
                .{ .position = .{ -160.0, -140.0 }, .color = .{ 0.2, 1.0, 0.2 } },
                .{ .position = .{ 160.0, -140.0 }, .color = .{ 0.2, 0.4, 1.0 } },
            },
        },
    });

    try commands.insertResource(common.ClearColor{ .color = common.Color.BLACK });
    try commands.insertResource(common.Camera3d{ .Viewport = .{ .mode = .Center } });
    try commands.insertResource(SceneReady{});
}
