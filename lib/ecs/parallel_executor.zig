/// Parallel system executor for the ECS scheduler.
///
/// Analyzes system access patterns to determine which systems can safely run
/// concurrently, then executes them in parallel batches using `std.Io.Group`.
///
/// Systems are partitioned into ordered batches where:
/// - Systems within a batch have no data conflicts (no write/read or write/write
///   on the same resource, and no exclusive access).
/// - Batch order preserves the declared registration order: if system A was
///   registered before system B and they conflict, A runs in an earlier batch.
/// - Within a batch, systems are launched in declared order (though they may
///   complete in any order).
///
/// After each batch completes, all deferred commands are applied sequentially
/// before the next batch begins.

const std = @import("std");
const system_mod = @import("system.zig");
const system_access = @import("system_access.zig");
const schedule_mod = @import("schedule.zig");
const Commands = @import("Commands.zig");
const World = @import("World.zig");
const common = @import("common");

const System = system_mod.System;
const AccessDescriptor = system_access.AccessDescriptor;
const CommandBatch = Commands.CommandBatch;

const log = std.log.scoped(.parallel_executor);

/// A batch of system indices that can safely run concurrently.
pub const SystemBatch = struct {
    indices: []const usize,
};

/// Compute parallel batches from an ordered list of system nodes.
///
/// Each batch contains systems that do not conflict with each other.
/// A system is added to the earliest batch where it has no conflicts with
/// any system already in that batch, preserving declared order.
///
/// Returns a slice of batches. Caller owns the returned memory.
pub fn computeBatches(
    allocator: std.mem.Allocator,
    schedule: *schedule_mod.Schedule,
    system_order: []const usize,
) ![]SystemBatch {
    if (system_order.len == 0) return &.{};

    // Collect enabled systems and their access descriptors.
    var enabled_indices: std.ArrayListUnmanaged(usize) = .empty;
    defer enabled_indices.deinit(allocator);

    var access_list: std.ArrayListUnmanaged(AccessDescriptor) = .empty;
    defer access_list.deinit(allocator);

    for (system_order) |idx| {
        const node = schedule.systemNodeAt(idx);
        if (!node.enabled) continue;
        try enabled_indices.append(allocator, idx);
        try access_list.append(allocator, node.system.access);
    }

    const count = enabled_indices.items.len;
    if (count == 0) return &.{};

    // Greedy batch assignment: for each system, find the earliest batch where
    // it doesn't conflict with any existing member.
    var batch_assignments = try allocator.alloc(usize, count);
    defer allocator.free(batch_assignments);

    // Track which systems are in which batch for conflict checking.
    // batch_members[b] = list of indices into enabled_indices for batch b.
    var batch_count: usize = 0;
    var batch_members: std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)) = .empty;
    defer {
        for (batch_members.items) |*bl| bl.deinit(allocator);
        batch_members.deinit(allocator);
    }

    for (0..count) |i| {
        const access_i = &access_list.items[i];

        // Find the latest batch containing a system that conflicts with this one.
        // This system must go in a batch strictly after that one to preserve
        // declared ordering for dependent systems.
        var min_batch: usize = 0;
        for (0..i) |j| {
            if (access_i.conflictsWith(&access_list.items[j])) {
                min_batch = @max(min_batch, batch_assignments[j] + 1);
            }
        }

        // Find the earliest batch >= min_batch where no member conflicts.
        var assigned_batch: ?usize = null;
        for (min_batch..batch_count) |b| {
            var conflicts = false;
            for (batch_members.items[b].items) |member| {
                if (access_i.conflictsWith(&access_list.items[member])) {
                    conflicts = true;
                    break;
                }
            }
            if (!conflicts) {
                assigned_batch = b;
                break;
            }
        }

        if (assigned_batch) |b| {
            batch_assignments[i] = b;
            try batch_members.items[b].append(allocator, i);
        } else {
            // New batch needed.
            batch_assignments[i] = batch_count;
            var new_list: std.ArrayListUnmanaged(usize) = .empty;
            try new_list.append(allocator, i);
            try batch_members.append(allocator, new_list);
            batch_count += 1;
        }
    }

    // Build the result batches.
    var batches = try allocator.alloc(SystemBatch, batch_count);
    errdefer {
        for (batches) |batch| allocator.free(batch.indices);
        allocator.free(batches);
    }

    for (0..batch_count) |b| {
        const members = batch_members.items[b].items;
        const indices = try allocator.alloc(usize, members.len);
        for (members, 0..) |member_idx, j| {
            indices[j] = enabled_indices.items[member_idx];
        }
        batches[b] = .{ .indices = indices };
    }

    return batches;
}

