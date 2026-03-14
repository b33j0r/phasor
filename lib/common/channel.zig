const std = @import("std");

pub fn Channel(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        io: *const std.Io,
        queue: std.Io.Queue(T),
        buffer: []T,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, io: *const std.Io, capacity: usize) !Self {
            if (capacity == 0) return error.InvalidCapacity;
            const buffer = try allocator.alloc(T, capacity);
            return .{
                .allocator = allocator,
                .io = io,
                .queue = std.Io.Queue(T).init(buffer),
                .buffer = buffer,
            };
        }

        pub fn deinit(self: *Self) void {
            self.close();
            self.allocator.free(self.buffer);
            self.* = undefined;
        }

        pub fn close(self: *Self) void {
            self.queue.close(self.io.*);
        }

        pub fn put(self: *Self, io: std.Io, values: []const T, limit: usize) !usize {
            return self.queue.put(io, values, limit);
        }

        pub fn get(self: *Self, io: std.Io, out: []T, limit: usize) !usize {
            return self.queue.get(io, out, limit);
        }

        pub fn putOneUncancelable(self: *Self, io: std.Io, value: T) !void {
            try self.queue.putOneUncancelable(io, value);
        }

        pub fn getOneUncancelable(self: *Self, io: std.Io) !T {
            return self.queue.getOneUncancelable(io);
        }

        pub fn send(self: *Self, value: T) !void {
            try self.putOneUncancelable(self.io.*, value);
        }

        pub fn trySend(self: *Self, value: T) !bool {
            var buffer = [_]T{value};
            const count = try self.put(self.io.*, &buffer, 0);
            return count != 0;
        }

        pub fn recv(self: *Self) !T {
            return self.getOneUncancelable(self.io.*);
        }

        pub fn tryRecv(self: *Self) ?T {
            var buffer: [1]T = undefined;
            const count = self.get(self.io.*, &buffer, 0) catch |err| switch (err) {
                error.Closed, error.Canceled => return null,
            };
            if (count == 0) return null;
            return buffer[0];
        }
    };
}

test "channel round-trips a value" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var channel = try Channel(u32).init(allocator, &io, 4);
    defer channel.deinit();

    try std.testing.expect(try channel.trySend(7));
    try std.testing.expectEqual(@as(?u32, 7), channel.tryRecv());
}
