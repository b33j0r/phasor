pub fn extractSystem(
    queue: ResMut(render.RenderQueue),
    mesh_override_query: Query(.{ render.MeshInstance, common.Transform, render.LayerOverride }),
    mesh_zero_query: Query(.{ render.MeshInstance, common.Transform, render.Layer(0), Without(render.LayerOverride) }),
    mesh_unlayered_query: Query(.{ render.MeshInstance, common.Transform, Without(render.LayerN), Without(render.LayerOverride) }),
    mesh_layer_groups: GroupBy(render.LayerN),
    triangle_override_query: Query(.{ render.Triangle, render.LayerOverride }),
    triangle_zero_query: Query(.{ render.Triangle, render.Layer(0), Without(render.LayerOverride) }),
    triangle_unlayered_query: Query(.{ render.Triangle, Without(render.LayerN), Without(render.LayerOverride) }),
    triangle_layer_groups: GroupBy(render.LayerN),
) !void {
    queue.ptr.reset();

    try extractTrianglesForRows(queue.ptr, triangle_override_query, null);
    try extractTrianglesForRows(queue.ptr, triangle_zero_query, 0);
    try extractTrianglesForRows(queue.ptr, triangle_unlayered_query, 0);
    try extractTrianglesForGroups(queue.ptr, triangle_layer_groups);

    try extractMeshesForRows(queue.ptr, mesh_override_query, null);
    try extractMeshesForRows(queue.ptr, mesh_zero_query, 0);
    try extractMeshesForRows(queue.ptr, mesh_unlayered_query, 0);
    try extractMeshesForGroups(queue.ptr, mesh_layer_groups);
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

fn extractMeshesForRows(queue: *render.RenderQueue, query: anytype, forced_layer: ?i32) !void {
    var it = query.iterator();
    while (it.next()) |row| {
        const instance = row.get(render.MeshInstance) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        const layer = forced_layer orelse layerKeyForRow(row);
        const sort_key = sortKeyForRow(row);
        try queue.pushMeshInstance(instance.*, transform.toMat4(), layer, sort_key, row.entity_id);
    }
}

fn extractMeshesForGroups(queue: *render.RenderQueue, groups: GroupBy(render.LayerN)) !void {
    var it = groups.iterator();
    while (it.next()) |group| {
        if (group.key == 0) continue;
        var rows = try group.query(.{ render.MeshInstance, common.Transform, Without(render.LayerOverride) });
        defer rows.deinit();
        try extractMeshesForRows(queue, rows, group.key);
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

const common = @import("common");
const ecs = @import("ecs");
const render = @import("render");
const db = @import("db");

const system_params = ecs.system_params;
const GroupBy = system_params.GroupBy;
const Query = system_params.Query;
const ResMut = system_params.ResMut;
const Without = system_params.Without;