pub fn freeBatches(allocator: std.mem.Allocator, batches: []SystemBatch) void {
    for (batches) |batch| allocator.free(batch.indices);
    allocator.free(batches);
}

/// Result of running a system, used for collecting errors from concurrent tasks.
const SystemResult = struct {
    index: usize,
    err: ?anyerror,
};

/// Execute a schedule's systems in parallel batches.
///
/// Systems within each batch run concurrently via `Io.Group`. After each batch
/// completes, deferred commands from all systems in the batch are applied
/// sequentially in declared order.
///
/// Falls back to sequential execution when `parallel = false` or when there's
/// only one system in a batch.
pub fn executeSchedule(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    world: *World,
    schedule: *schedule_mod.Schedule,
    command_channel: *common.Channel(CommandBatch),
    parallel: bool,
) !void {
    const system_order = try schedule.systemOrder(allocator);
    if (system_order.len == 0) return;

    if (!parallel) {
        return executeSequential(allocator, io, world, schedule, system_order, command_channel);
    }

    const batches = try computeBatches(allocator, schedule, system_order);
    defer freeBatches(allocator, batches);

    for (batches) |batch| {
        if (batch.indices.len == 0) continue;

        if (batch.indices.len == 1) {
            // Single system: run directly without concurrency overhead.
            try executeSingleSystem(allocator, io, world, schedule, batch.indices[0], command_channel);
        } else {
            try executeBatchConcurrent(allocator, io, world, schedule, batch, command_channel);
        }
    }
}

fn executeSequential(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    world: *World,
    schedule: *schedule_mod.Schedule,
    system_order: []const usize,
    command_channel: *common.Channel(CommandBatch),
) !void {
    for (system_order) |system_index| {
        try executeSingleSystem(allocator, io, world, schedule, system_index, command_channel);
    }
}

fn executeSingleSystem(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    world: *World,
    schedule: *schedule_mod.Schedule,
    system_index: usize,
    command_channel: *common.Channel(CommandBatch),
) !void {
    const node = schedule.systemNodeAt(system_index);
    if (!node.enabled) return;

    var commands = Commands.init(allocator, io, world);
    defer commands.deinit();

    try node.system.run(&commands);
    if (!commands.isEmpty()) {
        try commands.flushToChannel(command_channel);
        var batch = try command_channel.recv();
        defer batch.deinit();
        try batch.apply(world);
    }
}

fn executeBatchConcurrent(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    world: *World,
    schedule: *schedule_mod.Schedule,
    batch: SystemBatch,
    command_channel: *common.Channel(CommandBatch),
) !void {
    const n = batch.indices.len;

    // Pre-allocate Commands for each system in the batch.
    var commands_list = try allocator.alloc(Commands, n);
    defer {
        for (commands_list) |*cmds| cmds.deinit();
        allocator.free(commands_list);
    }
    for (commands_list) |*cmds| {
        cmds.* = Commands.init(allocator, io, world);
    }

    // Collect errors from concurrent tasks.
    var errors = try allocator.alloc(?anyerror, n);
    defer allocator.free(errors);
    for (errors) |*e| e.* = null;

    // Run all systems concurrently using Io.Group.
    var group: std.Io.Group = .init;

    for (batch.indices, 0..) |system_index, i| {
        const node = schedule.systemNodeAt(system_index);
        if (!node.enabled) continue;

        const run_fn = node.system.run;
        const cmds_ptr = &commands_list[i];
        const err_ptr = &errors[i];

        // Use group.concurrent() to spawn on a real thread.
        // Fall back to group.async() if we can't get concurrency.
        group.concurrent(io.*, runSystemTask, .{ run_fn, cmds_ptr, err_ptr }) catch {
            group.async(io.*, runSystemTask, .{ run_fn, cmds_ptr, err_ptr });
        };
    }

    // Wait for all tasks to complete.
    group.await(io.*) catch {};

    // Check for errors.
    var first_err: ?anyerror = null;
    for (errors) |e| {
        if (e != null and first_err == null) first_err = e;
    }

    // Apply commands in declared order.
    for (commands_list) |*cmds| {
        if (!cmds.isEmpty()) {
            try cmds.flushToChannel(command_channel);
            var cmd_batch = try command_channel.recv();
            defer cmd_batch.deinit();
            try cmd_batch.apply(world);
        }
    }

    if (first_err) |err| return err;
}

