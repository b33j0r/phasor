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
}

pub fn uninstall(app: *AppCommands, commands: *Commands) void {
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

const ecs = @import("ecs");
const lighting = @import("lighting");

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
const ResMut = ecs.system_params.ResMut;
const Without = ecs.system_params.Without;
