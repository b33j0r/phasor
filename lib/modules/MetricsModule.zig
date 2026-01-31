pub const MetricsModule = struct {
    update_ms: u32 = 250,
    font_size: f32 = 60.0,
    text_color: common.Color = common.Color.BLACK,
    margin: f32 = 12.0,

    pub fn install(self: *const MetricsModule, app: *AppCommands, cmds: *Commands) !void {
        if (!cmds.hasResource(TimeModule.DeltaTime)) {
            return error.MissingTimeModule;
        }

        if (!cmds.hasResource(metrics.Metrics)) {
            try cmds.insertResource(metrics.Metrics{});
        }

        try cmds.insertResource(MetricsConfig{
            .update_interval = @as(f64, @floatFromInt(self.update_ms)) / 1000.0,
            .font_size = self.font_size,
            .text_color = self.text_color,
            .margin = self.margin,
        });

        const text_entity = try cmds.createEntity(.{
            render.Text{
                .content = "FPS: 0.0",
                .color = self.text_color,
                .font_size = self.font_size,
                .horizontal_alignment = .Right,
                .vertical_alignment = .Bottom,
            },
            common.Transform{},
            MetricsTextTag{},
        });

        try cmds.insertResource(MetricsState{ .text_entity = text_entity });
        try app.addSystem(schedule.DefaultSchedule.Update, updateFpsText);
    }

    pub fn uninstall(_: *const MetricsModule, app: *AppCommands, cmds: *Commands) void {
        app.removeSystem(updateFpsText);

        if (cmds.getResource(MetricsState)) |state| {
            cmds.removeEntity(state.text_entity) catch {};
        }

        _ = cmds.removeResource(MetricsState);
        _ = cmds.removeResource(MetricsConfig);
        _ = cmds.removeResource(metrics.Metrics);
    }
};

const MetricsConfig = struct {
    update_interval: f64,
    font_size: f32,
    text_color: common.Color,
    margin: f32,
};

const MetricsState = struct {
    text_entity: Entity.Id = 0,
    timer: f64 = 0.0,
    frames: u32 = 0,
    text_buffer: [32]u8 = undefined,
};

const MetricsTextTag = struct {};

const Bounds = struct {
    width: f32,
    height: f32,
};

fn updateFpsText(
    dt: Res(TimeModule.DeltaTime),
    viewport_opt: ResOpt(ViewportSize),
    window_bounds_opt: ResOpt(common.WindowBounds),
    render_bounds_opt: ResOpt(common.RenderBounds),
    render_state_opt: ResOpt(RenderState),
    config: Res(MetricsConfig),
    state: ResMut(MetricsState),
    metrics_res: ResMut(metrics.Metrics),
    query: Query(.{ render.Text, common.Transform, MetricsTextTag }),
) void {
    const bounds = resolveBounds(viewport_opt, window_bounds_opt, render_bounds_opt, render_state_opt) orelse return;
    const dt_seconds = dt.deref().seconds;
    metrics_res.ptr.frame_ms = @floatCast(dt_seconds * 1000.0);

    var iter = query.iterator();
    while (iter.next()) |row| {
        const text = row.get(render.Text) orelse continue;
        const transform = row.get(common.Transform) orelse continue;

        transform.translation.x = bounds.width - config.ptr.margin;
        transform.translation.y = bounds.height - config.ptr.margin;

        text.color = config.ptr.text_color;
        text.font_size = config.ptr.font_size;
        text.horizontal_alignment = .Right;
        text.vertical_alignment = .Bottom;
    }

    if (dt_seconds <= 0.0) return;
    state.ptr.timer += dt_seconds;
    state.ptr.frames += 1;

    if (state.ptr.timer < config.ptr.update_interval) return;

    const fps = @as(f32, @floatFromInt(state.ptr.frames)) / @as(f32, @floatCast(state.ptr.timer));
    metrics_res.ptr.fps = fps;
    if (fps > metrics_res.ptr.max_fps) {
        metrics_res.ptr.max_fps = fps;
    }
    state.ptr.timer = 0.0;
    state.ptr.frames = 0;

    const fmt_buf: []const u8 = std.fmt.bufPrint(&state.ptr.text_buffer, "FPS: {d:0.1}", .{fps}) catch "FPS: ERR";

    iter = query.iterator();
    while (iter.next()) |row| {
        const text = row.get(render.Text) orelse continue;
        text.content = fmt_buf;
    }
}

fn resolveBounds(
    viewport_opt: ResOpt(ViewportSize),
    window_bounds_opt: ResOpt(common.WindowBounds),
    render_bounds_opt: ResOpt(common.RenderBounds),
    render_state_opt: ResOpt(RenderState),
) ?Bounds {
    if (viewport_opt.ptr) |vp| {
        return .{ .width = vp.width, .height = vp.height };
    }
    if (window_bounds_opt.ptr) |bounds| {
        return .{
            .width = @floatFromInt(bounds.width),
            .height = @floatFromInt(bounds.height),
        };
    }
    if (render_bounds_opt.ptr) |bounds| {
        return .{ .width = bounds.width, .height = bounds.height };
    }
    if (render_state_opt.ptr) |state| {
        const size = state.surface.size();
        return .{
            .width = @floatFromInt(size.width),
            .height = @floatFromInt(size.height),
        };
    }
    return null;
}

const std = @import("std");
const common = @import("common");
const ecs = @import("ecs");
const metrics = @import("metrics");
const render = @import("render");
const schedule = ecs.schedule;
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;
const Entity = @import("db").Entity;
const TimeModule = @import("TimeModule.zig");
const RenderModule = @import("RenderModule.zig");
const ViewportSize = RenderModule.ViewportSize;
const RenderState = RenderModule.RenderState;
