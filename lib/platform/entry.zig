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

pub const RuntimePlatformSettings = struct {
    fullscreen: bool = false,
    pause_on_gpu_error: bool = false,
};

pub const RuntimeApp = struct {
    inner: ecs.App,
    moved_to_wasm: bool = false,

    const Self = @This();

    pub fn init(init_context: *const std.process.Init, comptime config: ecs.App.AppConfig) !Self {
        const allocator = if (is_wasm) std.heap.wasm_allocator else std.heap.c_allocator;
        return .{
            .inner = try ecs.App.init(allocator, &init_context.io, config),
        };
    }

    pub fn default(init_context: *const std.process.Init) !Self {
        return init(init_context, .{});
    }

    pub fn deinit(self: *Self) void {
        if (self.moved_to_wasm) return;
        self.inner.deinit();
    }

    pub fn run(self: *Self) !u8 {
        comptime exportRootMainWasm();
        if (is_wasm) {
            return runWasm(self);
        }
        return try self.inner.run();
    }

    pub fn start(self: *Self) !void {
        try self.inner.start();
    }

    pub fn step(self: *Self) !?u8 {
        return try self.inner.step();
    }

    pub fn addSystem(self: *Self, comptime system_fn: anytype) !void {
        try self.inner.addSystem(system_fn);
    }

    pub fn addSystemTo(self: *Self, schedule_label: []const u8, comptime system_fn: anytype) !void {
        try self.inner.addSystemTo(schedule_label, system_fn);
    }

    pub fn removeSystem(self: *Self, comptime system_fn: anytype) void {
        self.inner.removeSystem(system_fn);
    }

    pub fn addSchedule(self: *Self, label: []const u8) !void {
        try self.inner.addSchedule(label);
    }

    pub fn insertScheduleBetween(self: *Self, before_label: []const u8, label: []const u8, after_label: []const u8) !void {
        try self.inner.insertScheduleBetween(before_label, label, after_label);
    }

    pub fn installModule(self: *Self, comptime module: anytype) !void {
        try self.inner.installModule(module);
    }

    pub fn installDefaultModules(self: *Self) !void {
        try installDefaultModulesFor(&self.inner);
    }

    pub fn uninstallModule(self: *Self, comptime module: anytype) !void {
        try self.inner.uninstallModule(module);
    }

    pub fn appCommands(self: *Self) ecs.AppCommands {
        return self.inner.appCommands();
    }

    pub fn commands(self: *Self) ecs.Commands {
        return ecs.Commands.init(self.inner.allocator, self.inner.io, &self.inner.world);
    }

    pub fn insertResource(self: *Self, resource: anytype) !void {
        try self.inner.insertResource(resource);
    }

    pub fn getResource(self: *Self, comptime T: type) ?*const T {
        return self.inner.getResource(T);
    }

    pub fn getResourceMut(self: *Self, comptime T: type) ?*T {
        return self.inner.getResourceMut(T);
    }

    pub fn removeResource(self: *Self, comptime T: type) bool {
        return self.inner.removeResource(T);
    }

    pub fn hasResource(self: *Self, comptime T: type) bool {
        return self.inner.hasResource(T);
    }

    pub fn runScheduleByLabel(self: *Self, label: []const u8) !void {
        try self.inner.runScheduleByLabel(label);
    }
};

pub const RuntimeBuilder = struct {
    app: *ecs.App,
    platform_options: Options,

    pub fn init(app: *ecs.App, platform_options: Options) RuntimeBuilder {
        return .{
            .app = app,
            .platform_options = platform_options,
        };
    }

    pub fn platform(self: *RuntimeBuilder, comptime options: Options) !void {
        self.platform_options = options;
        try installPlatformOptions(self.app, options);
    }

    pub fn commands(self: *RuntimeBuilder) !ecs.Commands {
        return ecs.Commands.init(self.app.allocator, self.app.io, &self.app.world);
    }

    pub fn addDefaultModules(self: *RuntimeBuilder) !void {
        try installDefaultModules(self.app);
    }

    pub fn addPlatformModules(self: *RuntimeBuilder, comptime settings: PlatformModuleSettings) !void {
        try installPlatformModules(self.app, settings);
    }

    pub fn addModule(self: *RuntimeBuilder, comptime module: anytype) !void {
        try self.app.installModule(module);
    }

    pub fn addSystem(self: *RuntimeBuilder, comptime system_fn: anytype) !void {
        try self.app.addSystem(system_fn);
    }

    pub fn addSystemTo(self: *RuntimeBuilder, schedule_label: []const u8, comptime system_fn: anytype) !void {
        try self.app.addSystemTo(schedule_label, system_fn);
    }
};

