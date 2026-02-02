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
        world.* = compose(parent_world.*, local.*, parent.*);
    }
}

fn getTransformById(database: *db.Database, entity_id: u64) ?*common.Transform {
    const loc = database.entities.get(entity_id) orelse return null;
    const table = &database.tables.items[loc.table_index];
    return table.getComponentPtr(loc.row, common.Transform);
}

fn compose(parent_world: common.Transform, local: common.LocalTransform, parent: common.Parent) common.Transform {
    const inherit_translation = parent.inherit_translation;
    const inherit_rotation = parent.inherit_rotation;
    const inherit_scale = parent.inherit_scale;

    const parent_scale = if (inherit_scale) parent_world.scale else common.Vec3.splat(1.0);
    const parent_rotation = if (inherit_rotation) parent_world.rotation else common.Quat.identity();
    const parent_translation = if (inherit_translation) parent_world.translation else common.Vec3{};

    const scaled_local = common.Vec3{
        .x = local.translation.x * parent_scale.x,
        .y = local.translation.y * parent_scale.y,
        .z = local.translation.z * parent_scale.z,
    };
    const rotated_local = parent_rotation.rotateVec3(scaled_local);

    return .{
        .translation = parent_translation.add(rotated_local),
        .rotation = parent_rotation.mul(local.rotation),
        .scale = .{
            .x = parent_scale.x * local.scale.x,
            .y = parent_scale.y * local.scale.y,
            .z = parent_scale.z * local.scale.z,
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
