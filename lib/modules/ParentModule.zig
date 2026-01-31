pub fn install(app: *AppCommands) !void {
    try app.addSystem("BeforeFrame", updateChildTransforms);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(updateChildTransforms);
}

fn updateChildTransforms(query: Query(.{ common.Parent, common.LocalTransform, common.Transform })) void {
    var it = query.iterator();
    while (it.next()) |row| {
        const parent = row.get(common.Parent) orelse continue;
        const local = row.get(common.LocalTransform) orelse continue;
        const world = row.get(common.Transform) orelse continue;

        const parent_world = getTransformById(row.database, parent.id) orelse continue;
        world.* = compose(parent_world.*, local.*);
    }
}

fn getTransformById(database: *db.Database, entity_id: u64) ?*common.Transform {
    const loc = database.entities.get(entity_id) orelse return null;
    const table = &database.tables.items[loc.table_index];
    return table.getComponentPtr(loc.row, common.Transform);
}

fn compose(parent: common.Transform, local: common.LocalTransform) common.Transform {
    const scaled_local = common.Vec3{
        .x = local.translation.x * parent.scale.x,
        .y = local.translation.y * parent.scale.y,
        .z = local.translation.z * parent.scale.z,
    };
    const rotated_local = parent.rotation.rotateVec3(scaled_local);

    return .{
        .translation = parent.translation.add(rotated_local),
        .rotation = parent.rotation.mul(local.rotation),
        .scale = .{
            .x = parent.scale.x * local.scale.x,
            .y = parent.scale.y * local.scale.y,
            .z = parent.scale.z * local.scale.z,
        },
    };
}

// Imports
const common = @import("common");
const ecs = @import("ecs");
const db = @import("db");
const AppCommands = ecs.AppCommands;
const schedule = ecs.schedule;
const Query = ecs.system_params.Query;
