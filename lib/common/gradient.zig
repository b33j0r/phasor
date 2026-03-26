const std = @import("std");
const Color = @import("Color.zig");

const Self = @This();

inner: *const anyopaque,
vtable: *const VTable,

pub const ColorStop = struct {
    at: f32,
    color: Color.F32,
};

pub const VTable = struct {
    sample: *const fn (inner: *const anyopaque, t: f32) Color.F32,
    stop_count: *const fn (inner: *const anyopaque) usize,
    stop_at: *const fn (inner: *const anyopaque, index: usize) ColorStop,
};

pub const samplers = struct {
    pub const Linear = struct {
        pub fn sample(stops: []const ColorStop, t: f32) Color.F32 {
            const clamped_t = std.math.clamp(t, 0.0, 1.0);
            if (stops.len == 0) unreachable;
            if (stops.len == 1) return stops[0].color;
            if (clamped_t <= stops[0].at) return stops[0].color;

            var i: usize = 1;
            while (i < stops.len) : (i += 1) {
                const right = stops[i];
                if (clamped_t <= right.at) {
                    const left = stops[i - 1];
                    const span = @max(right.at - left.at, 0.0001);
                    const local_t = std.math.clamp((clamped_t - left.at) / span, 0.0, 1.0);
                    return lerpColor(left.color, right.color, local_t);
                }
            }
            return stops[stops.len - 1].color;
        }
    };
};

pub fn initComptime(comptime spec: anytype) Self {
    const Impl = ComptimeGradient(spec);
    return Impl.interface();
}

pub fn sample(self: Self, t: f32) Color.F32 {
    return self.vtable.sample(self.inner, t);
}

pub fn sampleColor(self: Self, t: f32) Color {
    return self.sample(t).toColor();
}

pub fn stopCount(self: Self) usize {
    return self.vtable.stop_count(self.inner);
}

pub fn stop(self: Self, index: usize) ColorStop {
    return self.vtable.stop_at(self.inner, index);
}

pub fn ComptimeGradient(comptime spec: anytype) type {
    const SpecT = @TypeOf(spec);
    comptime {
        if (!@hasField(SpecT, "stops")) {
            @compileError("Gradient.initComptime(spec) requires a .stops field");
        }
    }

    const Sampler = if (@hasField(SpecT, "sampler")) spec.sampler else samplers.Linear;
    const stops = comptime normalizeStops(spec.stops);

    return struct {
        const Impl = @This();

        stops: [stops.len]ColorStop = stops,

        const instance: Impl = .{};

        pub fn interface() Self {
            return .{
                .inner = @ptrCast(&instance),
                .vtable = &.{
                    .sample = vt.sample,
                    .stop_count = vt.stopCount,
                    .stop_at = vt.stopAt,
                },
            };
        }

        const vt = struct {
            fn sample(inner: *const anyopaque, t: f32) Color.F32 {
                const self: *const Impl = @ptrCast(@alignCast(inner));
                return Sampler.sample(self.stops[0..], t);
            }

            fn stopCount(inner: *const anyopaque) usize {
                const self: *const Impl = @ptrCast(@alignCast(inner));
                return self.stops.len;
            }

            fn stopAt(inner: *const anyopaque, index: usize) ColorStop {
                const self: *const Impl = @ptrCast(@alignCast(inner));
                return self.stops[index];
            }
        };
    };
}

fn normalizeStops(comptime raw_stops: anytype) [comptimeStopCount(raw_stops)]ColorStop {
    const count = comptimeStopCount(raw_stops);
    if (count == 0) @compileError("Gradient.initComptime(spec) requires at least one stop");

    var out: [count]ColorStop = undefined;
    inline for (raw_stops, 0..) |raw_stop, i| {
        const StopT = @TypeOf(raw_stop);
        if (!@hasField(StopT, "at")) {
            @compileError("Gradient stop requires .at");
        }
        if (!@hasField(StopT, "color")) {
            @compileError("Gradient stop requires .color");
        }

        const at: f32 = raw_stop.at;
        if (!(at >= 0.0 and at <= 1.0)) {
            @compileError("Gradient stop .at must be within [0, 1]");
        }
        if (i > 0 and at < out[i - 1].at) {
            @compileError("Gradient stops must be sorted by ascending .at");
        }
        out[i] = .{
            .at = at,
            .color = normalizeColor(raw_stop.color),
        };
    }
    return out;
}

fn comptimeStopCount(comptime raw_stops: anytype) usize {
    return switch (@typeInfo(@TypeOf(raw_stops))) {
        .@"struct" => |info| if (info.is_tuple) info.fields.len else @compileError("Gradient .stops must be a tuple"),
        else => @compileError("Gradient .stops must be a tuple"),
    };
}

fn normalizeColor(comptime value: anytype) Color.F32 {
    return switch (@TypeOf(value)) {
        Color => Color.F32.fromColor(value),
        Color.F32 => value,
        else => Color.F32.fromColor(Color.fromColor(value)),
    };
}

fn lerpColor(a: Color.F32, b: Color.F32, t: f32) Color.F32 {
    const u = std.math.clamp(t, 0.0, 1.0);
    return .{
        .r = std.math.lerp(a.r, b.r, u),
        .g = std.math.lerp(a.g, b.g, u),
        .b = std.math.lerp(a.b, b.b, u),
        .a = std.math.lerp(a.a, b.a, u),
    };
}

test "Gradient samples linearly across color stops" {
    const fire = Self.initComptime(.{
        .stops = .{
            .{ .at = 0.0, .color = Color.rgb(255, 240, 220) },
            .{ .at = 1.0, .color = Color.rgba(120, 12, 6, 0) },
        },
    });

    const mid = fire.sample(0.5);
    try std.testing.expectApproxEqRel(@as(f32, 0.7352941), mid.r, 1e-5);
    try std.testing.expectApproxEqRel(@as(f32, 0.49411765), mid.g, 1e-5);
    try std.testing.expectApproxEqRel(@as(f32, 0.44313726), mid.b, 1e-5);
    try std.testing.expectApproxEqRel(@as(f32, 0.5), mid.a, 1e-5);
}

test "Gradient clamps outside stop range" {
    const ramp = Self.initComptime(.{
        .stops = .{
            .{ .at = 0.2, .color = Color.rgba(255, 200, 80, 255) },
            .{ .at = 0.8, .color = Color.rgba(10, 20, 30, 32) },
        },
    });

    try std.testing.expectEqual(ramp.stop(0).color.toColor(), ramp.sample(-1.0).toColor());
    try std.testing.expectEqual(ramp.stop(1).color.toColor(), ramp.sample(4.0).toColor());
}
