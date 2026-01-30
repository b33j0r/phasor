const std = @import("std");
const builtin = @import("builtin");
const phasor = @import("phasor");

const ecs = phasor.ecs;
const modules = phasor.modules;
const render = phasor.renderer;
const common = phasor.common;
const window = if (builtin.target.cpu.arch.isWasm()) struct {} else phasor.window;

const RenderSurface = modules.RenderModule.RenderSurface;
const RenderState = modules.RenderModule.RenderState;

const SceneReady = struct {};

var g_app: ?ecs.App = null;
var g_io_threaded: ?std.Io.Threaded = null;
var g_io: ?std.Io = null;

pub fn main(init: std.process.Init) !u8 {
    const allocator = std.heap.c_allocator;

    var app = try ecs.App.init(allocator, &init.io);
    defer app.deinit();

    try configureApp(&app);

    return try app.run();
}

pub export fn wasmInit() void {
    if (!builtin.target.cpu.arch.isWasm()) return;
    if (g_app != null) return;

    const allocator = std.heap.page_allocator;
    g_io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty }) catch return;
    g_io = g_io_threaded.?.io();
    var app = ecs.App.init(allocator, &g_io.?) catch {
        g_io_threaded.?.deinit();
        g_io_threaded = null;
        g_io = null;
        return;
    };
    errdefer app.deinit();

    configureApp(&app) catch {
        app.deinit();
        g_io_threaded.?.deinit();
        g_io_threaded = null;
        g_io = null;
        return;
    };

    app.start() catch {
        app.deinit();
        g_io_threaded.?.deinit();
        g_io_threaded = null;
        g_io = null;
        return;
    };

    g_app = app;
}

pub export fn wasmFrame() void {
    if (!builtin.target.cpu.arch.isWasm()) return;
    if (g_app) |*app| {
        _ = app.step() catch {};
    }
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
                .{ .position = .{ 0.0, 0.6 }, .color = .{ 1.0, 0.2, 0.2 } },
                .{ .position = .{ -0.6, -0.6 }, .color = .{ 0.2, 1.0, 0.2 } },
                .{ .position = .{ 0.6, -0.6 }, .color = .{ 0.2, 0.4, 1.0 } },
            },
        },
    });

    try commands.insertResource(common.ClearColor{ .color = common.Color.BLACK });
    try commands.insertResource(SceneReady{});
}
