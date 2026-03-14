const common = @import("common");
const ecs = @import("ecs");
const backend = @import("backend.zig");
const resources = @import("resources.zig");
const events = @import("events.zig");

pub const PhysicsSchedules = struct {
    pub const SyncIn = "PhysicsSyncIn";
    pub const Step = "PhysicsStep";
    pub const Events = "PhysicsEvents";
    pub const SyncOut = "PhysicsSyncOut";
};

pub const PhysicsModule = struct {
    config: resources.Config = .{},

    pub fn install(self: *const @This(), app: *ecs.AppCommands, commands: *ecs.Commands) !void {
        try ensureScheduleBetween(app, ecs.schedule.DefaultSchedule.BeforeFrame, PhysicsSchedules.SyncIn, ecs.schedule.DefaultSchedule.Update);
        try ensureScheduleBetween(app, PhysicsSchedules.SyncIn, PhysicsSchedules.Step, ecs.schedule.DefaultSchedule.Update);
        try ensureScheduleBetween(app, PhysicsSchedules.Step, PhysicsSchedules.Events, ecs.schedule.DefaultSchedule.Update);
        try ensureScheduleBetween(app, PhysicsSchedules.Events, PhysicsSchedules.SyncOut, ecs.schedule.DefaultSchedule.Update);

        if (!commands.hasResource(resources.Config)) {
            try commands.insertResource(self.config);
        }
        if (!commands.hasResource(resources.Stats)) {
            try commands.insertResource(resources.Stats{});
        }
        if (!commands.hasResource(resources.StepState)) {
            try commands.insertResource(resources.StepState{});
        }
        if (!commands.hasResource(backend.World)) {
            var world = try backend.World.init(commands.allocator, self.config);
            errdefer world.deinit(commands.allocator);
            try commands.insertResource(world);
        }

        try commands.registerEvent(events.ContactBegan, 128);
        try commands.registerEvent(events.ContactEnded, 128);
        try commands.registerEvent(events.TriggerEntered, 128);
        try commands.registerEvent(events.TriggerExited, 128);

        try app.addSystem(PhysicsSchedules.SyncIn, syncInSystem);
        try app.addSystem(PhysicsSchedules.Step, stepSystem);
        try app.addSystem(PhysicsSchedules.Events, eventsSystem);
        try app.addSystem(PhysicsSchedules.SyncOut, syncOutSystem);
    }

    pub fn uninstall(_: *const @This(), app: *ecs.AppCommands, commands: *ecs.Commands) void {
        app.removeSystem(syncInSystem);
        app.removeSystem(stepSystem);
        app.removeSystem(eventsSystem);
        app.removeSystem(syncOutSystem);
        if (commands.getResourceMut(backend.World)) |world| {
            world.deinit(commands.allocator);
            _ = commands.removeResource(backend.World);
        }
        _ = commands.removeResource(resources.StepState);
        _ = commands.removeResource(resources.Stats);
        _ = commands.removeResource(resources.Config);
    }
};

fn ensureScheduleBetween(
    app: *ecs.AppCommands,
    before_label: []const u8,
    label: []const u8,
    after_label: []const u8,
) !void {
    app.insertScheduleBetween(before_label, label, after_label) catch |err| switch (err) {
        error.ScheduleAlreadyExists => {},
        else => return err,
    };
}

fn syncInSystem(world: ecs.system_params.ResMut(backend.World), step_state: ecs.system_params.ResMut(resources.StepState)) void {
    world.ptr.syncIn(step_state.ptr);
}

fn stepSystem(
    world: ecs.system_params.ResMut(backend.World),
    config: ecs.system_params.Res(resources.Config),
    step_state: ecs.system_params.ResMut(resources.StepState),
    stats: ecs.system_params.ResMut(resources.Stats),
) void {
    world.ptr.step(config.ptr.*, step_state.ptr, stats.ptr);
}

fn eventsSystem(
    world: ecs.system_params.ResMut(backend.World),
    stats: ecs.system_params.ResMut(resources.Stats),
    step_state: ecs.system_params.Res(resources.StepState),
) void {
    world.ptr.collectEvents();
    stats.ptr.last_substeps = step_state.ptr.steps_last_frame;
}

fn syncOutSystem(
    world: ecs.system_params.ResMut(backend.World),
    _: *ecs.Commands,
    _: ecs.system_params.Res(resources.Config),
    _: ecs.system_params.Res(resources.StepState),
    _: ecs.system_params.Query(.{ common.Transform }),
) void {
    world.ptr.syncOut();
}
