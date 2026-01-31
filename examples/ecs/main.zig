const std_options = std.Options{
    .log_level = std.log.Level.debug,
};

const Position = struct { x: f32, y: f32 };
const Velocity = struct {
    dx: f32,
    dy: f32,
    pub const default = @This(){ .dx = 0, .dy = 0 };
};

const SpawnerTag = struct {};
const ParticleTag = struct {};
const ParticleTable = struct { index: usize };
const SpawnCounter = struct { value: u64 = 0 };
const ExitRequested = struct { code: u8 };

const Boot = struct {
    pub fn enter(_: *Boot, ctx: *PhaseContext) !void {
        var commands = ecs.Commands.init(ctx.allocator, ctx.io, ctx.world);
        defer commands.deinit();
        try setupResources(&commands);
        if (!commands.isEmpty()) {
            try commands.apply();
        }
        try ctx.addSystem("Update", advanceToRunning);
    }

    fn advanceToRunning(commands: *ecs.Commands) !void {
        try commands.insertResource(Phases.NextPhase{ .phase = AppPhases{ .Running = .{} } });
    }

    fn setupResources(commands: *ecs.Commands) !void {
        if (!commands.hasResource(SpawnCounter)) {
            try commands.insertResource(SpawnCounter{ .value = 0 });
            _ = try commands.createEntity(.{
                SpawnerTag{},
                StopwatchTimer{},
                CountdownTimer{ .remaining = 3.0 },
            });
        }
    }
};

const Running = struct {
    pub fn enter(_: *Running, ctx: *PhaseContext) !void {
        try ctx.addSystem("Update", spawnParticles);
        try ctx.addSystem("Update", integratePhysics);
        try ctx.addSystem("Update", requestExitAfterCountdown);
        try ctx.addSystem("Update", handleExitEvent);
    }

    fn spawnParticles(commands: *ecs.Commands, spawner_query: Query(.{ SpawnerTag, StopwatchTimer })) !void {
        const counter = commands.getResourceMut(SpawnCounter) orelse return;
        var spawner_it = spawner_query.iterator();
        const spawner_row = spawner_it.next() orelse return;

        counter.value += 1;
        const stopwatch = spawner_row.get(StopwatchTimer).?;
        if (counter.value % 100 == 0) {
            std.log.debug("Spawning particle #{d} ({d})", .{ counter.value, stopwatch.elapsed });
        }

        _ = try commands.createEntity(.{
            ParticleTag{},
            Position{ .x = @floatFromInt(counter.value), .y = 0 },
            Velocity{ .dx = 1, .dy = 0 },
        });
    }

    fn integratePhysics(dt: Res(DeltaTime), query: Query(.{ Position, Velocity, ParticleTag })) !void {
        const step: f32 = @floatCast(dt.deref().seconds);
        var it = query.iterator();
        while (it.next()) |row| {
            const pos = row.get(Position).?;
            const vel = row.get(Velocity).?;
            pos.x += vel.dx * step;
            pos.y += vel.dy * step;
        }
    }

    fn requestExitAfterCountdown(writer: EventWriter(ExitRequested), spawners: Query(.{ SpawnerTag, CountdownTimer })) !void {
        var spawner_it = spawners.iterator();
        const spawner_row = spawner_it.next() orelse return;
        const spawner_timer = spawner_row.get(CountdownTimer).?;
        if (spawner_timer.finished) {
            std.log.debug("Exit countdown finished, exiting.", .{});
            try writer.send(.{ .code = 0 });
        }
    }

    fn handleExitEvent(commands: *ecs.Commands, reader: EventReader(ExitRequested)) !void {
        while (reader.tryRecv()) |evt| {
            _ = evt;
            try commands.insertResource(Phases.NextPhase{ .phase = AppPhases{ .Quit = .{} } });
        }
    }
};

const Quit = struct {
    pub fn enter(_: *Quit, ctx: *PhaseContext) !void {
        try ctx.world.insertResource(resources.Exit{ .code = 0 });
    }
};

const AppPhases = union(enum) {
    Boot: Boot,
    Running: Running,
    Quit: Quit,
};

const Phases = modules.PhasesModule.Definition(AppPhases, AppPhases{ .Boot = .{} });

pub fn main(init: std.process.Init) !u8 {
    const allocator = std.heap.c_allocator;

    var app = try ecs.App.init(allocator, &init.io);
    defer app.deinit();

    var commands = ecs.Commands.init(allocator, app.io, &app.world);
    defer commands.deinit();
    try commands.registerEvent(ExitRequested, 8);
    if (!commands.isEmpty()) {
        try commands.apply();
    }
    try app.installModule(modules.TimeModule);
    try app.installModule(modules.TimerModule);
    try app.installModule(Phases);

    return try app.run();
}

// Imports
const std = @import("std");
const phasor = @import("phasor");
const ecs = phasor.ecs;
const resources = ecs.resources;
const modules = phasor.modules;
const PhaseContext = modules.PhasesModule.PhaseContext;
const DeltaTime = modules.TimeModule.DeltaTime;
const CountdownTimer = modules.TimerModule.CountdownTimer;
const StopwatchTimer = modules.TimerModule.StopwatchTimer;
const schedule = ecs.schedule;
const system_params = ecs.system_params;
const Query = system_params.Query;
const Res = system_params.Res;
const events = ecs.events;
const Events = events.Events;
const EventWriter = events.EventWriter;
const EventReader = events.EventReader;
