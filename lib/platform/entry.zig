const std = @import("std");
const builtin = @import("builtin");
const ecs = @import("ecs");
const modules = @import("modules");
const render = @import("render");
const common = @import("common");
const schedule = ecs.schedule;

const is_wasm = builtin.target.cpu.arch.isWasm();

pub const WindowFlags = common.WindowFlags;
pub const WindowSettings = common.WindowSettings;

pub const Options = struct {
    canvas_id: []const u8 = "#canvas",
    window: WindowSettings = .{},
    vsync: ?bool = false,
    install_window_module: bool = true,
    auto_surface: bool = true,
    fullscreen: bool = false,
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
        var wasm_last_error: []const u8 = "ok";

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

            const allocator = std.heap.c_allocator;
            const runner = allocator.create(Runner) catch {
                wasm_last_error = "alloc_runner_failed";
                return 0;
            };
            errdefer allocator.destroy(runner);

            runner.io = wasm.io();
            runner.app = ecs.App.init(allocator, &runner.io) catch |err| {
                wasm_last_error = @errorName(err);
                return 0;
            };
            errdefer runner.app.deinit();

            setupApp(&runner.app) catch |err| {
                wasm_last_error = @errorName(err);
                return 0;
            };
            runner.app.start() catch |err| {
                wasm_last_error = @errorName(err);
                return 0;
            };

            return @intCast(@intFromPtr(runner));
        }

        pub fn wasmVsyncEnabled() callconv(.c) bool {
            if (!is_wasm) return true;
            return options.vsync orelse true;
        }

        pub fn wasmFullscreenEnabled() callconv(.c) bool {
            if (!is_wasm) return false;
            return options.fullscreen;
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

            const allocator = std.heap.c_allocator;
            const runner: *Runner = @ptrFromInt(handle);
            runner.app.deinit();
            allocator.destroy(runner);
        }

        pub fn wasmLastErrorPtr() callconv(.c) [*]const u8 {
            if (!is_wasm) return @ptrFromInt(0);
            return wasm_last_error.ptr;
        }

        pub fn wasmLastErrorLen() callconv(.c) usize {
            if (!is_wasm) return 0;
            return wasm_last_error.len;
        }

        fn setupApp(app: *ecs.App) !void {
            if (!@hasDecl(AppSpec, "configure")) {
                @compileError("EntryPoint expects AppSpec.configure(app: *ecs.App) !void");
            }

            if (!is_wasm and options.install_window_module) {
                try installWindowModule(app, options.window);
            }

            if (options.vsync) |vsync| {
                try installVsyncResource(app, vsync);
            }

            if (options.auto_surface) {
                try app.addSystemTo(schedule.DefaultSchedule.WindowCreate, setupSurface);
            }

            try AppSpec.configure(app);
        }

        fn installWindowModule(app: *ecs.App, config: WindowSettings) !void {
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
                        .flags = config.flags,
                    });
                }
                if (!commands.isEmpty()) {
                    try commands.apply();
                }

                try app.installModule(window.WindowModule);
            }
        }

        fn installVsyncResource(app: *ecs.App, enabled: bool) !void {
            var commands = ecs.Commands.init(app.allocator, app.io, &app.world);
            defer commands.deinit();

            if (!commands.hasResource(render.VSync)) {
                try commands.insertResource(render.VSync{ .enabled = enabled });
            }
            if (!commands.isEmpty()) {
                try commands.apply();
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
                const vsync = if (commands.getResource(render.VSync)) |vsync_res|
                    vsync_res.enabled
                else
                    true;
                const surface = try render.surface_glfw.fromGlfwWindowWithVsync(handle, vsync);
                try commands.insertResource(RenderSurface{ .target = surface });
            }
        }
    };
}

pub fn exportWasm(comptime AppSpec: type) void {
    if (!builtin.target.cpu.arch.isWasm()) return;
    const Entry = EntryPoint(AppSpec);
    @export(&Entry.wasmCreate, .{ .name = "wasmCreate" });
    @export(&Entry.wasmVsyncEnabled, .{ .name = "wasmVsyncEnabled" });
    @export(&Entry.wasmFullscreenEnabled, .{ .name = "wasmFullscreenEnabled" });
    @export(&Entry.wasmFrame, .{ .name = "wasmFrame" });
    @export(&Entry.wasmDeinit, .{ .name = "wasmDeinit" });
    @export(&Entry.wasmLastErrorPtr, .{ .name = "wasmLastErrorPtr" });
    @export(&Entry.wasmLastErrorLen, .{ .name = "wasmLastErrorLen" });
}

pub fn main(comptime AppSpec: type) @TypeOf(EntryPoint(AppSpec).main) {
    exportWasm(AppSpec);
    return EntryPoint(AppSpec).main;
}
