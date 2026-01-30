const std = @import("std");
const meta = @import("meta.zig");
const resolveStructType = meta.resolveStructType;
const structHasField = meta.structHasField;

// ============================
// File-as-struct (like Bounds)
// ============================
r: u8 = 255,
g: u8 = 255,
b: u8 = 255,
a: u8 = 255,

const Color = @This();

// ============================
// Named colors
// ============================
pub const LIGHTGRAY = Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
pub const GRAY = Color{ .r = 130, .g = 130, .b = 130, .a = 255 };
pub const DARKGRAY = Color{ .r = 80, .g = 80, .b = 80, .a = 255 };
pub const YELLOW = Color{ .r = 253, .g = 249, .b = 0, .a = 255 };
pub const GOLD = Color{ .r = 255, .g = 203, .b = 0, .a = 255 };
pub const ORANGE = Color{ .r = 255, .g = 161, .b = 0, .a = 255 };
pub const PINK = Color{ .r = 255, .g = 109, .b = 194, .a = 255 };
pub const RED = Color{ .r = 230, .g = 41, .b = 55, .a = 255 };
pub const MAROON = Color{ .r = 190, .g = 33, .b = 55, .a = 255 };
pub const GREEN = Color{ .r = 0, .g = 228, .b = 48, .a = 255 };
pub const LIME = Color{ .r = 0, .g = 158, .b = 47, .a = 255 };
pub const CYAN = Color{ .r = 102, .g = 191, .b = 255, .a = 255 };
pub const DARKGREEN = Color{ .r = 0, .g = 117, .b = 44, .a = 255 };
pub const SKYBLUE = Color{ .r = 102, .g = 191, .b = 255, .a = 255 };
pub const BLUE = Color{ .r = 0, .g = 121, .b = 241, .a = 255 };
pub const DARKBLUE = Color{ .r = 0, .g = 82, .b = 172, .a = 255 };
pub const PURPLE = Color{ .r = 200, .g = 122, .b = 255, .a = 255 };
pub const VIOLET = Color{ .r = 135, .g = 60, .b = 190, .a = 255 };
pub const DARKPURPLE = Color{ .r = 112, .g = 31, .b = 126, .a = 255 };
pub const BEIGE = Color{ .r = 211, .g = 176, .b = 131, .a = 255 };
pub const BROWN = Color{ .r = 127, .g = 106, .b = 79, .a = 255 };
pub const DARKBROWN = Color{ .r = 76, .g = 63, .b = 47, .a = 255 };
pub const WHITE = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
pub const BLACK = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
pub const BLANK = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
pub const MAGENTA = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };

// Specials
pub const RAYWHITE = Color{ .r = 245, .g = 245, .b = 245, .a = 255 };
pub const ORANGERED = Color{ .r = 230, .g = 97, .b = 0, .a = 255 };
pub const BSOD = Color{ .r = 0, .g = 0, .b = 215, .a = 255 };

// ============================
// Convenience constructors
// ============================
pub fn rgb(r: u8, g: u8, b: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = 255 };
}
pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
}
pub fn withAlpha(self: Color, a: u8) Color {
    var out = self;
    out.a = a;
    return out;
}
pub fn withAlphaUnit(self: Color, a_unit: f32) Color {
    var out = self;
    out.a = u8FromUnitFloat(a_unit);
    return out;
}

pub const F32 = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn fromColor(c: Color) F32 {
        return .{
            .r = unitFloatFromU8(f32, c.r),
            .g = unitFloatFromU8(f32, c.g),
            .b = unitFloatFromU8(f32, c.b),
            .a = unitFloatFromU8(f32, c.a),
        };
    }

    pub fn toColor(self: F32) Color {
        return Color.fromColor(self);
    }
};

// Color -> T (matches r,g,b,a if present). u8 -> float => 0..1 ; u8 -> int keeps 0..255.
pub fn toColor(self: *const Color, comptime T: type) T {
    const S = resolveStructType(T);

    comptime {
        if (@typeInfo(S) != .@"struct") {
            @compileError("toColor: target type must be a struct");
        }
        var has_match = false;
        for (@typeInfo(S).@"struct".fields) |df| {
            if (std.mem.eql(u8, df.name, "r") or
                std.mem.eql(u8, df.name, "g") or
                std.mem.eql(u8, df.name, "b") or
                std.mem.eql(u8, df.name, "a")) has_match = true;
        }
        if (!has_match) {
            @compileError("toColor: no matching fields between Color and target type");
        }
    }

    var out: T = undefined;

    inline for (@typeInfo(S).@"struct".fields) |df| {
        if (std.mem.eql(u8, df.name, "r") or
            std.mem.eql(u8, df.name, "g") or
            std.mem.eql(u8, df.name, "b") or
            std.mem.eql(u8, df.name, "a"))
        {
            const chan: u8 = @field(self.*, df.name);
            @field(out, df.name) = convertOutChannel(df.type, chan);
        }
    }
    return out;
}