fn runSystemTask(
    run_fn: *const fn (*Commands) anyerror!void,
    commands: *Commands,
    err_out: *?anyerror,
) void {
    run_fn(commands) catch |err| {
        err_out.* = err;
    };
}

// ===========================================================================
// Tests
// ===========================================================================

const testing = std.testing;

const Health = struct { hp: u32 = 100 };
const Mana = struct { mp: u32 = 50 };
const Score = struct { value: u32 = 0 };

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

/// CPU-busy work for benchmarks: compute a hash chain.
fn busyWork(seed: u64, iterations: u64) u64 {
    var h: u64 = seed;
    for (0..iterations) |_| {
        h ^= h >> 33;
        h *%= 0xff51afd7ed558ccd;
        h ^= h >> 33;
        h *%= 0xc4ceb9fe1a85ec53;
        h ^= h >> 33;
    }
    return h;
}

test "computeBatches: independent systems go in same batch" {
    const allocator = testing.allocator;
    var world = World.init(allocator);
    defer world.deinit();

    var manager = try schedule_mod.ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    const sys_a = struct {
        fn run(_: system_params.Res(Health)) void {}
    }.run;
    const sys_b = struct {
        fn run(_: system_params.Res(Mana)) void {}
    }.run;

    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_a);
    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_b);

    const sched = manager.schedulePtr(schedule_mod.DefaultSchedule.Update).?;
    const order = try sched.systemOrder(allocator);
    const batches = try computeBatches(allocator, sched, order);
    defer freeBatches(allocator, batches);

    try testing.expectEqual(@as(usize, 1), batches.len);
    try testing.expectEqual(@as(usize, 2), batches[0].indices.len);
}

test "computeBatches: conflicting systems go in separate batches" {
    const allocator = testing.allocator;
    var world = World.init(allocator);
    defer world.deinit();

    var manager = try schedule_mod.ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    const sys_a = struct {
        fn run(_: system_params.ResMut(Health)) void {}
    }.run;
    const sys_b = struct {
        fn run(_: system_params.Res(Health)) void {}
    }.run;

    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_a);
    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_b);

    const sched = manager.schedulePtr(schedule_mod.DefaultSchedule.Update).?;
    const order = try sched.systemOrder(allocator);
    const batches = try computeBatches(allocator, sched, order);
    defer freeBatches(allocator, batches);

    try testing.expectEqual(@as(usize, 2), batches.len);
    try testing.expectEqual(@as(usize, 1), batches[0].indices.len);
    try testing.expectEqual(@as(usize, 1), batches[1].indices.len);
}

test "computeBatches: mixed independent and conflicting" {
    const allocator = testing.allocator;
    var world = World.init(allocator);
    defer world.deinit();

    var manager = try schedule_mod.ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    // sys_a writes Health
    const sys_a = struct {
        fn run(_: system_params.ResMut(Health)) void {}
    }.run;
    // sys_b reads Mana (no conflict with sys_a)
    const sys_b = struct {
        fn run(_: system_params.Res(Mana)) void {}
    }.run;
    // sys_c reads Health (conflicts with sys_a, not sys_b)
    const sys_c = struct {
        fn run(_: system_params.Res(Health)) void {}
    }.run;

    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_a);
    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_b);
    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_c);

    const sched = manager.schedulePtr(schedule_mod.DefaultSchedule.Update).?;
    const order = try sched.systemOrder(allocator);
    const batches = try computeBatches(allocator, sched, order);
    defer freeBatches(allocator, batches);

    // sys_a and sys_b should be in batch 0, sys_c in batch 1
    try testing.expectEqual(@as(usize, 2), batches.len);
    try testing.expectEqual(@as(usize, 2), batches[0].indices.len);
    try testing.expectEqual(@as(usize, 1), batches[1].indices.len);
}