pub fn EntryPoint(comptime AppSpec: type) type {
    return struct {
        const Self = @This();
        const platform_options: Options = if (@hasDecl(AppSpec, "options")) AppSpec.options else Options{};
        const app_config = if (@hasDecl(AppSpec, "appConfig"))
            AppSpec.appConfig
        else if (@hasDecl(AppSpec, "appOptions"))
            AppSpec.appOptions
        else
            ecs.App.AppConfig{};
        const Platform = if (is_wasm) Wasm else Native;

        const wasm = if (is_wasm) @import("wasm") else struct {
            pub fn io() std.Io {
                return undefined;
            }
        };
        var wasm_last_error: []const u8 = "ok";
        var wasm_window_title: []const u8 = platform_options.window.title;
        var wasm_vsync_enabled: bool = platform_options.vsync orelse true;
        var wasm_fullscreen_enabled: bool = platform_options.fullscreen;
        var wasm_pause_on_gpu_error_enabled: bool = platform_options.pause_on_gpu_error;

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

                var app = try ecs.App.init(allocator, &init.io, app_config);
                defer app.deinit();

                try Self.setupApp(&app);
                return try app.run();
            }

            pub const setupSurface = setupNativeSurface;
        };

        const WasmPlatform = struct {
            pub fn main() u8 {
                return 0;
            }

            pub const setupSurface = setupWasmSurface(platform_options.canvas_id);

            pub fn create() callconv(.c) u32 {
                if (!is_wasm) return 0;

                const allocator = std.heap.wasm_allocator;
                const runner = allocator.create(Runner) catch {
                    wasm_last_error = "alloc_runner_failed";
                    return 0;
                };
                errdefer allocator.destroy(runner);

                runner.io = wasm.io();
                runner.app = ecs.App.init(allocator, &runner.io, app_config) catch |err| {
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
                syncWasmExportSettings(&runner.app);

                return encodeRunnerHandle(runner);
            }

            pub fn vsyncEnabled() callconv(.c) bool {
                if (!is_wasm) return true;
                return wasm_vsync_enabled;
            }

            pub fn fullscreenEnabled() callconv(.c) bool {
                if (!is_wasm) return false;
                return wasm_fullscreen_enabled;
            }

            pub fn pauseOnGpuErrorEnabled() callconv(.c) bool {
                if (!is_wasm) return false;
                return wasm_pause_on_gpu_error_enabled;
            }

            pub fn windowTitlePtr() callconv(.c) [*]const u8 {
                if (!is_wasm) return @ptrFromInt(0);
                return wasm_window_title.ptr;
            }

            pub fn windowTitleLen() callconv(.c) usize {
                if (!is_wasm) return 0;
                return wasm_window_title.len;
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

            fn syncWasmExportSettings(app: *ecs.App) void {
                if (app.getResource(WindowSettings)) |settings| {
                    wasm_window_title = settings.title;
                }
                if (app.getResource(render.VSync)) |vsync| {
                    wasm_vsync_enabled = vsync.enabled;
                }
                if (app.getResource(RuntimePlatformSettings)) |settings| {
                    wasm_fullscreen_enabled = settings.fullscreen;
                    wasm_pause_on_gpu_error_enabled = settings.pause_on_gpu_error;
                }
            }
        };

        fn setupApp(app: *ecs.App) !void {
            if (@hasDecl(AppSpec, "build")) {
                var runtime = RuntimeBuilder.init(app, platform_options);
                try AppSpec.build(&runtime);
                return;
            }

            if (!@hasDecl(AppSpec, "configure")) {
                @compileError("EntryPoint expects AppSpec.configure(app: *ecs.App) !void or AppSpec.build(runtime: *platform.RuntimeBuilder) !void");
            }

            try installPlatformOptions(app, platform_options);

            try AppSpec.configure(app);
        }
    };
}

