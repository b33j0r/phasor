const builtin = @import("builtin");
const std = @import("std");

const ecs = @import("ecs");
const metrics = @import("metrics");
const render = @import("render");
const render_mod = @import("render").RenderModule;
const time_mod = @import("modules").TimeModule;
const crash = @import("metrics").CrashDumpModule;

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;

pub const SoakMonitorSettings = struct {
    enabled: bool = false,
    warmup_seconds: f64 = 10.0,
    snapshot_interval_seconds: f64 = 60.0,
    output_dir: []const u8 = "local/logs/soak",
    allow_buffer_growth: u32 = 0,
    allow_texture_growth: u32 = 0,
    allow_bind_group_growth: u32 = 0,
    allow_pipeline_growth: u32 = 0,
};

const SoakMonitorState = struct {
    next_snapshot: f64 = 0.0,
    last_buffers: u32 = 0,
    last_textures: u32 = 0,
    last_bind_groups: u32 = 0,
    last_pipelines: u32 = 0,
};

pub fn install(app: *AppCommands, commands: *Commands) !void {
    if (!commands.hasResource(SoakMonitorSettings)) {
        try commands.insertResource(SoakMonitorSettings{});
    }
    if (!commands.hasResource(SoakMonitorState)) {
        try commands.insertResource(SoakMonitorState{});
    }
    try app.addSystem("Update", updateSoakMonitor);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(updateSoakMonitor);
}

fn updateSoakMonitor(
    commands: *Commands,
    settings: Res(SoakMonitorSettings),
    state: ResMut(SoakMonitorState),
    run_time: Res(time_mod.RunTime),
    store_opt: ResOpt(metrics.Store),
    render_state_opt: ResOpt(render_mod.RenderState),
) void {
    if (!settings.ptr.enabled) return;
    const elapsed_seconds = run_time.ptr.seconds;
    if (state.ptr.next_snapshot == 0.0) {
        state.ptr.next_snapshot = settings.ptr.warmup_seconds;
    }
    if (elapsed_seconds < state.ptr.next_snapshot) return;

    const store = store_opt.ptr orelse return;
    const snapshot = readSnapshot(store);

    const warn = checkInvariants(settings.ptr.*, state.ptr, snapshot, elapsed_seconds);
    writeSnapshot(commands, settings.ptr.*, elapsed_seconds, snapshot, render_state_opt.ptr, warn) catch |err| {
        std.log.err("SoakMonitor: snapshot write failed ({s})", .{@errorName(err)});
    };

    state.ptr.last_buffers = snapshot.create_buffers;
    state.ptr.last_textures = snapshot.create_textures;
    state.ptr.last_bind_groups = snapshot.create_bind_groups;
    state.ptr.last_pipelines = snapshot.create_pipelines;
    state.ptr.next_snapshot = elapsed_seconds + settings.ptr.snapshot_interval_seconds;

    if (warn) {
        commands.insertResource(crash.CrashDumpRequest{ .reason = "soak_invariant" }) catch {};
    }
}

const Snapshot = struct {
    fps: f64,
    frame_ms: f64,
    wasm_mem_mb: f64,
    js_heap_used_mb: f64,
    js_heap_total_mb: f64,
    create_buffers: u32,
    destroy_buffers: u32,
    create_textures: u32,
    destroy_textures: u32,
    create_bind_groups: u32,
    create_pipelines: u32,
    create_views: u32,
    create_encoders: u32,
    create_passes: u32,
    queue_wait_ms: u32,
    queue_wait_max_ms: u32,
};

fn readSnapshot(store_const: *const metrics.Store) Snapshot {
    const store: *metrics.Store = @constCast(store_const);
    return .{
        .fps = metric(store, "fps"),
        .frame_ms = metric(store, "frame_ms"),
        .wasm_mem_mb = metric(store, "wasm_mem_mb"),
        .js_heap_used_mb = metric(store, "js_heap_used_mb"),
        .js_heap_total_mb = metric(store, "js_heap_total_mb"),
        .create_buffers = metricU32(store, "webgpu_create_buffers"),
        .destroy_buffers = metricU32(store, "webgpu_destroy_buffers"),
        .create_textures = metricU32(store, "webgpu_create_textures"),
        .destroy_textures = metricU32(store, "webgpu_destroy_textures"),
        .create_bind_groups = metricU32(store, "webgpu_create_bind_groups"),
        .create_pipelines = metricU32(store, "webgpu_create_pipelines"),
        .create_views = metricU32(store, "webgpu_create_views"),
        .create_encoders = metricU32(store, "webgpu_create_encoders"),
        .create_passes = metricU32(store, "webgpu_create_passes"),
        .queue_wait_ms = metricU32(store, "webgpu_queue_wait_ms"),
        .queue_wait_max_ms = metricU32(store, "webgpu_queue_wait_max_ms"),
    };
}

