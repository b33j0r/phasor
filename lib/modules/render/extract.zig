pub fn extractSystem(
    queue: ResMut(render.RenderQueue),
    extracted_lighting: ResMut(types.ExtractedSceneLighting),
    ambient_light: ResOpt(lighting.AmbientLight),
    environment_light: ResOpt(lighting.EnvironmentLight),
    exposure_settings: ResOpt(lighting.ExposureSettings),
    normal_map_scale_opt: ResOpt(render.NormalMapScale),
    mesh_override_query: Query(.{ render.MeshInstance, common.Transform, render.LayerOverride }),
    mesh_zero_query: Query(.{ render.MeshInstance, common.Transform, render.Layer(0), Without(render.LayerOverride) }),
    mesh_unlayered_query: Query(.{ render.MeshInstance, common.Transform, Without(render.LayerN), Without(render.LayerOverride) }),
    mesh_layer_groups: GroupBy(render.LayerN),
    triangle_override_query: Query(.{ render.Triangle, render.LayerOverride }),
    triangle_zero_query: Query(.{ render.Triangle, render.Layer(0), Without(render.LayerOverride) }),
    triangle_unlayered_query: Query(.{ render.Triangle, Without(render.LayerN), Without(render.LayerOverride) }),
    triangle_layer_groups: GroupBy(render.LayerN),
    visible_lights: Query(.{ common.Transform, lighting.Light, lighting.LightVisibility }),
    untagged_lights: Query(.{ common.Transform, lighting.Light, Without(lighting.LightVisibility) }),
) !void {
    queue.ptr.reset();
    extracted_lighting.ptr.* = .{};
    const normal_scale_multiplier = if (normal_map_scale_opt.ptr) |scale|
        @max(scale.multiplier, 0.0)
    else
        1.0;
    if (ambient_light.ptr) |ambient| {
        extracted_lighting.ptr.ambient_color = .{
            .r = ambient.color.r * ambient.intensity,
            .g = ambient.color.g * ambient.intensity,
            .b = ambient.color.b * ambient.intensity,
            .a = 1.0,
        };
    }
    if (environment_light.ptr) |environment| {
        extracted_lighting.ptr.environment_intensity = environment.intensity;
        extracted_lighting.ptr.environment_diffuse_strength = environment.diffuse_strength;
        extracted_lighting.ptr.environment_specular_strength = environment.specular_strength;
        extracted_lighting.ptr.environment_average_luminance = environment.average_luminance;
        extracted_lighting.ptr.environment_dominant_direction = environment.dominant_direction;
        extracted_lighting.ptr.environment_dominant_color = environment.dominant_color;
        extracted_lighting.ptr.environment_irradiance_sh = environment.irradiance_sh;
    }
    if (exposure_settings.ptr) |settings| {
        extracted_lighting.ptr.exposure_enabled = settings.enabled;
        if (settings.auto_enabled) {
            const avg_luma = @max(extracted_lighting.ptr.environment_average_luminance, 0.0001);
            const auto_exposure = settings.auto_key_value / avg_luma;
            extracted_lighting.ptr.exposure = std.math.clamp(
                auto_exposure,
                settings.min_exposure,
                settings.max_exposure,
            );
        } else {
            extracted_lighting.ptr.exposure = settings.exposure;
        }
    }
    extractLights(extracted_lighting.ptr, visible_lights, true);
    extractLights(extracted_lighting.ptr, untagged_lights, false);

    try extractTrianglesForRows(queue.ptr, triangle_override_query, null);
    try extractTrianglesForRows(queue.ptr, triangle_zero_query, 0);
    try extractTrianglesForRows(queue.ptr, triangle_unlayered_query, 0);
    try extractTrianglesForGroups(queue.ptr, triangle_layer_groups);

    try extractMeshesForRows(queue.ptr, mesh_override_query, normal_scale_multiplier, null);
    try extractMeshesForRows(queue.ptr, mesh_zero_query, normal_scale_multiplier, 0);
    try extractMeshesForRows(queue.ptr, mesh_unlayered_query, normal_scale_multiplier, 0);
    try extractMeshesForGroups(queue.ptr, mesh_layer_groups, normal_scale_multiplier);
}

fn extractLights(store: *types.ExtractedSceneLighting, query: anytype, comptime has_visibility: bool) void {
    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(common.Transform) orelse continue;
        const light = row.get(lighting.Light) orelse continue;
        if (has_visibility) {
            const visibility = row.get(lighting.LightVisibility) orelse continue;
            if (!visibility.enabled) continue;
        }
        if (store.light_count >= render.max_scene_lights) break;
        store.lights[store.light_count] = buildSceneLight(transform.*, light.*);
        store.light_count += 1;
    }
}