pub fn installDefaultModules(app: *ecs.App) !void {
    try installDefaultModulesFor(app);
}

fn installDefaultModulesFor(app: *ecs.App) !void {
    try installPlatformModules(app, .{});
    try app.installModule(modules.TimeModule);
    try app.installModule(modules.TimerModule);
    try app.installModule(modules.RenderModule);
    try app.installModule(modules.InputModule);
    try app.installModule(modules.AudioModule);
}

pub const PlatformModuleSettings = struct {
    install_window_module: bool = true,
    auto_surface: bool = true,
    canvas_id: []const u8 = "#canvas",
};

pub fn installPlatformModules(app: *ecs.App, comptime settings: PlatformModuleSettings) !void {
    if (!is_wasm and settings.install_window_module) {
        const window = @import("window");
        try app.installModule(window.WindowModule);
    }
    if (settings.auto_surface) {
        if (is_wasm) {
            try app.addSystemTo(schedule.DefaultSchedule.WindowCreate, setupWasmSurface(settings.canvas_id));
        } else {
            try app.addSystemTo(schedule.DefaultSchedule.WindowCreate, setupNativeSurface);
        }
    }
}

fn installPlatformOptions(app: *ecs.App, comptime options: Options) !void {
    try app.insertResource(RuntimePlatformSettings{
        .fullscreen = options.fullscreen,
        .pause_on_gpu_error = options.pause_on_gpu_error,
    });
    try installOptionResources(app, options);

    if (options.install_crash_dump) {
        try app.installModule(modules.CrashDumpModule);
    }
    if (options.install_soak_monitor) {
        try app.installModule(modules.SoakMonitorModule);
    }
}

fn installOptionResources(app: *ecs.App, comptime options: Options) !void {
    if (options.install_window_module and !app.hasResource(WindowSettings)) {
        try app.insertResource(options.window);
    }
    if (options.vsync) |vsync| {
        if (!app.hasResource(render.VSync)) {
            try app.insertResource(render.VSync{ .enabled = vsync });
        }
    }
}

fn setupNativeSurface(commands: *ecs.Commands) !void {
    if (commands.hasResource(modules.RenderModule.RenderSurface)) return;

    const window = @import("window");
    const window_res = commands.getResource(window.Window) orelse return;
    const handle = window_res.handle orelse return;
    const vsync = if (commands.getResource(render.VSync)) |vsync_res|
        vsync_res.enabled
    else
        true;
    const surface = try render.surface_glfw.fromGlfwWindowWithVsync(handle, vsync);
    try commands.insertResource(modules.RenderModule.RenderSurface{ .target = surface });
}

fn setupWasmSurface(comptime canvas_id: []const u8) fn (*ecs.Commands) anyerror!void {
    return struct {
        fn run(commands: *ecs.Commands) !void {
            if (commands.hasResource(modules.RenderModule.RenderSurface)) return;

            const surface = render.surface_canvas.fromCanvasId(canvas_id);
            try commands.insertResource(modules.RenderModule.RenderSurface{ .target = surface });
        }
    }.run;
}

const wasm_runtime = if (is_wasm) @import("wasm") else struct {
    pub fn io() std.Io {
        return undefined;
    }
};

const WasmRuntimeRunner = struct {
    app: ecs.App,
    io: std.Io,
};

var root_wasm_runner: ?*WasmRuntimeRunner = null;
var root_wasm_last_error: []const u8 = "ok";
var root_wasm_window_title: []const u8 = "Phasor";
var root_wasm_vsync_enabled: bool = true;
var root_wasm_fullscreen_enabled: bool = false;
var root_wasm_pause_on_gpu_error_enabled: bool = false;
var root_wasm_arena: std.heap.ArenaAllocator = undefined;
var root_wasm_environ_map: std.process.Environ.Map = undefined;
var root_wasm_init_ready: bool = false;

