pub const Metrics = struct {
    fps: f32 = 0.0,
    max_fps: f32 = 0.0,
    frame_ms: f32 = 0.0,
};

pub const MetricMode = enum {
    stat,
    gauge,
    counter,
    event,
};

pub const MetricValue = union(enum) {
    f64: f64,
    i64: i64,
    u64: u64,
    bool: bool,

    pub fn from(value: anytype) MetricValue {
        return switch (@typeInfo(@TypeOf(value))) {
            .bool => .{ .bool = value },
            .float, .comptime_float => .{ .f64 = @floatCast(value) },
            .int, .comptime_int => blk: {
                if (@TypeOf(value) == u64 or @TypeOf(value) == usize) break :blk .{ .u64 = @intCast(value) };
                if (@TypeOf(value) == i64 or @TypeOf(value) == isize) break :blk .{ .i64 = @intCast(value) };
                if (@TypeOf(value) == u32 or @TypeOf(value) == u16 or @TypeOf(value) == u8) break :blk .{ .u64 = @intCast(value) };
                if (@TypeOf(value) == i32 or @TypeOf(value) == i16 or @TypeOf(value) == i8) break :blk .{ .i64 = @intCast(value) };
                break :blk .{ .i64 = @intCast(value) };
            },
            else => @compileError("Unsupported metric value type"),
        };
    }

    pub fn asF64(self: MetricValue) f64 {
        return switch (self) {
            .f64 => |v| v,
            .i64 => |v| @floatFromInt(v),
            .u64 => |v| @floatFromInt(v),
            .bool => |v| if (v) 1.0 else 0.0,
        };
    }
};

pub const Metric = struct {
    mode: MetricMode = .stat,
    value: MetricValue,
    unit: ?[]const u8 = null,
};

pub fn stat(value: anytype) Metric {
    return .{ .mode = .stat, .value = MetricValue.from(value) };
}

pub fn gauge(value: anytype) Metric {
    return .{ .mode = .gauge, .value = MetricValue.from(value) };
}

pub fn counter(value: anytype) Metric {
    return .{ .mode = .counter, .value = MetricValue.from(value) };
}

pub fn event(value: anytype) Metric {
    return .{ .mode = .event, .value = MetricValue.from(value) };
}

pub const Entry = struct {
    name: []const u8,
    mode: MetricMode,
    value: MetricValue,
    unit: ?[]const u8 = null,
};

pub const Event = struct {
    count: u8 = 0,
    entries: [Bus.max_entries]Entry = undefined,
};

pub const Bus = struct {
    channel: common.Channel(Event),
    enabled: bool = true,

    pub const max_entries: usize = 32;

    pub const Config = struct {
        capacity: usize = 256,
        enabled: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator, io: *const std.Io, config: Config) !Bus {
        return .{
            .channel = try common.Channel(Event).init(allocator, io, config.capacity),
            .enabled = config.enabled,
        };
    }

    pub fn deinit(self: *Bus) void {
        self.channel.deinit();
        self.* = undefined;
    }
};

pub inline fn emit(comptime enabled: bool, io: std.Io, bus: *Bus, payload: anytype) void {
    if (!enabled) return;
    if (!bus.enabled) return;
    _ = tryEmit(io, bus, payload) catch {};
}

pub fn tryEmit(io: std.Io, bus: *Bus, payload: anytype) !void {
    if (!bus.enabled) return;
    const metric_event = try buildEvent(payload);
    try putMetric(io, bus, metric_event);
}

pub inline fn emitBus(comptime enabled: bool, bus: *Bus, payload: anytype) void {
    if (!enabled) return;
    if (!bus.enabled) return;
    _ = tryEmitBus(bus, payload) catch {};
}

pub fn tryEmitBus(bus: *Bus, payload: anytype) !void {
    if (!bus.enabled) return;
    const metric_event = try buildEvent(payload);
    try putMetric(bus, metric_event);
}

fn putMetric(bus: *Bus, metric_event: Event) !void {
    if (builtin.target.cpu.arch.isWasm()) {
        _ = try bus.channel.trySend(metric_event);
        return;
    }
    try bus.channel.send(metric_event);
}

fn buildEvent(payload: anytype) !Event {
    const PayloadT = @TypeOf(payload);
    const info = @typeInfo(PayloadT);
    if (info != .@"struct") {
        @compileError("metrics.emit payload must be a struct literal");
    }
    const fields = info.@"struct".fields;
    if (fields.len > Bus.max_entries) {
        @compileError("metrics.emit payload has too many fields for the bus event");
    }

    var metric_event = Event{ .count = 0, .entries = undefined };
    inline for (fields) |field| {
        const name = field.name;
        const input = @field(payload, name);
        const metric = coerceMetric(input);
        metric_event.entries[metric_event.count] = .{
            .name = name,
            .mode = metric.mode,
            .value = metric.value,
            .unit = metric.unit,
        };
        metric_event.count += 1;
    }

    return metric_event;
}

fn coerceMetric(input: anytype) Metric {
    const T = @TypeOf(input);
    if (T == Metric) return input;
    if (@hasField(T, "mode") and @hasField(T, "value")) {
        const mode = @field(input, "mode");
        const value = @field(input, "value");
        const unit = if (@hasField(T, "unit")) @field(input, "unit") else null;
        return .{
            .mode = mode,
            .value = MetricValue.from(value),
            .unit = unit,
        };
    }
    @compileError("metrics.emit payload fields must be metrics.Metric or have { mode, value }");
}

pub const Sample = struct {
    name: []const u8,
    mode: MetricMode,
    value: MetricValue,
    unit: ?[]const u8 = null,
    count: u64 = 0,
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMapUnmanaged(u64, Sample) = .empty,

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Store) void {
        self.map.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn applyEvent(self: *Store, metric_event: Event) void {
        var i: usize = 0;
        while (i < metric_event.count) : (i += 1) {
            self.apply(metric_event.entries[i]);
        }
    }

    pub fn apply(self: *Store, entry: Entry) void {
        const key = metricKey(entry.name);
        if (self.map.getPtr(key)) |sample| {
            sample.unit = entry.unit orelse sample.unit;
            switch (entry.mode) {
                .counter => {
                    sample.value = addValues(sample.value, entry.value);
                    sample.count += 1;
                },
                .event => {
                    sample.value = entry.value;
                    sample.count += 1;
                },
                .stat, .gauge => {
                    sample.value = entry.value;
                    sample.count += 1;
                },
            }
            sample.mode = entry.mode;
            return;
        }

        _ = self.map.put(self.allocator, key, Sample{
            .name = entry.name,
            .mode = entry.mode,
            .value = entry.value,
            .unit = entry.unit,
            .count = 1,
        }) catch {};
    }

    pub fn get(self: *Store, name: []const u8) ?Sample {
        return self.map.get(metricKey(name));
    }
};

fn metricKey(name: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(name);
    return hasher.final();
}

fn addValues(a: MetricValue, b: MetricValue) MetricValue {
    return .{ .f64 = a.asF64() + b.asF64() };
}

// Imports
const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");
