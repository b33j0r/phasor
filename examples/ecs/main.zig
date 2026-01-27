const std = @import("std");
const phasor = @import("phasor");
const ecs = phasor.ecs;
const metrics = phasor.metrics;
const BenchmarkConfig = @import("bench_config.zig").BenchmarkConfig;
const profiles = @import("profiles.zig");

const Position = struct { x: f32, y: f32 };
const Velocity = struct {
    dx: f32,
    dy: f32,
    pub const default = @This(){ .dx = 0, .dy = 0 };
};
const Lifetime = struct {
    seconds: f32,
    pub const default = @This(){ .seconds = 0 };
};

const ParticleTable = struct { index: usize };
const SpawnCounter = struct { value: u64 = 0 };

pub fn main(init: std.process.Init) u8 {
    _ = init;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = ecs.App.init(allocator);
    defer app.deinit();

    app.addSystem(spawnSystem(profiles.sine)) catch return 1;
    app.addSystem(updateSystem()) catch return 1;

    app.world.insertResource(BenchmarkConfig{}) catch return 1;
    app.world.insertResource(SpawnCounter{}) catch return 1;

    const table_index = app.world.dbMut().getOrCreateTable(.{ Position, Velocity, Lifetime }) catch return 1;
    app.world.insertResource(ParticleTable{ .index = table_index }) catch return 1;

    seedInitial(&app.world, table_index) catch return 1;

    const config = app.world.getResource(BenchmarkConfig).?.*;
    app.run(.{ .warmup_frames = config.warmup_frames, .sample_frames = config.sample_frames }) catch return 1;

    if (app.world.getResource(ecs.resources.Metrics)) |m| {
        std.debug.print(
            "frames={} spawned={} removed={} moved={} last_frame_ms={d:.2}\n",
            .{ m.frame, m.spawned, m.removed, m.moved, @as(f64, @floatFromInt(m.frame_ns)) / 1_000_000.0 },
        );
    }

    return 0;
}

fn seedInitial(world: *ecs.World, table_index: usize) !void {
    const config = world.getResource(BenchmarkConfig).?.*;
    var i: usize = 0;
    while (i < config.initial_entities) : (i += 1) {
        _ = try spawnParticle(world, table_index);
    }
}

fn spawnSystem(comptime sampleFn: fn (BenchmarkConfig, u64, f32) i32) ecs.schedule.Schedule.SystemFn {
    return struct {
        fn run(world: *ecs.World) !void {
            const dt = world.getResource(ecs.resources.DeltaTime).?.seconds;
            const frame = world.getResource(ecs.resources.FrameNum).?.value;
            const config = world.getResource(BenchmarkConfig).?.*;
            const table_index = world.getResource(ParticleTable).?.index;

            const delta = sampleFn(config, frame, dt);
            if (delta == 0) return;

            const table = world.dbMut().tableMut(table_index);
            const current = table.len();

            if (delta > 0) {
                const max_add = if (current < config.max_entities) config.max_entities - current else 0;
                const to_add = @min(@as(usize, @intCast(delta)), max_add);
                var i: usize = 0;
                while (i < to_add) : (i += 1) {
                    _ = try spawnParticle(world, table_index);
                    if (world.getResourceMut(ecs.resources.Metrics)) |m| m.spawned += 1;
                }
            } else {
                const to_remove = @min(@as(usize, @intCast(-delta)), current);
                var i: usize = 0;
                while (i < to_remove) : (i += 1) {
                    const last_index = table.len() - 1;
                    const id = table.entityIdAt(last_index).?;
                    try world.dbMut().removeEntity(id);
                    if (world.getResourceMut(ecs.resources.Metrics)) |m| m.removed += 1;
                }
            }
        }
    }.run;
}

fn updateSystem() ecs.schedule.Schedule.SystemFn {
    return struct {
        fn run(world: *ecs.World) !void {
            const dt = world.getResource(ecs.resources.DeltaTime).?.seconds;
            const config = world.getResource(BenchmarkConfig).?.*;
            const table_index = world.getResource(ParticleTable).?.index;

            var i: usize = 0;
            while (i < world.dbMut().tableMut(table_index).len()) {
                var db = world.dbMut();
                var table = db.tableMut(table_index);
                const id = table.entityIdAt(i).?;
                const pos = table.getComponentPtr(i, Position).?;
                const vel = table.getComponentPtr(i, Velocity).?;
                const life = table.getComponentPtr(i, Lifetime).?;

                pos.x += vel.dx * dt;
                pos.y += vel.dy * dt;
                vel.dy += config.gravity * dt;
                life.seconds -= dt;

                if (life.seconds <= 0) {
                    try db.removeEntity(id);
                    if (world.getResourceMut(ecs.resources.Metrics)) |m| m.removed += 1;
                } else {
                    i += 1;
                }
            }
        }
    }.run;
}

fn spawnParticle(world: *ecs.World, table_index: usize) !phasor.db.Entity.Id {
    const counter = world.getResourceMut(SpawnCounter).?;

    const angle = @as(f32, @floatFromInt(counter.value % 360)) * (std.math.pi / 180.0);
    counter.value += 1;

    const speed: f32 = 25.0;
    const vel = Velocity{ .dx = @cos(angle) * speed, .dy = @sin(angle) * speed };
    const life = Lifetime{ .seconds = 2.0 + @as(f32, @floatFromInt(counter.value % 100)) / 100.0 };

    return world.dbMut().createEntityInTable(table_index, .{
        Position{ .x = 0, .y = 0 },
        vel,
        life,
    });
}