fn runWasm(app: *RuntimeApp) !u8 {
    if (!is_wasm) unreachable;
    if (root_wasm_runner != null) return error.WasmAppAlreadyRunning;

    const allocator = std.heap.wasm_allocator;
    const runner = try allocator.create(WasmRuntimeRunner);
    errdefer allocator.destroy(runner);

    runner.io = wasm_runtime.io();
    runner.app = app.inner;
    runner.app.io = &runner.io;

    app.moved_to_wasm = true;
    root_wasm_runner = runner;
    errdefer {
        root_wasm_runner = null;
        app.moved_to_wasm = false;
    }

    try runner.app.start();
    syncRootWasmExportSettings(&runner.app);
    root_wasm_last_error = "ok";
    return 0;
}

fn exportRootMainWasm() void {
    if (!is_wasm) return;
    @export(&rootWasmCreate, .{ .name = "wasmCreate" });
    @export(&rootWasmVsyncEnabled, .{ .name = "wasmVsyncEnabled" });
    @export(&rootWasmFullscreenEnabled, .{ .name = "wasmFullscreenEnabled" });
    @export(&rootWasmPauseOnGpuErrorEnabled, .{ .name = "wasmPauseOnGpuErrorEnabled" });
    @export(&rootWasmWindowTitlePtr, .{ .name = "wasmWindowTitlePtr" });
    @export(&rootWasmWindowTitleLen, .{ .name = "wasmWindowTitleLen" });
    @export(&rootWasmFrame, .{ .name = "wasmFrame" });
    @export(&rootWasmResize, .{ .name = "wasmResize" });
    @export(&rootWasmOnDeviceLost, .{ .name = "wasmOnDeviceLost" });
    @export(&rootWasmOnDeviceRestored, .{ .name = "wasmOnDeviceRestored" });
    @export(&rootWasmDeinit, .{ .name = "wasmDeinit" });
    @export(&rootWasmLastErrorPtr, .{ .name = "wasmLastErrorPtr" });
    @export(&rootWasmLastErrorLen, .{ .name = "wasmLastErrorLen" });
}

fn rootWasmCreate() callconv(.c) u32 {
    if (!is_wasm) return 0;
    if (root_wasm_runner) |runner| {
        return encodeRootWasmRunnerHandle(runner);
    }

    ensureRootWasmInitGlobals();
    const init_context = makeRootWasmInit();
    const Root = @import("root");
    const result = callRootMain(Root.main, init_context) catch |err| {
        root_wasm_last_error = @errorName(err);
        return 0;
    };
    if (result != 0) {
        root_wasm_last_error = "main_returned_nonzero";
        return 0;
    }

    const runner = root_wasm_runner orelse {
        root_wasm_last_error = "app_run_not_called";
        return 0;
    };
    return encodeRootWasmRunnerHandle(runner);
}

fn callRootMain(comptime main_fn: anytype, init_context: std.process.Init) !u8 {
    const result = try main_fn(init_context);
    return switch (@TypeOf(result)) {
        void => 0,
        u8 => result,
        else => @compileError("WASM App main must return !void or !u8"),
    };
}

fn rootWasmVsyncEnabled() callconv(.c) bool {
    if (!is_wasm) return true;
    return root_wasm_vsync_enabled;
}

fn rootWasmFullscreenEnabled() callconv(.c) bool {
    if (!is_wasm) return false;
    return root_wasm_fullscreen_enabled;
}

fn rootWasmPauseOnGpuErrorEnabled() callconv(.c) bool {
    if (!is_wasm) return false;
    return root_wasm_pause_on_gpu_error_enabled;
}

fn rootWasmWindowTitlePtr() callconv(.c) [*]const u8 {
    if (!is_wasm) return @ptrFromInt(0);
    return root_wasm_window_title.ptr;
}

fn rootWasmWindowTitleLen() callconv(.c) usize {
    if (!is_wasm) return 0;
    return root_wasm_window_title.len;
}

