//! `MetricsModule` installs a Metrics resource and DB hooks for tracking ECS activity.
pub fn install(app: *AppCommands, cmds: *Commands) !void {
    if (!cmds.world.hasResource(metrics.Metrics)) {
        try cmds.world.insertResource(metrics.Metrics{});
    }

    if (!cmds.world.hasResource(MetricsHooks)) {
        const metrics_ptr = cmds.world.getResourceMut(metrics.Metrics).?;
        try cmds.world.insertResource(MetricsHooks{
            .metrics = metrics_ptr,
            .db_hooks = hooks.DatabaseHooks.none(),
        });
    }

    const hooks_ptr = cmds.world.getResourceMut(MetricsHooks).?;
    hooks_ptr.db_hooks = hooks.DatabaseHooks.from(MetricsHooks, hooks_ptr);
    cmds.world.database.setHooks(&hooks_ptr.db_hooks);

    try app.addSystem(schedule.DefaultSchedule.BeforeFrame, beginFrame);
}

pub fn uninstall(app: *AppCommands, cmds: *Commands) void {
    app.removeSystem(beginFrame);
    cmds.world.database.clearHooks();
    _ = cmds.removeResource(MetricsHooks);
}

const MetricsHooks = struct {
    metrics: *metrics.Metrics,
    db_hooks: hooks.DatabaseHooks,

    pub fn onEntityCreated(self: *MetricsHooks, _: Entity.Id, _: usize) void {
        self.metrics.spawned += 1;
    }

    pub fn onEntityRemoved(self: *MetricsHooks, _: Entity.Id, _: usize) void {
        self.metrics.removed += 1;
    }

    pub fn onEntityMoved(self: *MetricsHooks, _: Entity.Id, _: usize, _: usize) void {
        self.metrics.moved += 1;
    }
};

fn beginFrame(res: ResMut(metrics.Metrics)) void {
    const metrics_ptr = res.deref();
    metrics_ptr.frame += 1;
    metrics_ptr.resetFrame();
}

// Imports
const phasor = @import("../root.zig");
const metrics = phasor.metrics;
const hooks = phasor.ecs.hooks;
const schedule = phasor.ecs.schedule;
const Entity = phasor.db.Entity;
const AppCommands = phasor.ecs.AppCommands;
const Commands = phasor.ecs.Commands;
const ResMut = phasor.ecs.system_params.ResMut;
