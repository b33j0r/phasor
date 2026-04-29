//! `TimeModule` updates frame delta, simulation elapsed time, and monotonic runtime resources each frame.
pub const DeltaTime = struct {
    seconds: f64 = 0.0,
};

pub const ElapsedTime = struct {
    seconds: f64 = 0.0,
};

pub const RunTime = struct {
    seconds: f64 = 0.0,
};

pub const SimulationDeltaTime = struct {
    seconds: f64 = 0.0,
};

const LastInstant = struct {
    value: InstantValue,
};

const StartInstant = struct {
    value: InstantValue,
};

const InstantValue = if (builtin.target.cpu.arch.isWasm()) struct {
    ms: f64,
} else std.Io.Clock.Timestamp;

pub fn install(app: *AppCommands, cmds: *Commands) !void {
    const now = try currentInstant();
    try cmds.insertResource(DeltaTime{});
    try cmds.insertResource(ElapsedTime{});
    try cmds.insertResource(RunTime{});
    try cmds.insertResource(SimulationDeltaTime{});
    try cmds.insertResource(LastInstant{ .value = now });
    try cmds.insertResource(StartInstant{ .value = now });
    try app.addSystem("BeforeFrame", updateTimeSystem);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(updateTimeSystem);
}

fn updateTimeSystem(
    res_delta_time: ResMut(DeltaTime),
    res_elapsed_time: ResMut(ElapsedTime),
    res_run_time: ResMut(RunTime),
    r_is_paused: HasResource(Paused),
    res_simulation_delta_time: ResMut(SimulationDeltaTime),
    res_last_instant: ResMut(LastInstant),
    res_start_instant: ResMut(StartInstant),
) void {
    const delta_time = res_delta_time.deref();
    const elapsed_time = res_elapsed_time.deref();
    const run_time = res_run_time.deref();
    const simulation_delta_time = res_simulation_delta_time.deref();
    const last_instant = res_last_instant.deref();
    const now = currentInstant() catch {
        std.log.debug("Failed to get current time instant", .{});
        return;
    };
    const dt_raw = deltaSeconds(last_instant.value, now);
    const dt = sanitizeDelta(dt_raw);
    last_instant.value = now;
    delta_time.seconds = dt;

    if (r_is_paused.value) {
        simulation_delta_time.seconds = 0.0;
    } else {
        simulation_delta_time.seconds = dt;
        elapsed_time.seconds += dt;
    }

    if (builtin.target.cpu.arch.isWasm()) {
        const elapsed_raw = deltaSeconds(res_start_instant.deref().value, now);
        if (std.math.isFinite(elapsed_raw) and elapsed_raw >= run_time.seconds) {
            run_time.seconds = elapsed_raw;
        } else {
            run_time.seconds += dt;
        }
        return;
    }

    run_time.seconds += dt;
}

pub fn setPaused(commands: *Commands, enabled: bool) !void {
    if (enabled) {
        try commands.insertResource(Paused{});
    } else {
        _ = commands.removeResource(Paused);
    }
}

fn currentInstant() !InstantValue {
    if (builtin.target.cpu.arch.isWasm()) {
        return .{ .ms = WasmImports.timeMs() };
    }
    return std.Io.Clock.Timestamp.now(std.Options.debug_io, .awake);
}

fn deltaSeconds(prev: InstantValue, now: InstantValue) f64 {
    if (builtin.target.cpu.arch.isWasm()) {
        const dt_ms = now.ms - prev.ms;
        return dt_ms / 1000.0;
    }
    const dt = prev.durationTo(now);
    return @as(f64, @floatFromInt(dt.raw.nanoseconds)) / std.time.ns_per_s;
}

fn sanitizeDelta(dt: f64) f64 {
    if (!std.math.isFinite(dt)) return 0.0;
    if (dt < 0.0) return 0.0;
    return dt;
}

// Imports
const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");
const ecs = @import("ecs");
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const HasResource = ecs.system_params.HasResource;
const ResMut = ecs.system_params.ResMut;
const schedule = ecs.schedule;

const WasmImports = if (builtin.target.cpu.arch.isWasm()) struct {
    extern "env" fn wasm_time_ms() f64;

    pub fn timeMs() f64 {
        return wasm_time_ms();
    }
} else struct {
    pub fn timeMs() f64 {
        return 0.0;
    }
};

pub const Paused = common.Paused;