fn rootWasmFrame(handle: u32) callconv(.c) void {
    if (!is_wasm) return;
    const runner = decodeRootWasmRunnerHandle(handle) orelse return;
    _ = runner.app.step() catch |err| {
        root_wasm_last_error = @errorName(err);
        return;
    };
    root_wasm_last_error = "ok";
}

fn rootWasmResize(
    handle: u32,
    logical_width: u32,
    logical_height: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
) callconv(.c) void {
    if (!is_wasm) return;
    const runner = decodeRootWasmRunnerHandle(handle) orelse return;
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

fn rootWasmOnDeviceLost(handle: u32) callconv(.c) void {
    if (!is_wasm) return;
    const runner = decodeRootWasmRunnerHandle(handle) orelse return;
    var commands = ecs.Commands.init(runner.app.allocator, runner.app.io, &runner.app.world);
    defer commands.deinit();
    modules.RenderModule.signalDeviceLost(&commands);
    _ = commands.apply() catch {};
}

fn rootWasmOnDeviceRestored(handle: u32) callconv(.c) void {
    if (!is_wasm) return;
    const runner = decodeRootWasmRunnerHandle(handle) orelse return;
    var commands = ecs.Commands.init(runner.app.allocator, runner.app.io, &runner.app.world);
    defer commands.deinit();
    modules.RenderModule.signalDeviceRestored(&commands);
    _ = commands.apply() catch {};
}

fn rootWasmDeinit(handle: u32) callconv(.c) void {
    if (!is_wasm) return;
    const runner = decodeRootWasmRunnerHandle(handle) orelse return;
    if (root_wasm_runner == runner) {
        root_wasm_runner = null;
    }
    runner.app.deinit();
    std.heap.wasm_allocator.destroy(runner);
}

fn rootWasmLastErrorPtr() callconv(.c) [*]const u8 {
    if (!is_wasm) return @ptrFromInt(0);
    return root_wasm_last_error.ptr;
}

fn rootWasmLastErrorLen() callconv(.c) usize {
    if (!is_wasm) return 0;
    return root_wasm_last_error.len;
}

fn encodeRootWasmRunnerHandle(runner: *WasmRuntimeRunner) u32 {
    return @intCast(@intFromPtr(runner) + 1);
}

fn decodeRootWasmRunnerHandle(handle: u32) ?*WasmRuntimeRunner {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, handle) - 1);
}

fn syncRootWasmExportSettings(app: *ecs.App) void {
    if (app.getResource(WindowSettings)) |settings| {
        root_wasm_window_title = settings.title;
    }
    if (app.getResource(render.VSync)) |vsync| {
        root_wasm_vsync_enabled = vsync.enabled;
    }
    if (app.getResource(RuntimePlatformSettings)) |settings| {
        root_wasm_fullscreen_enabled = settings.fullscreen;
        root_wasm_pause_on_gpu_error_enabled = settings.pause_on_gpu_error;
    }
}

fn makeRootWasmInit() std.process.Init {
    if (!is_wasm) unreachable;
    return .{
        .minimal = .{
            .environ = .empty,
            .args = .{ .vector = &[_][*:0]const u8{} },
        },
        .arena = &root_wasm_arena,
        .gpa = std.heap.wasm_allocator,
        .io = wasm_runtime.io(),
        .environ_map = &root_wasm_environ_map,
        .preopens = .empty,
    };
}

fn ensureRootWasmInitGlobals() void {
    if (!is_wasm) return;
    if (root_wasm_init_ready) return;
    root_wasm_arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
    root_wasm_environ_map = std.process.Environ.Map.init(std.heap.wasm_allocator);
    root_wasm_init_ready = true;
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

pub fn exportWasmWith(comptime app_config: ecs.App.AppConfig, comptime configure_fn: anytype) void {
    const AppSpec = struct {
        pub const appConfig = app_config;

        pub fn configure(app: *ecs.App) !void {
            try configure_fn(app);
        }
    };
    exportWasm(AppSpec);
}

pub fn main(comptime AppSpec: type) @TypeOf(EntryPoint(AppSpec).main) {
    exportWasm(AppSpec);
    return EntryPoint(AppSpec).main;
}
