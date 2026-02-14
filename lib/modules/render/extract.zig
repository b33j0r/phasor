pub fn extractSystem(
    queue: ResMut(render.RenderQueue),
    mesh_query: Query(.{ render.MeshInstance, common.Transform, render.MaterialInstance }),
    mesh_default_query: Query(.{ render.MeshInstance, common.Transform, Without(render.MaterialInstance) }),
    triangle_query: Query(.{render.Triangle}),
) !void {
    queue.ptr.reset();

    var tri_it = triangle_query.iterator();
    while (tri_it.next()) |row| {
        const tri = row.get(render.Triangle) orelse continue;
        const layer = layerKeyForRow(row);
        try queue.ptr.pushTriangle(tri.*, layer);
    }

    var it = mesh_query.iterator();
    while (it.next()) |row| {
        const instance = row.get(render.MeshInstance) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        const material = row.get(render.MaterialInstance) orelse continue;
        const layer = layerKeyForRow(row);
        try queue.ptr.pushMeshInstanceWithMaterial(instance.*, transform.toMat4(), material.material, layer, row.entity_id);
    }

    var default_it = mesh_default_query.iterator();
    while (default_it.next()) |row| {
        const instance = row.get(render.MeshInstance) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        const layer = layerKeyForRow(row);
        try queue.ptr.pushMeshInstance(instance.*, transform.toMat4(), layer, row.entity_id);
    }
}

fn layerKeyForRow(row: db.QueryResult.Row) i32 {
    const table = &row.database.tables.items[row.table_index];
    return layerKeyForTable(table);
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
const Query = system_params.Query;
const ResMut = system_params.ResMut;
const Without = system_params.Without;
