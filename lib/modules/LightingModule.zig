pub fn install(app: *AppCommands, commands: *Commands) !void {
    if (!commands.hasResource(lighting.AmbientLight)) {
        try commands.insertResource(lighting.AmbientLight{});
    }
    if (!commands.hasResource(lighting.EnvironmentLight)) {
        try commands.insertResource(lighting.EnvironmentLight{});
    }
    if (!commands.hasResource(lighting.ExposureSettings)) {
        try commands.insertResource(lighting.ExposureSettings{});
    }
    if (!commands.hasResource(lighting.AuthoringStats)) {
        try commands.insertResource(lighting.AuthoringStats{});
    }

    try app.addSystem("BeforeFrame", syncAuthoringStats);
    try app.addSystem("BeforeFrame", emitAuthoringMetrics);
}

pub fn uninstall(app: *AppCommands, commands: *Commands) void {
    app.removeSystem(emitAuthoringMetrics);
    app.removeSystem(syncAuthoringStats);
    _ = commands.removeResource(lighting.AuthoringStats);
    _ = commands.removeResource(lighting.ExposureSettings);
    _ = commands.removeResource(lighting.EnvironmentLight);
    _ = commands.removeResource(lighting.AmbientLight);
}

fn syncAuthoringStats(
    stats: ResMut(lighting.AuthoringStats),
    visible_lights: Query(.{ lighting.Light, lighting.LightVisibility }),
    untagged_lights: Query(.{ lighting.Light, Without(lighting.LightVisibility) }),
) void {
    stats.ptr.* = .{};

    var visible_it = visible_lights.iterator();
    while (visible_it.next()) |row| {
        const light = row.get(lighting.Light) orelse continue;
        const visibility = row.get(lighting.LightVisibility) orelse continue;
        accumulate(stats.ptr, light.*, visibility.*);
    }

    var untagged_it = untagged_lights.iterator();
    while (untagged_it.next()) |row| {
        const light = row.get(lighting.Light) orelse continue;
        accumulate(stats.ptr, light.*, .{});
    }
}

fn accumulate(
    stats: *lighting.AuthoringStats,
    light: lighting.Light,
    visibility: lighting.LightVisibility,
) void {
    stats.total_lights += 1;
    if (visibility.enabled) stats.enabled_lights += 1;
    if (visibility.is_static) {
        stats.static_lights += 1;
    } else {
        stats.dynamic_lights += 1;
    }

    switch (light.kind()) {
        .directional => stats.directional_lights += 1,
        .point => stats.point_lights += 1,
        .spot => stats.spot_lights += 1,
    }
}

fn emitAuthoringMetrics(
    bus: ResMut(metrics.Bus),
    mode_opt: ResOpt(render.SceneStatsMode),
    stats: ResMut(lighting.AuthoringStats),
) void {
    const mode = mode_opt.ptr orelse return;
    if (!mode.enabled) return;

    metrics.emitBus(true, bus.ptr, .{
        .lights_total = metrics.gauge(stats.ptr.total_lights),
        .lights_dynamic = metrics.gauge(stats.ptr.dynamic_lights),
        .lights_point = metrics.gauge(stats.ptr.point_lights),
        .lights_spot = metrics.gauge(stats.ptr.spot_lights),
    });
}

const ecs = @import("ecs");
const lighting = @import("lighting");
const metrics = @import("metrics");
const render = @import("render");

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;
const Without = ecs.system_params.Without;
