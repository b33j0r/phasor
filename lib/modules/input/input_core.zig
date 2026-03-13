//! Shared input types and helpers for all platform backends.

const std = @import("std");

pub const KeyPressed = struct { key: Key };
pub const KeyReleased = struct { key: Key };
pub const KeyDown = struct { key: Key };
pub const MouseDelta = struct { dx: f32, dy: f32 };
pub const MouseCapture = struct { enabled: bool = false };
pub const MouseButton = enum(u8) {
    left = 0,
    right = 1,
    middle = 2,
};

pub const Keyboard = struct {
    current: u128 = 0,
    previous: u128 = 0,

    pub fn isKeyDown(self: *const Keyboard, key: Key) bool {
        return isKeyDownBits(self.current, key);
    }

    pub fn isKeyPressed(self: *const Keyboard, key: Key) bool {
        return isKeyDownBits(self.current, key) and !isKeyDownBits(self.previous, key);
    }

    pub fn isKeyReleased(self: *const Keyboard, key: Key) bool {
        return !isKeyDownBits(self.current, key) and isKeyDownBits(self.previous, key);
    }

    pub fn setKeyDown(self: *Keyboard, key: Key) void {
        const idx = keyToIndex(key);
        if (idx >= 128) return;
        self.current |= (@as(u128, 1) << @intCast(idx));
    }

    pub fn setKeyUp(self: *Keyboard, key: Key) void {
        const idx = keyToIndex(key);
        if (idx >= 128) return;
        self.current &= ~(@as(u128, 1) << @intCast(idx));
    }
};

pub const Mouse = struct {
    delta_x: f32 = 0.0,
    delta_y: f32 = 0.0,
    x: f32 = 0.0,
    y: f32 = 0.0,
    previous_x: f32 = 0.0,
    previous_y: f32 = 0.0,
    last_x: f64 = 0.0,
    last_y: f64 = 0.0,
    current_buttons: u8 = 0,
    previous_buttons: u8 = 0,
    has_position: bool = false,
    has_last: bool = false,
    captured: bool = false,

    pub fn isButtonDown(self: *const Mouse, button: MouseButton) bool {
        return (self.current_buttons & buttonMask(button)) != 0;
    }

    pub fn isButtonPressed(self: *const Mouse, button: MouseButton) bool {
        const mask = buttonMask(button);
        return (self.current_buttons & mask) != 0 and (self.previous_buttons & mask) == 0;
    }

    pub fn isButtonReleased(self: *const Mouse, button: MouseButton) bool {
        const mask = buttonMask(button);
        return (self.current_buttons & mask) == 0 and (self.previous_buttons & mask) != 0;
    }

    pub fn moved(self: *const Mouse) bool {
        if (!self.has_position) return false;
        return self.x != self.previous_x or self.y != self.previous_y;
    }
};

fn buttonMask(button: MouseButton) u8 {
    return @as(u8, 1) << @as(u3, @intCast(@intFromEnum(button)));
}

pub fn keyFromInt(value: u32) ?Key {
    const signed = std.math.cast(c_int, value) orelse return null;
    inline for (std.meta.fields(Key)) |field| {
        if (@as(c_int, @intCast(field.value)) == signed) {
            return @enumFromInt(signed);
        }
    }
    return null;
}

fn isKeyDownBits(bits: u128, key: Key) bool {
    const idx = keyToIndex(key);
    if (idx >= 128) return false;
    return (bits & (@as(u128, 1) << @intCast(idx))) != 0;
}

fn keyToIndex(key: Key) u8 {
    return switch (key) {
        .space => 0,
        .a => 1,
        .b => 2,
        .c => 3,
        .d => 4,
        .e => 5,
        .f => 6,
        .g => 7,
        .h => 8,
        .i => 9,
        .j => 10,
        .k => 11,
        .l => 12,
        .m => 13,
        .n => 14,
        .o => 15,
        .p => 16,
        .q => 17,
        .r => 18,
        .s => 19,
        .t => 20,
        .u => 21,
        .v => 22,
        .w => 23,
        .x => 24,
        .y => 25,
        .z => 26,
        .left => 27,
        .right => 28,
        .up => 29,
        .down => 30,
        .escape => 31,
        .enter => 32,
        else => 255,
    };
}

pub const keys_to_poll = [_]Key{
    .space, .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
    .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z,
    .left, .right, .up, .down, .escape, .enter,
};

pub const Key = enum(c_int) {
    space = 32,
    apostrophe = 39,
    comma = 44,
    minus = 45,
    period = 46,
    slash = 47,
    zero = 48,
    one = 49,
    two = 50,
    three = 51,
    four = 52,
    five = 53,
    six = 54,
    seven = 55,
    eight = 56,
    nine = 57,
    semicolon = 59,
    equal = 61,
    a = 65,
    b = 66,
    c = 67,
    d = 68,
    e = 69,
    f = 70,
    g = 71,
    h = 72,
    i = 73,
    j = 74,
    k = 75,
    l = 76,
    m = 77,
    n = 78,
    o = 79,
    p = 80,
    q = 81,
    r = 82,
    s = 83,
    t = 84,
    u = 85,
    v = 86,
    w = 87,
    x = 88,
    y = 89,
    z = 90,
    left_bracket = 91,
    backslash = 92,
    right_bracket = 93,
    grave_accent = 96,
    escape = 256,
    enter = 257,
    tab = 258,
    backspace = 259,
    insert = 260,
    delete = 261,
    right = 262,
    left = 263,
    down = 264,
    up = 265,
    page_up = 266,
    page_down = 267,
    home = 268,
    end = 269,
    caps_lock = 280,
    scroll_lock = 281,
    num_lock = 282,
    print_screen = 283,
    pause = 284,
    f1 = 290,
    f2 = 291,
    f3 = 292,
    f4 = 293,
    f5 = 294,
    f6 = 295,
    f7 = 296,
    f8 = 297,
    f9 = 298,
    f10 = 299,
    f11 = 300,
    f12 = 301,
    left_shift = 340,
    left_control = 341,
    left_alt = 342,
    left_super = 343,
    right_shift = 344,
    right_control = 345,
    right_alt = 346,
    right_super = 347,

    pub fn toGlfwKey(self: Key) c_int {
        return @intFromEnum(self);
    }
};