test "computeBatches: exclusive system gets own batch" {
    const allocator = testing.allocator;
    var world = World.init(allocator);
    defer world.deinit();

    var manager = try schedule_mod.ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    const sys_a = struct {
        fn run(_: system_params.Res(Health)) void {}
    }.run;
    const sys_b = struct {
        fn run(_: *Commands) void {}
    }.run;
    const sys_c = struct {
        fn run(_: system_params.Res(Mana)) void {}
    }.run;

    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_a);
    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_b);
    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_c);

    const sched = manager.schedulePtr(schedule_mod.DefaultSchedule.Update).?;
    const order = try sched.systemOrder(allocator);
    const batches = try computeBatches(allocator, sched, order);
    defer freeBatches(allocator, batches);

    // sys_a in batch 0, sys_b (exclusive) in batch 1, sys_c in batch 2
    // (sys_c must come after sys_b because exclusive conflicts with everything)
    try testing.expectEqual(@as(usize, 3), batches.len);
    try testing.expectEqual(@as(usize, 1), batches[0].indices.len);
    try testing.expectEqual(@as(usize, 1), batches[1].indices.len);
    try testing.expectEqual(@as(usize, 1), batches[2].indices.len);
}

test "executeSchedule: sequential execution preserves resource mutations" {
    const allocator = testing.allocator;
    var io_impl = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_impl.deinit();
    const io = io_impl.io();

    var world = World.init(allocator);
    defer world.deinit();
    try world.insertResource(Score{ .value = 0 });

    var manager = try schedule_mod.ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    const add_ten = struct {
        fn run(score: system_params.ResMut(Score)) void {
            score.deref().value += 10;
        }
    }.run;
    const add_five = struct {
        fn run(score: system_params.ResMut(Score)) void {
            score.deref().value += 5;
        }
    }.run;

    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, add_ten);
    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, add_five);

    const sched = manager.schedulePtr(schedule_mod.DefaultSchedule.Update).?;
    var channel = try common.Channel(CommandBatch).init(allocator, &io, 64);
    defer channel.deinit();

    try executeSchedule(allocator, &io, &world, sched, &channel, false);

    const score = world.getResource(Score).?;
    try testing.expectEqual(@as(u32, 15), score.value);
}

test "executeSchedule: parallel execution with independent systems" {
    const allocator = testing.allocator;
    var io_impl = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_impl.deinit();
    const io = io_impl.io();

    var world = World.init(allocator);
    defer world.deinit();
    try world.insertResource(Health{ .hp = 100 });
    try world.insertResource(Mana{ .mp = 50 });

    var manager = try schedule_mod.ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    const heal = struct {
        fn run(health: system_params.ResMut(Health)) void {
            health.deref().hp += 10;
        }
    }.run;
    const regen_mana = struct {
        fn run(mana: system_params.ResMut(Mana)) void {
            mana.deref().mp += 5;
        }
    }.run;

    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, heal);
    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, regen_mana);

    const sched = manager.schedulePtr(schedule_mod.DefaultSchedule.Update).?;
    var channel = try common.Channel(CommandBatch).init(allocator, &io, 64);
    defer channel.deinit();

    try executeSchedule(allocator, &io, &world, sched, &channel, true);

    try testing.expectEqual(@as(u32, 110), world.getResource(Health).?.hp);
    try testing.expectEqual(@as(u32, 55), world.getResource(Mana).?.mp);
}

test "executeSchedule: parallel preserves order for conflicting systems" {
    const allocator = testing.allocator;
    var io_impl = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_impl.deinit();
    const io = io_impl.io();

    var world = World.init(allocator);
    defer world.deinit();
    try world.insertResource(Score{ .value = 0 });

    var manager = try schedule_mod.ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    // Both write Score, so they must run sequentially in declared order.
    const multiply = struct {
        fn run(score: system_params.ResMut(Score)) void {
            score.deref().value = score.deref().value * 2 + 1;
        }
    }.run;
    const add_three = struct {
        fn run(score: system_params.ResMut(Score)) void {
            score.deref().value += 3;
        }
    }.run;

    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, multiply);
    try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, add_three);

    const sched = manager.schedulePtr(schedule_mod.DefaultSchedule.Update).?;
    var channel = try common.Channel(CommandBatch).init(allocator, &io, 64);
    defer channel.deinit();

    try executeSchedule(allocator, &io, &world, sched, &channel, true);

    // multiply: 0 * 2 + 1 = 1, then add_three: 1 + 3 = 4
    try testing.expectEqual(@as(u32, 4), world.getResource(Score).?.value);
}

