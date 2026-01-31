const std = @import("std");
const builtin = @import("builtin");
const ecs = @import("ecs");
const modules = @import("modules");
const render = @import("render");

const is_wasm = builtin.target.cpu.arch.isWasm();

pub const WindowFlags = struct {
    pub const Resizable: u32 = 1 << 0;
    pub const HighDPI: u32 = 1 << 1;
};

pub const WindowConfig = struct {
    width: u32 = 800,
    height: u32 = 450,
    title: []const u8 = "Phasor Lite",
    target_fps: i32 = 60,
    flags: u32 = WindowFlags.Resizable | WindowFlags.HighDPI,
};

pub const Options = struct {
    canvas_id: []const u8 = "#canvas",
    window: WindowConfig = .{},
    install_window_module: bool = true,
    auto_surface: bool = true,
};

pub fn EntryPoint(comptime AppSpec: type) type {
    return struct {
        const options: Options = if (@hasDecl(AppSpec, "options")) AppSpec.options else Options{};
        const wasm = if (is_wasm) @import("wasm") else struct {
            pub fn io() std.Io {
                return undefined;
            }
        };
        const RenderSurface = modules.RenderModule.RenderSurface;

        const Runner = struct {
            app: ecs.App,
            io: std.Io,
        };

        fn nativeMain(init: std.process.Init) !u8 {
            const allocator = std.heap.c_allocator;

            var app = try ecs.App.init(allocator, &init.io);
            defer app.deinit();

            try setupApp(&app);
            return try app.run();
        }

        fn wasmMain() u8 {
            return 0;
        }

        pub const main = if (is_wasm) wasmMain else nativeMain;

        pub fn wasmCreate() callconv(.c) u32 {
            if (!is_wasm) return 0;

            const allocator = std.heap.page_allocator;
            const runner = allocator.create(Runner) catch return 0;
            errdefer allocator.destroy(runner);

            runner.io = wasm.io();
            runner.app = ecs.App.init(allocator, &runner.io) catch {
                return 0;
            };
            errdefer runner.app.deinit();

            setupApp(&runner.app) catch {
                return 0;
            };
            runner.app.start() catch {
                return 0;
            };

            return @intCast(@intFromPtr(runner));
        }

        pub fn wasmFrame(handle: u32) callconv(.c) void {
            if (!is_wasm) return;
            if (handle == 0) return;

            const runner: *Runner = @ptrFromInt(handle);
            _ = runner.app.step() catch {};
        }

        pub fn wasmDeinit(handle: u32) callconv(.c) void {
            if (!is_wasm) return;
            if (handle == 0) return;

            const allocator = std.heap.page_allocator;
            const runner: *Runner = @ptrFromInt(handle);
            runner.app.deinit();
            allocator.destroy(runner);
        }

        fn setupApp(app: *ecs.App) !void {
            if (!@hasDecl(AppSpec, "configure")) {
                @compileError("EntryPoint expects AppSpec.configure(app: *ecs.App) !void");
            }

            if (!is_wasm and options.install_window_module) {
                try installWindowModule(app, options.window);
            }

            if (options.auto_surface) {
                try app.addSystemTo(ecs.schedule.DefaultSchedule.BeforeFrame, setupSurface);
            }

            try AppSpec.configure(app);
        }

        fn installWindowModule(app: *ecs.App, config: WindowConfig) !void {
            if (is_wasm) {
                return;
            } else {
                const window = @import("window");
                var commands = ecs.Commands.init(app.allocator, app.io, &app.world);
                defer commands.deinit();

                if (!commands.hasResource(window.WindowSettings)) {
                    try commands.insertResource(window.WindowSettings{
                        .width = config.width,
                        .height = config.height,
                        .title = config.title,
                        .target_fps = config.target_fps,
                        .flags = config.flags,
                    });
                }
                if (!commands.isEmpty()) {
                    try commands.apply();
                }

                try app.installModule(window.WindowModule);
            }
        }

        fn setupSurface(commands: *ecs.Commands) !void {
            if (commands.hasResource(RenderSurface)) return;

            if (is_wasm) {
                const surface = render.surface_canvas.fromCanvasId(options.canvas_id);
                try commands.insertResource(RenderSurface{ .target = surface });
            } else {
                const window = @import("window");
                const window_res = commands.getResource(window.Window) orelse return;
                const handle = window_res.handle orelse return;
                const surface = try render.surface_glfw.fromGlfwWindow(handle);
                try commands.insertResource(RenderSurface{ .target = surface });
            }
        }
    };
}

pub fn exportWasm(comptime AppSpec: type) void {
    if (!builtin.target.cpu.arch.isWasm()) return;
    const Entry = EntryPoint(AppSpec);
    @export(&Entry.wasmCreate, .{ .name = "wasmCreate" });
    @export(&Entry.wasmFrame, .{ .name = "wasmFrame" });
    @export(&Entry.wasmDeinit, .{ .name = "wasmDeinit" });
}

pub fn main(comptime AppSpec: type) @TypeOf(EntryPoint(AppSpec).main) {
    exportWasm(AppSpec);
    return EntryPoint(AppSpec).main;
}
