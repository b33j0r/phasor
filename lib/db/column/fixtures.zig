const std = @import("std");

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
