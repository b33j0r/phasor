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

pub const Config = struct {
    status_font_size: f32 = 18.0,
    status_color: Color = Color.rgb(214, 227, 242),
    bar_width: f32 = 360.0,
    bar_height: f32 = 18.0,
    bar_center_offset_y: f32 = -24.0,
    status_gap: f32 = 26.0,
    track_color: Color = Color.rgb(38, 46, 58),
    fill_color: Color = Color.rgb(90, 190, 255),
    min_fill_width: f32 = 1.0,

    fn statusPosition(self: Config) Vec3 {
        return .{
            .x = 0.0,
            .y = self.bar_center_offset_y + self.bar_height * 0.5 + self.status_gap,
            .z = 0.0,
        };
    }

    fn barPosition(self: Config) Vec3 {
        return .{
            .x = 0.0,
            .y = self.bar_center_offset_y,
            .z = 0.0,
        };
    }

    fn fillPosition(self: Config, fill_width: f32) Vec3 {
        return .{
            .x = -(self.bar_width - fill_width) * 0.5,
            .y = self.bar_center_offset_y,
            .z = 0.0,
        };
    }

    fn fillWidth(self: Config, progress01: f32) f32 {
        return @max(self.min_fill_width, self.bar_width * std.math.clamp(progress01, 0.0, 1.0));
    }
};

pub const StatusText = struct {};
pub const BarTrack = struct {};
pub const BarFill = struct {};

pub fn setup(commands: *Commands) !void {
    if (!commands.hasResource(Model)) {
        try commands.insertResource(Model{});
    }
    const config = try ensureConfig(commands);

    try commands.insertEntity(.{
        StatusText{},
        Transform{ .translation = config.statusPosition(), .scale = Vec3.splat(0.0) },
        Text{
            .font_size = config.status_font_size,
            .color = config.status_color,
            .content = "",
            .horizontal_alignment = .Center,
            .vertical_alignment = .Center,
        },
        Layer(1){},
    });

    try commands.insertEntity(.{
        Camera{ .Viewport = .{ .mode = .Center } },
        Transform{},
        CameraLayer(1){},
    });

    try commands.insertEntity(.{
        BarTrack{},
        Transform{ .translation = config.barPosition(), .scale = Vec3.splat(0.0) },
        Rectangle{ .width = config.bar_width, .height = config.bar_height, .color = config.track_color },
        Layer(1){},
    });

    try commands.insertEntity(.{
        BarFill{},
        Transform{ .translation = config.fillPosition(config.min_fill_width), .scale = Vec3.splat(0.0) },
        Rectangle{ .width = config.min_fill_width, .height = config.bar_height, .color = config.fill_color },
        Layer(1){},
    });
}

pub fn sync(
    model: Res(Model),
    config: Res(Config),
    status_query: Query(.{ Text, Transform, StatusText }),
    fill_query: Query(.{ Rectangle, Transform, BarFill }),
    track_query: Query(.{ Rectangle, Transform, BarTrack }),
) void {
    var status_it = status_query.iterator();
    while (status_it.next()) |row| {
        const text = row.get(Text) orelse continue;
        const transform = row.get(Transform) orelse continue;
        text.font_size = config.ptr.status_font_size;
        text.color = config.ptr.status_color;
        text.content = if (model.ptr.visible) model.ptr.status() else "";
        transform.translation = config.ptr.statusPosition();
        transform.scale = if (model.ptr.visible) Vec3.splat(1.0) else Vec3.splat(0.0);
    }

    const scale = if (model.ptr.visible) Vec3.splat(1.0) else Vec3.splat(0.0);

    var track_it = track_query.iterator();
    while (track_it.next()) |row| {
        const rectangle = row.get(Rectangle) orelse continue;
        const transform = row.get(Transform) orelse continue;
        rectangle.width = config.ptr.bar_width;
        rectangle.height = config.ptr.bar_height;
        rectangle.color = config.ptr.track_color;
        transform.translation = config.ptr.barPosition();
        transform.scale = scale;
    }

    const fill_width = config.ptr.fillWidth(model.ptr.progress01);
    var fill_it = fill_query.iterator();
    while (fill_it.next()) |row| {
        const rectangle = row.get(Rectangle) orelse continue;
        const transform = row.get(Transform) orelse continue;
        rectangle.width = fill_width;
        rectangle.height = config.ptr.bar_height;
        rectangle.color = config.ptr.fill_color;
        transform.translation = config.ptr.fillPosition(fill_width);
        transform.scale = scale;
    }
}

fn ensureConfig(commands: *Commands) !Config {
    if (commands.getResource(Config)) |config| {
        return config.*;
    }
    if (!commands.hasResource(Config)) {
        try commands.insertResource(Config{});
    }
    return Config{};
}

const Camera = phasor.Camera;
const CameraLayer = phasor.CameraLayer;
const Color = phasor.Color;
const Commands = phasor.Commands;
const Layer = phasor.Layer;
const Query = phasor.Query;
const Rectangle = phasor.Rectangle;
const Res = phasor.Res;
const Text = phasor.Text;
const Transform = phasor.Transform;
const Vec3 = phasor.Vec3;