fn buildSceneLight(transform: common.Transform, light: lighting.Light) render.SceneLight {
    const forward = transform.rotation.rotateVec3(.{ .x = 0.0, .y = 0.0, .z = -1.0 }).normalize();
    return switch (light) {
        .directional => |directional| .{
            .position_range = .{ 0.0, 0.0, 0.0, 0.0 },
            .direction_kind = .{ forward.x, forward.y, forward.z, @floatFromInt(@intFromEnum(render.SceneLightKind.directional)) },
            .color_intensity = .{
                directional.color.r,
                directional.color.g,
                directional.color.b,
                directional.illuminance_lux * 0.00008,
            },
        },
        .point => |point| .{
            .position_range = .{ transform.translation.x, transform.translation.y, transform.translation.z, point.range },
            .direction_kind = .{ 0.0, 0.0, 0.0, @floatFromInt(@intFromEnum(render.SceneLightKind.point)) },
            .color_intensity = .{ point.color.r, point.color.g, point.color.b, point.intensity_candela * 0.0025 },
            .spot_params = .{ 1.0, 0.0, point.radius, 0.0 },
        },
        .spot => |spot| .{
            .position_range = .{ transform.translation.x, transform.translation.y, transform.translation.z, spot.range },
            .direction_kind = .{ forward.x, forward.y, forward.z, @floatFromInt(@intFromEnum(render.SceneLightKind.spot)) },
            .color_intensity = .{ spot.color.r, spot.color.g, spot.color.b, spot.intensity_candela * 0.0025 },
            .spot_params = .{ @cos(spot.inner_angle_rad), @cos(spot.outer_angle_rad), spot.radius, 0.0 },
        },
    };
}

fn extractTrianglesForRows(queue: *render.RenderQueue, query: anytype, forced_layer: ?i32) !void {
    var it = query.iterator();
    while (it.next()) |row| {
        const tri = row.get(render.Triangle) orelse continue;
        const layer = forced_layer orelse layerKeyForRow(row);
        const sort_key = sortKeyForRow(row);
        try queue.pushTriangle(tri.*, layer, sort_key);
    }
}

fn extractTrianglesForGroups(queue: *render.RenderQueue, groups: GroupBy(render.LayerN)) !void {
    var it = groups.iterator();
    while (it.next()) |group| {
        if (group.key == 0) continue;
        var rows = try group.query(.{ render.Triangle, Without(render.LayerOverride) });
        defer rows.deinit();
        try extractTrianglesForRows(queue, rows, group.key);
    }
}

fn extractMeshesForRows(queue: *render.RenderQueue, query: anytype, normal_scale_multiplier: f32, forced_layer: ?i32) !void {
    var it = query.iterator();
    while (it.next()) |row| {
        const instance = row.get(render.MeshInstance) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        const layer = forced_layer orelse layerKeyForRow(row);
        const sort_key = sortKeyForRow(row);
        try queue.pushMeshInstance(instance.*, transform.toMat4(), normal_scale_multiplier, layer, sort_key, row.entity_id);
    }
}

fn extractMeshesForGroups(queue: *render.RenderQueue, groups: GroupBy(render.LayerN), normal_scale_multiplier: f32) !void {
    var it = groups.iterator();
    while (it.next()) |group| {
        if (group.key == 0) continue;
        var rows = try group.query(.{ render.MeshInstance, common.Transform, Without(render.LayerOverride) });
        defer rows.deinit();
        try extractMeshesForRows(queue, rows, normal_scale_multiplier, group.key);
    }
}

fn layerKeyForRow(row: db.QueryResult.Row) i32 {
    if (row.get(render.LayerOverride)) |override| {
        return override.value;
    }
    const table = &row.database.tables.items[row.table_index];
    return layerKeyForTable(table);
}

fn sortKeyForRow(row: db.QueryResult.Row) i32 {
    if (row.get(render.LayerSortKey)) |sort_key| {
        return sort_key.value;
    }
    return 0;
}

fn layerKeyForTable(table: *const db.table.Table) i32 {
    const trait_id = db.meta.typeId(render.LayerN);
    for (table.columns) |column| {
        for (column.group_traits) |group_trait| {
            if (group_trait.trait_id != trait_id) continue;
            return group_trait.key;
        }
    }
    return 0;
}

const std = @import("std");
const common = @import("common");
const ecs = @import("ecs");
const render = @import("render");
const lighting = @import("lighting");
const db = @import("db");
const types = @import("types.zig");

const system_params = ecs.system_params;
const GroupBy = system_params.GroupBy;
const Query = system_params.Query;
const ResMut = system_params.ResMut;
const ResOpt = system_params.ResOpt;
const Without = system_params.Without;
