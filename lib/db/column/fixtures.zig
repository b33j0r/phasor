const std = @import("std");

pub const Position = struct { x: f32, y: f32 };
pub const Velocity = struct {
    dx: f32,
    dy: f32,
    pub const default = @This(){ .dx = 0, .dy = 0 };
};
pub const State = enum { idle, active, paused };
pub const Health = struct {
    hp: i32,
    pub const default = @This(){ .hp = 0 };
};
pub const ShipIsOnFire = struct { pub const default = @This(){}; };
pub const Tag = struct { pub const default = @This(){}; };

var zst_deinit_count: usize = 0;

pub const ZstDeinit = struct {
    pub fn initDefault() @This() {
        return .{};
    }

    pub fn deinit(_: *@This()) void {
        zst_deinit_count += 1;
    }
};

pub fn resetZstDeinitCount() void {
    zst_deinit_count = 0;
}

pub fn getZstDeinitCount() usize {
    return zst_deinit_count;
}

/// Test helper type that increments a counter on deinit.
pub fn DeinitCounterForTests(comptime N: usize) type {
    return struct {
        allocator: std.mem.Allocator,
        data: []u8,
        counter: *usize,

        pub fn init(allocator: std.mem.Allocator, counter: *usize) !@This() {
            return .{
                .allocator = allocator,
                .data = try allocator.alloc(u8, N),
                .counter = counter,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.data);
            self.counter.* += 1;
            self.* = undefined;
        }
    };
}
