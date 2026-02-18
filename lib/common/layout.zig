pub const LayoutValue = union(enum) {
    Pixels: f32,
    Percent: f32,

    pub fn px(value: f32) LayoutValue {
        return .{ .Pixels = value };
    }

    pub fn pct(value: f32) LayoutValue {
        return .{ .Percent = value };
    }

    pub fn resolve(self: LayoutValue, total: f32) f32 {
        return switch (self) {
            .Pixels => |v| v,
            .Percent => |v| total * v,
        };
    }
};

pub const ViewportLayout = struct {
    left: ?LayoutValue = null,
    right: ?LayoutValue = null,
    top: ?LayoutValue = null,
    bottom: ?LayoutValue = null,
    width: ?LayoutValue = null,
    height: ?LayoutValue = null,
};
