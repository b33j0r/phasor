const std = @import("std");
const phasor = @import("phasor");

pub const Model = struct {
    visible: bool = true,
    progress01: f32 = 0.0,
    status_buf: [160]u8 = @splat(0),
    status_len: usize = 0,

    pub fn status(self: *const Model) []const u8 {
        return self.status_buf[0..self.status_len];
    }

    pub fn clearStatus(self: *Model) void {
        self.status_len = 0;
    }

    pub fn setStatus(self: *Model, text: []const u8) void {
        const len = @min(text.len, self.status_buf.len);
        @memcpy(self.status_buf[0..len], text[0..len]);
        self.status_len = len;
    }

    pub fn setStatusFmt(self: *Model, comptime fmt: []const u8, args: anytype) !void {
        self.status_len = (try std.fmt.bufPrint(&self.status_buf, fmt, args)).len;
    }
};

pub const StatusText = struct {};
pub const BarTrack = struct {};
pub const BarFill = struct {};

const bar_width: f32 = 360.0;
const bar_left: f32 = 220.0;
const bar_center_x: f32 = bar_left + bar_width * 0.5;

pub fn setup(commands: *Commands) !void {
    if (!commands.hasResource(Model)) {
        try commands.insertResource(Model{});
    }

    _ = try commands.createEntity(.{
        StatusText{},
        Transform{ .translation = .{ .x = bar_center_x, .y = 268.0, .z = 0.0 } },
        Text{
            .font_size = 18.0,
            .color = Color.rgb(214, 227, 242),
            .content = "",
            .horizontal_alignment = .Center,
            .vertical_alignment = .Center,
        },
        Layer(1000){},
    });

    _ = try commands.createEntity(.{
        BarTrack{},
        Transform{ .translation = .{ .x = 400.0, .y = 318.0, .z = 0.0 }, .scale = Vec3.splat(0.0) },
        Rectangle{ .width = bar_width, .height = 18.0, .color = Color.rgb(38, 46, 58) },
        Layer(1000){},
    });

    _ = try commands.createEntity(.{
        BarFill{},
        Transform{ .translation = .{ .x = bar_left, .y = 318.0, .z = 0.0 }, .scale = Vec3.splat(0.0) },
        Rectangle{ .width = 1.0, .height = 18.0, .color = Color.rgb(90, 190, 255) },
        Layer(1000){},
    });
}

pub fn sync(
    model: Res(Model),
    status_query: Query(.{ Text, StatusText }),
    fill_query: Query(.{ Rectangle, Transform, BarFill }),
    track_query: Query(.{ Transform, BarTrack }),
) void {
    var status_it = status_query.iterator();
    while (status_it.next()) |row| {
        const text = row.get(Text) orelse continue;
        text.content = if (model.ptr.visible) model.ptr.status() else "";
    }

    const scale = if (model.ptr.visible) Vec3.splat(1.0) else Vec3.splat(0.0);

    var track_it = track_query.iterator();
    while (track_it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.scale = scale;
    }

    const fill_width = @max(1.0, bar_width * std.math.clamp(model.ptr.progress01, 0.0, 1.0));
    var fill_it = fill_query.iterator();
    while (fill_it.next()) |row| {
        const rectangle = row.get(Rectangle) orelse continue;
        const transform = row.get(Transform) orelse continue;
        rectangle.width = fill_width;
        transform.translation.x = bar_left + fill_width * 0.5;
        transform.scale = scale;
    }
}

const Color = phasor.Color;
const Commands = phasor.Commands;
const Layer = phasor.Layer;
const Query = phasor.Query;
const Rectangle = phasor.Rectangle;
const Res = phasor.Res;
const Text = phasor.Text;
const Transform = phasor.Transform;
const Vec3 = phasor.Vec3;
