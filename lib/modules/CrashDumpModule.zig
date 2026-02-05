const builtin = @import("builtin");
const std = @import("std");

const ecs = @import("ecs");
const metrics = @import("metrics");
const render = @import("render");
const render_mod = @import("RenderModule.zig");
const time_mod = @import("TimeModule.zig");

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;

pub const CrashDumpSettings = struct {
    enabled: bool = true,
    output_dir: []const u8 = "local/logs/crash",
};

pub const CrashDumpRequest = struct {
    reason: []const u8 = "manual",
};

const CrashDumpState = struct {
    dumped: bool = false,
    last_device_lost: bool = false,
};

pub fn install(app: *AppCommands, commands: *Commands) !void {
    if (commands.hasResource(CrashDumpState)) return;
    if (!commands.hasResource(CrashDumpSettings)) {
        try commands.insertResource(CrashDumpSettings{});
    }
    try commands.insertResource(CrashDumpState{});
    try app.addSystem("Update", updateCrashDump);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(updateCrashDump);
}

fn updateCrashDump(
    commands: *Commands,
    settings: Res(CrashDumpSettings),
    state: ResMut(CrashDumpState),
    store_opt: ResOpt(metrics.Store),
    elapsed_opt: ResOpt(time_mod.ElapsedTime),
    render_state_opt: ResOpt(render_mod.RenderState),
    request_opt: ResOpt(CrashDumpRequest),
) void {
    if (!settings.ptr.enabled) return;
    const device_lost = detectDeviceLost();
    if (request_opt.ptr) |request| {
        writeCrashDump(commands, settings.ptr.*, store_opt.ptr, elapsed_opt.ptr, render_state_opt.ptr, request.reason) catch |err| {
            std.log.err("CrashDump: failed to write ({s})", .{@errorName(err)});
        };
        _ = commands.removeResource(CrashDumpRequest);
        state.ptr.dumped = true;
    } else if (device_lost and !state.ptr.dumped) {
        writeCrashDump(commands, settings.ptr.*, store_opt.ptr, elapsed_opt.ptr, render_state_opt.ptr, "webgpu_device_lost") catch |err| {
            std.log.err("CrashDump: failed to write ({s})", .{@errorName(err)});
        };
        state.ptr.dumped = true;
    }
    state.ptr.last_device_lost = device_lost;
}

fn detectDeviceLost() bool {
    if (builtin.target.cpu.arch.isWasm()) {
        var flag: u32 = 0;
        WasmImports.deviceLost(&flag);
        return flag != 0;
    }
    return false;
}