// any struct/pointer with r,g,b,(a?) -> Color
// ints read as 0..255 (clamped), floats read as 0..1 (clamped, rounded*255).
pub fn fromColor(src: anytype) Color {
    const SrcT = @TypeOf(src);
    const SrcS = resolveStructType(SrcT);

    comptime {
        if (@typeInfo(SrcS) != .@"struct") {
            @compileError("fromColor: source must be a struct (or pointer to struct)");
        }
        if (!structHasField(SrcS, "r") or
            !structHasField(SrcS, "g") or
            !structHasField(SrcS, "b"))
        {
            @compileError("fromColor: source must have at least r,g,b fields");
        }
    }

    var out = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

    if (@typeInfo(SrcT) == .pointer) {
        const v: SrcS = src.*;
        out.r = convertInChannel(@field(v, "r"));
        out.g = convertInChannel(@field(v, "g"));
        out.b = convertInChannel(@field(v, "b"));
        if (comptime structHasField(SrcS, "a")) {
            out.a = convertInChannel(@field(v, "a"));
        }
    } else {
        out.r = convertInChannel(@field(src, "r"));
        out.g = convertInChannel(@field(src, "g"));
        out.b = convertInChannel(@field(src, "b"));
        if (comptime structHasField(SrcS, "a")) {
            out.a = convertInChannel(@field(src, "a"));
        }
    }

    return out;
}

// u8 -> T for toColor()
inline fn convertOutChannel(comptime ToT: type, chan_u8: u8) ToT {
    return switch (@typeInfo(ToT)) {
        .int, .comptime_int => @as(ToT, @intCast(chan_u8)),
        .float, .comptime_float => unitFloatFromU8(ToT, chan_u8),
        else => @compileError("toColor: unsupported destination field type"),
    };
}

// any -> u8 for fromColor()
inline fn convertInChannel(value: anytype) u8 {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .int, .comptime_int => blk: {
            const v = @as(i64, @intCast(value));
            const clamped = std.math.clamp(v, 0, 255);
            break :blk @as(u8, @intCast(clamped));
        },
        .float, .comptime_float => u8FromUnitFloat(value),
        else => @compileError("fromColor: unsupported source field type"),
    };
}

inline fn clamp01(comptime F: type, x: F) F {
    return std.math.clamp(x, @as(F, 0.0), @as(F, 1.0));
}

inline fn u8FromUnitFloat(x_any: anytype) u8 {
    const F = @TypeOf(x_any);
    const x_f64: f64 = switch (@typeInfo(F)) {
        .float, .comptime_float => @floatCast(x_any),
        else => @compileError("u8FromUnitFloat expects float input"),
    };
    const clamped = clamp01(f64, x_f64);
    const scaled = std.math.round(clamped * 255.0);
    return @intFromFloat(scaled);
}

inline fn unitFloatFromU8(comptime F: type, c: u8) F {
    comptime {
        if (@typeInfo(F) != .float and @typeInfo(F) != .comptime_float)
            @compileError("unitFloatFromU8: destination must be float");
    }
    return @as(F, @floatFromInt(c)) / @as(F, 255.0);
}

// ============================
// Tests
// ============================
test "toColor: u8 -> f32 normalized" {
    const Float4 = struct { r: f32, g: f32, b: f32, a: f32 };
    const c = Color{ .r = 255, .g = 128, .b = 0, .a = 64 };
    const f = c.toColor(Float4);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), f.r, 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 128.0 / 255.0), f.g, 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), f.b, 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 64.0 / 255.0), f.a, 1e-6);
}

test "toColor: u8 -> u16 preserves 0..255" {
    const U16 = struct { r: u16, g: u16, b: u16, a: u16 };
    const c = Color{ .r = 255, .g = 10, .b = 0, .a = 200 };
    const d = c.toColor(U16);
    try std.testing.expectEqual(@as(u16, 255), d.r);
    try std.testing.expectEqual(@as(u16, 10), d.g);
    try std.testing.expectEqual(@as(u16, 0), d.b);
    try std.testing.expectEqual(@as(u16, 200), d.a);
}

test "fromColor: f32(0..1) -> u8 with rounding" {
    const F = struct { r: f32, g: f32, b: f32, a: f32 };
    const src = F{ .r = 1.0, .g = 0.5, .b = 0.0, .a = 0.25 };
    const c = Color.fromColor(src);
    try std.testing.expectEqual(@as(u8, 255), c.r);
    try std.testing.expectEqual(@as(u8, 128), c.g);
    try std.testing.expectEqual(@as(u8, 0), c.b);
    try std.testing.expectEqual(@as(u8, 64), c.a);
}

test "fromColor: ints clamped to 0..255, alpha optional" {
    const I = struct { r: i32, g: i32, b: i32 };
    const c = Color.fromColor(I{ .r = 999, .g = -3, .b = 42 });
    try std.testing.expectEqual(@as(u8, 255), c.r);
    try std.testing.expectEqual(@as(u8, 0), c.g);
    try std.testing.expectEqual(@as(u8, 42), c.b);
    try std.testing.expectEqual(@as(u8, 255), c.a);
}

test "F32 view roundtrip" {
    const c = Color{ .r = 10, .g = 200, .b = 30, .a = 128 };
    const f = Color.F32.fromColor(c);
    const back = f.toColor();
    try std.testing.expectEqual(c.r, back.r);
    try std.testing.expectEqual(c.g, back.g);
    try std.testing.expectEqual(c.b, back.b);
    try std.testing.expectEqual(c.a, back.a);
}
