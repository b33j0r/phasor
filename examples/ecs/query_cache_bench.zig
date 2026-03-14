const std = @import("std");
const phasor = @import("phasor");
const db = phasor.db;
const fixtures = phasor.common.fixtures;

pub const std_options = phasor.common.logging.stdOptions(.info);

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var database = db.Database.init(allocator);
    defer database.deinit();

    try populateTables(&database);

    const Spec = db.QuerySpec.Spec(.{ fixtures.Position, db.QuerySpec.Without(fixtures.Health) });
    const iterations: usize = 200_000;

    var checksum: usize = 0;

    var uncached_timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const table_indices = try database.queryTableIndicesUncached(Spec);
        checksum +%= table_indices.len;
        if (table_indices.len > 0) allocator.free(table_indices);
    }
    const uncached_ns = uncached_timer.read();

    _ = try database.queryTableIndices(Spec);
    var cached_timer = try std.time.Timer.start();
    i = 0;
    while (i < iterations) : (i += 1) {
        const table_indices = try database.queryTableIndices(Spec);
        checksum +%= table_indices.len;
    }
    const cached_ns = cached_timer.read();

    const uncached_per_query = @as(f64, @floatFromInt(uncached_ns)) / @as(f64, @floatFromInt(iterations));
    const cached_per_query = @as(f64, @floatFromInt(cached_ns)) / @as(f64, @floatFromInt(iterations));
    const speedup = uncached_per_query / cached_per_query;

    std.log.info(
        "ecs_query_cache_bench: tables={d} iterations={d} uncached_ns_per_query={d:.2} cached_ns_per_query={d:.2} speedup={d:.2}x checksum={d}",
        .{ database.tableCount(), iterations, uncached_per_query, cached_per_query, speedup, checksum },
    );

    if (speedup < 1.50) {
        std.log.err("ecs_query_cache_bench: FAIL speedup below required threshold (1.50x)", .{});
        return error.BenchmarkRegression;
    }
}

fn populateTables(database: *db.Database) !void {
    _ = try database.createEntityWithId(1, .{fixtures.Position{ .x = 1, .y = 1 }});
    _ = try database.createEntityWithId(2, .{ fixtures.Position{ .x = 2, .y = 2 }, fixtures.Velocity{ .dx = 1, .dy = 1 } });
    _ = try database.createEntityWithId(3, .{ fixtures.Position{ .x = 3, .y = 3 }, fixtures.Health{ .hp = 10 } });
    _ = try database.createEntityWithId(4, .{ fixtures.Position{ .x = 4, .y = 4 }, fixtures.Tag{} });
    _ = try database.createEntityWithId(5, .{ fixtures.Position{ .x = 5, .y = 5 }, fixtures.ShipIsOnFire{} });
    _ = try database.createEntityWithId(6, .{ fixtures.Position{ .x = 6, .y = 6 }, fixtures.State.active });
    _ = try database.createEntityWithId(7, .{ fixtures.Position{ .x = 7, .y = 7 }, fixtures.Velocity{ .dx = 1, .dy = 1 }, fixtures.Health{ .hp = 10 } });
    _ = try database.createEntityWithId(8, .{ fixtures.Position{ .x = 8, .y = 8 }, fixtures.Velocity{ .dx = 1, .dy = 1 }, fixtures.Tag{} });
    _ = try database.createEntityWithId(9, .{ fixtures.Position{ .x = 9, .y = 9 }, fixtures.Velocity{ .dx = 1, .dy = 1 }, fixtures.ShipIsOnFire{} });
    _ = try database.createEntityWithId(10, .{ fixtures.Position{ .x = 10, .y = 10 }, fixtures.Velocity{ .dx = 1, .dy = 1 }, fixtures.State.idle });
    _ = try database.createEntityWithId(11, .{ fixtures.Position{ .x = 11, .y = 11 }, fixtures.Health{ .hp = 10 }, fixtures.Tag{} });
    _ = try database.createEntityWithId(12, .{ fixtures.Position{ .x = 12, .y = 12 }, fixtures.Health{ .hp = 10 }, fixtures.ShipIsOnFire{} });
    _ = try database.createEntityWithId(13, .{ fixtures.Position{ .x = 13, .y = 13 }, fixtures.Health{ .hp = 10 }, fixtures.State.paused });
    _ = try database.createEntityWithId(14, .{ fixtures.Position{ .x = 14, .y = 14 }, fixtures.Tag{}, fixtures.ShipIsOnFire{} });
    _ = try database.createEntityWithId(15, .{ fixtures.Position{ .x = 15, .y = 15 }, fixtures.Tag{}, fixtures.State.active });
    _ = try database.createEntityWithId(16, .{ fixtures.Position{ .x = 16, .y = 16 }, fixtures.ShipIsOnFire{}, fixtures.State.idle });

    var id: db.Entity.Id = 17;
    while (id < 30_000) : (id += 1) {
        switch (id % 16) {
            0 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 1 }, fixtures.Velocity{ .dx = 1, .dy = 1 } }),
            1 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 2 }, fixtures.Health{ .hp = 10 } }),
            2 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 3 }, fixtures.Tag{} }),
            3 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 4 }, fixtures.ShipIsOnFire{} }),
            4 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 5 }, fixtures.State.idle }),
            5 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 6 }, fixtures.Velocity{ .dx = 2, .dy = 2 }, fixtures.Tag{} }),
            6 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 7 }, fixtures.Velocity{ .dx = 2, .dy = 2 }, fixtures.ShipIsOnFire{} }),
            7 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 8 }, fixtures.Velocity{ .dx = 2, .dy = 2 }, fixtures.Health{ .hp = 20 } }),
            8 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 9 }, fixtures.Health{ .hp = 20 }, fixtures.Tag{} }),
            9 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 10 }, fixtures.Health{ .hp = 20 }, fixtures.ShipIsOnFire{} }),
            10 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 11 }, fixtures.Tag{}, fixtures.ShipIsOnFire{} }),
            11 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 12 }, fixtures.Tag{}, fixtures.State.active }),
            12 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 13 }, fixtures.ShipIsOnFire{}, fixtures.State.paused }),
            13 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 14 }, fixtures.Velocity{ .dx = 2, .dy = 2 }, fixtures.State.active }),
            14 => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 15 }, fixtures.Health{ .hp = 20 }, fixtures.State.idle }),
            else => _ = try database.createEntityWithId(id, .{ fixtures.Position{ .x = @floatFromInt(id), .y = 16 }, fixtures.Velocity{ .dx = 1, .dy = 1 }, fixtures.Health{ .hp = 5 }, fixtures.Tag{} }),
        }
    }
}