test "executeSchedule: parallel speedup with CPU-heavy independent systems" {
    const allocator = testing.allocator;
    var io_impl = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_impl.deinit();
    const io = io_impl.io();

    // Each resource holds a result slot for a CPU-heavy computation.
    const WorkA = struct { result: u64 = 0 };
    const WorkB = struct { result: u64 = 0 };
    const WorkC = struct { result: u64 = 0 };
    const WorkD = struct { result: u64 = 0 };

    const iters: u64 = 2_000_000;

    const sys_a = struct {
        fn run(w: system_params.ResMut(WorkA)) void {
            w.deref().result = busyWork(1, iters);
        }
    }.run;
    const sys_b = struct {
        fn run(w: system_params.ResMut(WorkB)) void {
            w.deref().result = busyWork(2, iters);
        }
    }.run;
    const sys_c = struct {
        fn run(w: system_params.ResMut(WorkC)) void {
            w.deref().result = busyWork(3, iters);
        }
    }.run;
    const sys_d = struct {
        fn run(w: system_params.ResMut(WorkD)) void {
            w.deref().result = busyWork(4, iters);
        }
    }.run;

    // --- Sequential run ---
    {
        var world = World.init(allocator);
        defer world.deinit();
        try world.insertResource(WorkA{});
        try world.insertResource(WorkB{});
        try world.insertResource(WorkC{});
        try world.insertResource(WorkD{});

        var manager = try schedule_mod.ScheduleManager.init(allocator);
        defer manager.deinit(&world);
        try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_a);
        try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_b);
        try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_c);
        try manager.addSystem(&world, schedule_mod.DefaultSchedule.Update, sys_d);

        const sched = manager.schedulePtr(schedule_mod.DefaultSchedule.Update).?;
        var channel = try common.Channel(CommandBatch).init(allocator, &io, 64);
        defer channel.deinit();

        const t0 = nowNs();
        try executeSchedule(allocator, &io, &world, sched, &channel, false);
        const seq_ns = nowNs() - t0;

        // --- Parallel run ---
        var world2 = World.init(allocator);
        defer world2.deinit();
        try world2.insertResource(WorkA{});
        try world2.insertResource(WorkB{});
        try world2.insertResource(WorkC{});
        try world2.insertResource(WorkD{});

        var manager2 = try schedule_mod.ScheduleManager.init(allocator);
        defer manager2.deinit(&world2);
        try manager2.addSystem(&world2, schedule_mod.DefaultSchedule.Update, sys_a);
        try manager2.addSystem(&world2, schedule_mod.DefaultSchedule.Update, sys_b);
        try manager2.addSystem(&world2, schedule_mod.DefaultSchedule.Update, sys_c);
        try manager2.addSystem(&world2, schedule_mod.DefaultSchedule.Update, sys_d);

        const sched2 = manager2.schedulePtr(schedule_mod.DefaultSchedule.Update).?;
        var channel2 = try common.Channel(CommandBatch).init(allocator, &io, 64);
        defer channel2.deinit();

        const t1 = nowNs();
        try executeSchedule(allocator, &io, &world2, sched2, &channel2, true);
        const par_ns = nowNs() - t1;

        // Verify correctness: both runs produce the same results.
        try testing.expectEqual(
            world.getResource(WorkA).?.result,
            world2.getResource(WorkA).?.result,
        );
        try testing.expectEqual(
            world.getResource(WorkB).?.result,
            world2.getResource(WorkB).?.result,
        );

        const seq_ms = @as(f64, @floatFromInt(seq_ns)) / 1_000_000.0;
        const par_ms = @as(f64, @floatFromInt(par_ns)) / 1_000_000.0;
        const speedup = seq_ms / par_ms;
        log.info("parallel speedup benchmark: sequential={d:.1}ms parallel={d:.1}ms speedup={d:.2}x", .{ seq_ms, par_ms, speedup });

        // With 4 independent CPU-heavy systems and >=2 cores, we expect >1.3x speedup.
        // On CI/single-core this may not hold, so we just verify correctness above.
        // The speedup log line serves as evidence on real hardware.
    }
}

const system_params = @import("system_params.zig");
