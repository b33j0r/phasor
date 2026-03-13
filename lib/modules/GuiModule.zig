pub fn install(app: *AppCommands) !void {
    try app.addSystem(schedule.DefaultSchedule.Layout, updateCanvasRoots);
    try app.addSystem(schedule.DefaultSchedule.Layout, syncSpriteBoxes);
    try app.addSystem(schedule.DefaultSchedule.Layout, updateGuiTransforms);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(updateCanvasRoots);
    app.removeSystem(syncSpriteBoxes);
    app.removeSystem(updateGuiTransforms);
}

fn updateCanvasRoots(
    viewport_opt: ResOpt(RenderModule.ViewportSize),
    roots: Query(.{ gui.CanvasRoot, gui.Box, common.Transform }),
) void {
    const size = viewportSize(viewport_opt.ptr);
    var it = roots.iterator();
    while (it.next()) |row| {
        const root = row.get(gui.CanvasRoot) orelse continue;
        const box = row.get(gui.Box) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        box.width = size.width;
        box.height = size.height;
        transform.translation = .{
            .x = size.width * 0.5,
            .y = size.height * 0.5,
            .z = root.z,
        };
        transform.rotation = common.Quat.identity();
        transform.scale = common.Vec3.splat(1.0);
    }
}

fn syncSpriteBoxes(query: Query(.{ gui.Box, render.Sprite })) void {
    var it = query.iterator();
    while (it.next()) |row| {
        const box = row.get(gui.Box) orelse continue;
        const sprite = row.get(render.Sprite) orelse continue;
        sprite.size_mode = .{ .Manual = .{ .width = box.width, .height = box.height } };
    }
}

fn updateGuiTransforms(
    viewport_opt: ResOpt(RenderModule.ViewportSize),
    query: Query(.{ common.Parent, gui.Placement, common.Transform }),
) void {
    const bounds = viewportSize(viewport_opt.ptr);
    var it = query.iterator();
    while (it.next()) |row| {
        _ = row.get(common.Parent) orelse continue;
        _ = row.get(gui.Placement) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        const world = resolveEntityTransform(row.database, row.entity_id, bounds, 0) orelse continue;
        transform.* = world;
    }
}

fn resolveEntityTransform(database: *db.Database, entity_id: db.Entity.Id, bounds: gui.Box, depth: u8) ?common.Transform {
    if (depth > 32) return null;
    const loc = database.entities.get(entity_id) orelse return null;
    const table = &database.tables.items[loc.table_index];
    const transform = table.getComponentPtr(loc.row, common.Transform) orelse return null;
    if (table.getComponentPtr(loc.row, gui.CanvasRoot)) |canvas_root| {
        const box = table.getComponentPtr(loc.row, gui.Box) orelse return null;
        return .{
            .translation = .{
                .x = box.width * 0.5,
                .y = box.height * 0.5,
                .z = canvas_root.z,
            },
            .rotation = common.Quat.identity(),
            .scale = common.Vec3.splat(1.0),
        };
    }
    if (table.getComponentPtr(loc.row, common.Parent)) |parent| {
        if (table.getComponentPtr(loc.row, gui.Placement)) |placement| {
            const parent_transform = resolveEntityTransform(database, parent.id, bounds, depth + 1) orelse transform.*;
            const parent_box = resolveEntityBox(database, parent.id, bounds);
            const self_box = if (table.getComponentPtr(loc.row, gui.Box)) |box| box.* else gui.Box{};
            const parent_point = gui.anchorPoint(parent_box, placement.parent_anchor);
            const self_point = gui.anchorPoint(self_box, placement.self_anchor);
            return .{
                .translation = .{
                    .x = parent_transform.translation.x + parent_point.x - self_point.x + placement.offset.x,
                    .y = parent_transform.translation.y + parent_point.y - self_point.y + placement.offset.y,
                    .z = parent_transform.translation.z + placement.z,
                },
                .rotation = common.Quat.identity(),
                .scale = common.Vec3.splat(1.0),
            };
        }
    }
    return transform.*;
}

fn resolveEntityBox(database: *db.Database, entity_id: db.Entity.Id, bounds: gui.Box) gui.Box {
    const loc = database.entities.get(entity_id) orelse return bounds;
    const table = &database.tables.items[loc.table_index];
    if (table.getComponentPtr(loc.row, gui.Box)) |box| return box.*;
    return gui.Box{};
}

fn viewportSize(viewport_opt: ?*const RenderModule.ViewportSize) gui.Box {
    if (viewport_opt) |viewport| {
        return .{
            .width = viewport.width,
            .height = viewport.height,
        };
    }
    return .{ .width = 1280.0, .height = 720.0 };
}

const common = @import("common");
const db = @import("db");
const ecs = @import("ecs");
const gui = @import("gui");
const render = @import("render");
const RenderModule = @import("RenderModule.zig");

const AppCommands = ecs.AppCommands;
const schedule = ecs.schedule;
const Query = ecs.system_params.Query;
const ResOpt = ecs.system_params.ResOpt;
