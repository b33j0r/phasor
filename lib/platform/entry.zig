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
    pause_on_gpu_error: bool = false,
    install_crash_dump: bool = false,
    install_soak_monitor: bool = false,
};

pub fn EntryPoint(comptime AppSpec: type) type {
    return struct {
        const Self = @This();
        const platform_options: Options = if (@hasDecl(AppSpec, "options")) AppSpec.options else Options{};
        const app_options = if (@hasDecl(AppSpec, "appOptions")) AppSpec.appOptions else ecs.App.InitConfig{};
        const Platform = if (is_wasm) Wasm else Native;

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

        pub const main = Platform.main;
        pub const Native = NativePlatform;
        pub const Wasm = WasmPlatform;

        const NativePlatform = struct {
            pub fn main(init: std.process.Init) !u8 {
                const allocator = std.heap.c_allocator;

                var app = try ecs.App.init(allocator, &init.io, app_options);
                defer app.deinit();

                try Self.setupApp(&app);
                return try app.run();
            }

            pub fn installWindowModule(app: *ecs.App, config: WindowSettings) !void {
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

            pub fn setupSurface(commands: *ecs.Commands) !void {
                if (commands.hasResource(RenderSurface)) return;

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
        };

        const WasmPlatform = struct {
            pub fn main() u8 {
                return 0;
            }

            pub fn installWindowModule(_: *ecs.App, _: WindowSettings) !void {}

            pub fn setupSurface(commands: *ecs.Commands) !void {
                if (commands.hasResource(RenderSurface)) return;

                const surface = render.surface_canvas.fromCanvasId(platform_options.canvas_id);
                try commands.insertResource(RenderSurface{ .target = surface });
            }

            pub fn create() callconv(.c) u32 {
                if (!is_wasm) return 0;

                const allocator = std.heap.wasm_allocator;
                const runner = allocator.create(Runner) catch {
                    wasm_last_error = "alloc_runner_failed";
                    return 0;
                };
                errdefer allocator.destroy(runner);

                runner.io = wasm.io();
                runner.app = ecs.App.init(allocator, &runner.io, app_options) catch |err| {
                    wasm_last_error = @errorName(err);
                    return 0;
                };
                errdefer runner.app.deinit();

                Self.setupApp(&runner.app) catch |err| {
                    wasm_last_error = @errorName(err);
                    return 0;
                };
                runner.app.start() catch |err| {
                    wasm_last_error = @errorName(err);
                    return 0;
                };

                return encodeRunnerHandle(runner);
            }

            pub fn vsyncEnabled() callconv(.c) bool {
                if (!is_wasm) return true;
                return platform_options.vsync orelse true;
            }

            pub fn fullscreenEnabled() callconv(.c) bool {
                if (!is_wasm) return false;
                return platform_options.fullscreen;
            }

            pub fn pauseOnGpuErrorEnabled() callconv(.c) bool {
                if (!is_wasm) return false;
                return platform_options.pause_on_gpu_error;
            }

            pub fn windowTitlePtr() callconv(.c) [*]const u8 {
                if (!is_wasm) return @ptrFromInt(0);
                return platform_options.window.title.ptr;
            }

            pub fn windowTitleLen() callconv(.c) usize {
                if (!is_wasm) return 0;
                return platform_options.window.title.len;
            }

            pub fn frame(handle: u32) callconv(.c) void {
                if (!is_wasm) return;
                if (handle == 0) return;

                const runner = decodeRunnerHandle(handle);
                _ = runner.app.step() catch |err| {
                    wasm_last_error = @errorName(err);
                    return;
                };
                wasm_last_error = "ok";
            }

            pub fn resize(
                handle: u32,
                logical_width: u32,
                logical_height: u32,
                framebuffer_width: u32,
                framebuffer_height: u32,
            ) callconv(.c) void {
                if (!is_wasm) return;
                if (handle == 0) return;

                const runner = decodeRunnerHandle(handle);
                var commands = ecs.Commands.init(runner.app.allocator, runner.app.io, &runner.app.world);
                defer commands.deinit();
                modules.RenderModule.setSurfaceSize(
                    &commands,
                    logical_width,
                    logical_height,
                    framebuffer_width,
                    framebuffer_height,
                );
                _ = commands.apply() catch {};
            }

            pub fn onDeviceLost(handle: u32) callconv(.c) void {
                if (!is_wasm) return;
                if (handle == 0) return;
                if (!@hasDecl(AppSpec, "onDeviceLost")) return;

                const runner = decodeRunnerHandle(handle);
                callDeviceHook(AppSpec.onDeviceLost, runner);
            }

            pub fn onDeviceRestored(handle: u32) callconv(.c) void {
                if (!is_wasm) return;
                if (handle == 0) return;
                if (!@hasDecl(AppSpec, "onDeviceRestored")) return;

                const runner = decodeRunnerHandle(handle);
                callDeviceHook(AppSpec.onDeviceRestored, runner);
            }

            pub fn deinit(handle: u32) callconv(.c) void {
                if (!is_wasm) return;
                if (handle == 0) return;

                const allocator = std.heap.wasm_allocator;
                const runner = decodeRunnerHandle(handle);
                runner.app.deinit();
                allocator.destroy(runner);
            }

            pub fn lastErrorPtr() callconv(.c) [*]const u8 {
                if (!is_wasm) return @ptrFromInt(0);
                return wasm_last_error.ptr;
            }

            pub fn lastErrorLen() callconv(.c) usize {
                if (!is_wasm) return 0;
                return wasm_last_error.len;
            }

            fn encodeRunnerHandle(runner: *Runner) u32 {
                return @intCast(@intFromPtr(runner) + 1);
            }

            fn decodeRunnerHandle(handle: u32) *Runner {
                return @ptrFromInt(@as(usize, handle) - 1);
            }

            fn callDeviceHook(comptime hook: anytype, runner: *Runner) void {
                switch (@typeInfo(@TypeOf(hook))) {
                    .@"fn" => |info| {
                        if (info.return_type) |ret| {
                            switch (@typeInfo(ret)) {
                                .error_union => {
                                    hook(&runner.app) catch |e| {
                                        wasm_last_error = @errorName(e);
                                        return;
                                    };
                                    wasm_last_error = "ok";
                                },
                                else => {
                                    _ = hook(&runner.app);
                                },
                            }
                        } else {
                            hook(&runner.app);
                        }
                    },
                    else => {},
                }
            }
        };

        fn setupApp(app: *ecs.App) !void {
            if (!@hasDecl(AppSpec, "configure")) {
                @compileError("EntryPoint expects AppSpec.configure(app: *ecs.App) !void");
            }

            if (platform_options.install_window_module) {
                try Platform.installWindowModule(app, platform_options.window);
            }

            if (platform_options.vsync) |vsync| {
                try installVsyncResource(app, vsync);
            }

            if (platform_options.auto_surface) {
                try app.addSystemTo(schedule.DefaultSchedule.WindowCreate, Platform.setupSurface);
            }

            if (platform_options.install_crash_dump) {
                try app.installModule(modules.CrashDumpModule);
            }
            if (platform_options.install_soak_monitor) {
                try app.installModule(modules.SoakMonitorModule);
            }

            try AppSpec.configure(app);
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
    };
}

pub fn installDefaultModules(app: *ecs.App) !void {
    try app.installModule(modules.TimeModule);
    try app.installModule(modules.TimerModule);
    try app.installModule(modules.RenderModule);
    try app.installModule(modules.InputModule);
    try app.installModule(modules.AudioModule);
}

pub fn exportWasm(comptime AppSpec: type) void {
    if (!builtin.target.cpu.arch.isWasm()) return;
    const Entry = EntryPoint(AppSpec);
    @export(&Entry.Wasm.create, .{ .name = "wasmCreate" });
    @export(&Entry.Wasm.vsyncEnabled, .{ .name = "wasmVsyncEnabled" });
    @export(&Entry.Wasm.fullscreenEnabled, .{ .name = "wasmFullscreenEnabled" });
    @export(&Entry.Wasm.pauseOnGpuErrorEnabled, .{ .name = "wasmPauseOnGpuErrorEnabled" });
    @export(&Entry.Wasm.windowTitlePtr, .{ .name = "wasmWindowTitlePtr" });
    @export(&Entry.Wasm.windowTitleLen, .{ .name = "wasmWindowTitleLen" });
    @export(&Entry.Wasm.frame, .{ .name = "wasmFrame" });
    @export(&Entry.Wasm.resize, .{ .name = "wasmResize" });
    @export(&Entry.Wasm.onDeviceLost, .{ .name = "wasmOnDeviceLost" });
    @export(&Entry.Wasm.onDeviceRestored, .{ .name = "wasmOnDeviceRestored" });
    @export(&Entry.Wasm.deinit, .{ .name = "wasmDeinit" });
    @export(&Entry.Wasm.lastErrorPtr, .{ .name = "wasmLastErrorPtr" });
    @export(&Entry.Wasm.lastErrorLen, .{ .name = "wasmLastErrorLen" });
}

pub fn main(comptime AppSpec: type) @TypeOf(EntryPoint(AppSpec).main) {
    exportWasm(AppSpec);
    return EntryPoint(AppSpec).main;
}