fn writeCrashDump(
    commands: *Commands,
    settings: CrashDumpSettings,
    store: ?*const metrics.Store,
    elapsed: ?*const time_mod.ElapsedTime,
    render_state_opt: ?*const render_mod.RenderState,
    reason: []const u8,
) !void {
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(commands.allocator);

    const now_ms: i64 = if (builtin.target.cpu.arch.isWasm())
        0
    else blk: {
        const ts = std.Io.Clock.real.now(commands.io.*) catch std.Io.Timestamp.zero;
        break :blk ts.toMilliseconds();
    };
    try appendFmt(
        &buffer,
        commands.allocator,
        "phasor crash dump\n  time_ms={d}\n  target={s}\n  reason={s}\n",
        .{ now_ms, if (builtin.target.cpu.arch.isWasm()) "wasm" else "native", reason },
    );
    if (elapsed) |elapsed_res| {
        try appendFmt(&buffer, commands.allocator, "  elapsed_seconds={d:.3}\n", .{elapsed_res.seconds});
    }

    if (render_state_opt) |state| {
        const stats = render.rendererStats(&state.renderer);
        try appendFmt(
            &buffer,
            commands.allocator,
            "  render_stats mesh={d}/{d} texture={d}/{d} material={d}/{d} sampler={d}/{d}\n",
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

    if (builtin.target.cpu.arch.isWasm()) {
        const mem_bytes: u64 = WasmImports.memoryBytes();
        var js_used: u32 = 0;
        var js_total: u32 = 0;
        WasmImports.jsHeap(&js_used, &js_total);
        var creates: [13]u32 = .{0} ** 13;
        var destroys: [5]u32 = .{0} ** 5;
        WasmImports.webgpuResourceCounts(&creates, &destroys);
        try appendFmt(
            &buffer,
            commands.allocator,
            "  wasm_mem_bytes={d}\n  js_heap_used_mb={d:.2}\n  js_heap_total_mb={d:.2}\n",
            .{
                mem_bytes,
                @as(f64, @floatFromInt(js_used)) / (1024.0 * 1024.0),
                @as(f64, @floatFromInt(js_total)) / (1024.0 * 1024.0),
            },
        );
        try appendFmt(
            &buffer,
            commands.allocator,
            "  webgpu_create buffers={d} textures={d} views={d} samplers={d} bind_groups={d} pipelines={d} encoders={d} passes={d}\n",
            .{ creates[0], creates[1], creates[2], creates[3], creates[4], creates[5], creates[6], creates[7] },
        );
        try appendFmt(
            &buffer,
            commands.allocator,
            "  webgpu_destroy buffers={d} textures={d} samplers={d} bind_groups={d} pipelines={d}\n",
            .{ destroys[0], destroys[1], destroys[2], destroys[3], destroys[4] },
        );
    }

    if (store) |metrics_store| {
        try appendFmt(&buffer, commands.allocator, "  metrics:\n", .{});
        var it = metrics_store.map.iterator();
        while (it.next()) |entry| {
            const sample = entry.value_ptr.*;
            try appendFmt(&buffer, commands.allocator, "    {s} ", .{sample.name});
            try appendMetricValue(&buffer, commands.allocator, sample.value);
            try appendFmt(&buffer, commands.allocator, " {s}\n", .{sample.unit orelse "-"});
        }
    }

    if (builtin.target.cpu.arch.isWasm()) {
        std.log.err("{s}", .{buffer.items});
        return;
    }

    const io = commands.io.*;
    try std.Io.Dir.cwd().createDirPath(io, settings.output_dir);
    var name_buf: [128]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buf, "{s}/crash-{d}.log", .{ settings.output_dir, now_ms });
    var file = try std.Io.Dir.cwd().createFile(io, name, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, buffer.items);
}

fn appendMetricValue(
    buffer: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: metrics.MetricValue,
) !void {
    switch (value) {
        .f64 => |v| try appendFmt(buffer, allocator, "{d:.3}", .{v}),
        .i64 => |v| try appendFmt(buffer, allocator, "{d}", .{v}),
        .u64 => |v| try appendFmt(buffer, allocator, "{d}", .{v}),
        .bool => |v| try appendFmt(buffer, allocator, "{s}", .{if (v) "true" else "false"}),
    }
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

const WasmImports = if (builtin.target.cpu.arch.isWasm()) struct {
    extern "env" fn wasm_memory_bytes() u32;
    extern "env" fn wasm_js_heap(out_used: *u32, out_total: *u32) void;
    extern "env" fn webgpu_device_lost(out_flag: *u32) void;
    extern "env" fn webgpu_resource_counts(out_creates: [*]u32, out_destroys: [*]u32) void;

    pub fn memoryBytes() u64 {
        return @intCast(wasm_memory_bytes());
    }

    pub fn jsHeap(out_used: *u32, out_total: *u32) void {
        wasm_js_heap(out_used, out_total);
    }

    pub fn deviceLost(out_flag: *u32) void {
        webgpu_device_lost(out_flag);
    }

    pub fn webgpuResourceCounts(out_creates: *[13]u32, out_destroys: *[5]u32) void {
        webgpu_resource_counts(out_creates.ptr, out_destroys.ptr);
    }
} else struct {
    pub fn memoryBytes() u64 {
        return 0;
    }
    pub fn jsHeap(_: *u32, _: *u32) void {}
    pub fn deviceLost(out_flag: *u32) void {
        out_flag.* = 0;
    }
    pub fn webgpuResourceCounts(_: *[13]u32, _: *[5]u32) void {}
};