fn metric(store: *metrics.Store, name: []const u8) f64 {
    if (store.get(name)) |sample| {
        return sample.value.asF64();
    }
    return 0.0;
}

fn metricU32(store: *metrics.Store, name: []const u8) u32 {
    return @intFromFloat(metric(store, name));
}

fn checkInvariants(
    settings: SoakMonitorSettings,
    state: *SoakMonitorState,
    snapshot: Snapshot,
    elapsed_seconds: f64,
) bool {
    if (elapsed_seconds < settings.warmup_seconds) return false;
    const buf_growth = growth(snapshot.create_buffers, state.last_buffers);
    const tex_growth = growth(snapshot.create_textures, state.last_textures);
    const bg_growth = growth(snapshot.create_bind_groups, state.last_bind_groups);
    const pipe_growth = growth(snapshot.create_pipelines, state.last_pipelines);
    return buf_growth > settings.allow_buffer_growth or
        tex_growth > settings.allow_texture_growth or
        bg_growth > settings.allow_bind_group_growth or
        pipe_growth > settings.allow_pipeline_growth;
}

fn writeSnapshot(
    commands: *Commands,
    settings: SoakMonitorSettings,
    elapsed_seconds: f64,
    snapshot: Snapshot,
    render_state_opt: ?*const render_mod.RenderState,
    warn: bool,
) !void {
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(commands.allocator);

    try appendFmt(&buffer, commands.allocator, "soak snapshot\n", .{});
    try appendFmt(&buffer, commands.allocator, "  elapsed_seconds={d:.3}\n", .{elapsed_seconds});
    try appendFmt(&buffer, commands.allocator, "  fps={d:.2} frame_ms={d:.2}\n", .{ snapshot.fps, snapshot.frame_ms });
    try appendFmt(&buffer, commands.allocator, "  wasm_mem_mb={d:.2} js_heap_used_mb={d:.2} js_heap_total_mb={d:.2}\n", .{
        snapshot.wasm_mem_mb,
        snapshot.js_heap_used_mb,
        snapshot.js_heap_total_mb,
    });
    try appendFmt(
        &buffer,
        commands.allocator,
        "  webgpu_create buf={d} tex={d} view={d} bg={d} pipe={d} enc={d} pass={d}\n",
        .{
            snapshot.create_buffers,
            snapshot.create_textures,
            snapshot.create_views,
            snapshot.create_bind_groups,
            snapshot.create_pipelines,
            snapshot.create_encoders,
            snapshot.create_passes,
        },
    );
    try appendFmt(
        &buffer,
        commands.allocator,
        "  webgpu_destroy buf={d} tex={d}\n",
        .{ snapshot.destroy_buffers, snapshot.destroy_textures },
    );
    try appendFmt(
        &buffer,
        commands.allocator,
        "  webgpu_queue wait={d} max={d}\n",
        .{ snapshot.queue_wait_ms, snapshot.queue_wait_max_ms },
    );
    if (render_state_opt) |state| {
        const stats = render.rendererStats(&state.renderer);
        try appendFmt(
            &buffer,
            commands.allocator,
            "  render_stats mesh={d}/{d} tex={d}/{d} mat={d}/{d} samp={d}/{d}\n",
            .{
                stats.meshes_alive,
                stats.meshes_slots,
                stats.textures_alive,
                stats.textures_slots,
                stats.materials_alive,
                stats.materials_slots,
                stats.samplers_alive,
                stats.samplers_slots,
            },
        );
    }
    if (warn) {
        try appendFmt(&buffer, commands.allocator, "  warn=invariant_violation\n", .{});
    }

    if (builtin.target.cpu.arch.isWasm()) {
        std.log.info("{s}", .{buffer.items});
        return;
    }

    const io = commands.io.*;
    try std.Io.Dir.cwd().createDirPath(io, settings.output_dir);
    const ts = std.Io.Clock.real.now(commands.io.*) catch std.Io.Timestamp.zero;
    const now_ms: i64 = ts.toMilliseconds();
    var name_buf: [128]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buf, "{s}/soak-{d}.log", .{ settings.output_dir, now_ms });
    var file = try std.Io.Dir.cwd().createFile(io, name, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, buffer.items);
}

fn growth(current: u32, last: u32) u32 {
    return if (current >= last) current - last else 0;
}

fn appendFmt(
    buffer: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const line = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(line);
    try buffer.appendSlice(allocator, line);
}
