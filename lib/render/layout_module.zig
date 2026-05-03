pub fn install(app: *AppCommands, commands: *Commands) !void {
    if (!commands.hasResource(types.LayerViewports)) {
        try commands.insertResource(types.LayerViewports.init(commands.allocator));
    }
    try app.addSystem(schedule.DefaultSchedule.Layout, computeLayerViewports);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(computeLayerViewports);
}

fn computeLayerViewports(
    viewports: ResMut(types.LayerViewports),
    viewport_opt: ResOpt(types.ViewportSize),
    cameras_zero_with_layout: Query(.{ common.Camera3d, common.ViewportLayout, render.CameraLayer(0) }),
    cameras_unlayered_with_layout: Query(.{ common.Camera3d, common.ViewportLayout, Without(render.CameraLayerN) }),
    camera_groups_with_layout: GroupBy(render.CameraLayerN),
    cameras_zero_without_layout: Query(.{ common.Camera3d, render.CameraLayer(0), Without(common.ViewportLayout) }),
    cameras_unlayered_without_layout: Query(.{ common.Camera3d, Without(common.ViewportLayout), Without(render.CameraLayerN) }),
    camera_groups_without_layout: GroupBy(render.CameraLayerN),
) !void {
    const bounds = viewportBounds(viewport_opt.ptr);
    viewports.ptr.clear();

    try collectLayerViewportLayouts(viewports.ptr, cameras_zero_with_layout, bounds, 0);
    try collectLayerViewportLayouts(viewports.ptr, cameras_unlayered_with_layout, bounds, 0);
    try collectLayerViewportGroupsWithLayout(viewports.ptr, camera_groups_with_layout, bounds);

    try collectDefaultLayerViewport(viewports.ptr, cameras_zero_without_layout, bounds, 0);
    try collectDefaultLayerViewport(viewports.ptr, cameras_unlayered_without_layout, bounds, 0);
    try collectLayerViewportGroupsWithoutLayout(viewports.ptr, camera_groups_without_layout, bounds);
}

fn collectLayerViewportLayouts(
    viewports: *types.LayerViewports,
    query: anytype,
    bounds: Bounds,
    forced_layer: i32,
) !void {
    var it = query.iterator();
    while (it.next()) |row| {
        _ = row.get(common.Camera3d) orelse continue;
        const layout = row.get(common.ViewportLayout) orelse continue;
        const rect = resolveRect(layout.*, bounds);
        if (rect.width <= 0.0 or rect.height <= 0.0) continue;
        try viewports.map.put(forced_layer, rect);
    }
}

fn collectLayerViewportGroupsWithLayout(
    viewports: *types.LayerViewports,
    groups: GroupBy(render.CameraLayerN),
    bounds: Bounds,
) !void {
    var it = groups.iterator();
    while (it.next()) |group| {
        if (group.key == 0) continue;
        var rows = try group.query(.{ common.Camera3d, common.ViewportLayout });
        defer rows.deinit();
        try collectLayerViewportLayouts(viewports, rows, bounds, group.key);
    }
}

fn collectDefaultLayerViewport(
    viewports: *types.LayerViewports,
    query: anytype,
    bounds: Bounds,
    forced_layer: i32,
) !void {
    var it = query.iterator();
    while (it.next()) |row| {
        _ = row.get(common.Camera3d) orelse continue;
        if (viewports.map.contains(forced_layer)) continue;
        try viewports.map.put(forced_layer, .{
            .x = 0.0,
            .y = 0.0,
            .width = bounds.width,
            .height = bounds.height,
        });
    }
}

fn collectLayerViewportGroupsWithoutLayout(
    viewports: *types.LayerViewports,
    groups: GroupBy(render.CameraLayerN),
    bounds: Bounds,
) !void {
    var it = groups.iterator();
    while (it.next()) |group| {
        if (group.key == 0) continue;
        var rows = try group.query(.{ common.Camera3d, Without(common.ViewportLayout) });
        defer rows.deinit();
        try collectDefaultLayerViewport(viewports, rows, bounds, group.key);
    }
}

const Bounds = struct {
    width: f32,
    height: f32,
};

fn viewportBounds(viewport_opt: ?*const types.ViewportSize) Bounds {
    if (viewport_opt) |vp| return .{ .width = vp.width, .height = vp.height };
    return .{ .width = 1280.0, .height = 720.0 };
}

fn resolveRect(layout: common.ViewportLayout, bounds: Bounds) types.ViewportRect {
    const left = if (layout.left) |v| v.resolve(bounds.width) else null;
    const right = if (layout.right) |v| v.resolve(bounds.width) else null;
    const top = if (layout.top) |v| v.resolve(bounds.height) else null;
    const bottom = if (layout.bottom) |v| v.resolve(bounds.height) else null;
    const explicit_width = if (layout.width) |v| v.resolve(bounds.width) else null;
    const explicit_height = if (layout.height) |v| v.resolve(bounds.height) else null;

    const x: f32, const width: f32 = blk: {
        if (explicit_width) |w| {
            const x_pos = if (left) |l|
                l
            else if (right) |r|
                bounds.width - r - w
            else
                0.0;
            break :blk .{ x_pos, w };
        }
        const l = left orelse 0.0;
        const r = right orelse 0.0;
        break :blk .{ l, bounds.width - l - r };
    };

    const y: f32, const height: f32 = blk: {
        if (explicit_height) |h| {
            const y_pos = if (top) |t|
                t
            else if (bottom) |b|
                bounds.height - b - h
            else
                0.0;
            break :blk .{ y_pos, h };
        }
        const t = top orelse 0.0;
        const b = bottom orelse 0.0;
        break :blk .{ t, bounds.height - t - b };
    };

    const clamped_x = std.math.clamp(x, 0.0, bounds.width);
    const clamped_y = std.math.clamp(y, 0.0, bounds.height);
    const max_w = @max(0.0, bounds.width - clamped_x);
    const max_h = @max(0.0, bounds.height - clamped_y);
    return .{
        .x = clamped_x,
        .y = clamped_y,
        .width = std.math.clamp(width, 0.0, max_w),
        .height = std.math.clamp(height, 0.0, max_h),
    };
}

const std = @import("std");
const common = @import("common");
const ecs = @import("ecs");
const render = @import("root.zig");
const types = @import("types.zig");

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const schedule = ecs.schedule;
const system_params = ecs.system_params;
const GroupBy = system_params.GroupBy;
const Query = system_params.Query;
const ResMut = system_params.ResMut;
const ResOpt = system_params.ResOpt;
const Without = system_params.Without;
