const std = @import("std");

pub fn Channel(comptime T: type) type {
    return struct {
        sender: Sender,
        receiver: Receiver,

        const Self = @This();

        const Inner = struct {
            allocator: std.mem.Allocator,
            io: *const std.Io,
            queue: std.Io.Queue(T),
            buffer: []T,
            mutex: std.Io.Mutex = .init,
            ref_count: usize = 2,
            sender_count: usize = 1,
            receiver_live: bool = true,
        };

        pub const Split = struct {
            sender: Sender,
            receiver: Receiver,
        };

        pub fn init(allocator: std.mem.Allocator, io: *const std.Io, queue_capacity: usize) !Self {
            if (queue_capacity == 0) return error.InvalidCapacity;

            const inner = try allocator.create(Inner);
            errdefer allocator.destroy(inner);
            const buffer = try allocator.alloc(T, queue_capacity);
            errdefer allocator.free(buffer);

            inner.* = .{
                .allocator = allocator,
                .io = io,
                .queue = std.Io.Queue(T).init(buffer),
                .buffer = buffer,
            };
            return .{
                .sender = .{ .inner = inner },
                .receiver = .{ .inner = inner },
            };
        }

        pub fn deinit(self: *Self) void {
            self.sender.deinit();
            self.receiver.deinit();
            self.* = undefined;
        }

        pub fn split(self: *Self) Split {
            const out = Split{
                .sender = self.sender,
                .receiver = self.receiver,
            };
            self.sender.inner = null;
            self.receiver.inner = null;
            return out;
        }

        pub fn close(self: *Self) void {
            self.sender.close();
        }

        pub fn send(self: *Self, value: T) !void {
            try self.sender.send(value);
        }

        pub fn trySend(self: *Self, value: T) !bool {
            return self.sender.trySend(value);
        }

        pub fn recv(self: *Self) !T {
            return self.receiver.recv();
        }

        pub fn tryRecv(self: *Self) ?T {
            return self.receiver.tryRecv();
        }

        pub fn capacity(self: *const Self) usize {
            return self.sender.capacity();
        }

        pub const Sender = struct {
            inner: ?*Inner,

            pub fn clone(self: Sender) Sender {
                const inner = self.inner orelse @panic("attempted to clone released Channel sender");
                retain(inner);
                inner.mutex.lockUncancelable(inner.io.*);
                inner.sender_count += 1;
                inner.mutex.unlock(inner.io.*);
                return .{ .inner = inner };
            }

            pub fn deinit(self: *Sender) void {
                const inner = self.inner orelse return;
                self.inner = null;

                var should_close = false;
                inner.mutex.lockUncancelable(inner.io.*);
                std.debug.assert(inner.sender_count > 0);
                inner.sender_count -= 1;
                should_close = inner.sender_count == 0;
                inner.mutex.unlock(inner.io.*);

                if (should_close) inner.queue.close(inner.io.*);
                release(inner);
            }

            pub fn close(self: Sender) void {
                const inner = self.inner orelse return;
                inner.queue.close(inner.io.*);
            }

            pub fn send(self: Sender, value: T) !void {
                const inner = self.inner orelse return error.Closed;
                try inner.queue.putOneUncancelable(inner.io.*, value);
            }

            pub fn trySend(self: Sender, value: T) !bool {
                const inner = self.inner orelse return error.Closed;
                var buffer = [_]T{value};
                return (try inner.queue.put(inner.io.*, &buffer, 0)) != 0;
            }

            pub fn capacity(self: Sender) usize {
                const inner = self.inner orelse return 0;
                return inner.queue.capacity();
            }
        };

        pub const Receiver = struct {
            inner: ?*Inner,

            pub fn deinit(self: *Receiver) void {
                const inner = self.inner orelse return;
                self.inner = null;

                var should_close = false;
                inner.mutex.lockUncancelable(inner.io.*);
                if (inner.receiver_live) {
                    inner.receiver_live = false;
                    should_close = true;
                }
                inner.mutex.unlock(inner.io.*);

                if (should_close) inner.queue.close(inner.io.*);
                release(inner);
            }

            pub fn close(self: Receiver) void {
                const inner = self.inner orelse return;
                inner.queue.close(inner.io.*);
            }

            pub fn recv(self: Receiver) !T {
                const inner = self.inner orelse return error.Closed;
                return inner.queue.getOneUncancelable(inner.io.*);
            }

            pub fn tryRecv(self: Receiver) ?T {
                const inner = self.inner orelse return null;
                var buffer: [1]T = undefined;
                const count = inner.queue.get(inner.io.*, &buffer, 0) catch |err| switch (err) {
                    error.Closed, error.Canceled => return null,
                };
                if (count == 0) return null;
                return buffer[0];
            }

            pub fn next(self: Receiver) ?T {
                return self.tryRecv();
            }
        };

        fn retain(inner: *Inner) void {
            inner.mutex.lockUncancelable(inner.io.*);
            inner.ref_count += 1;
            inner.mutex.unlock(inner.io.*);
        }

        fn release(inner: *Inner) void {
            var should_destroy = false;
            inner.mutex.lockUncancelable(inner.io.*);
            std.debug.assert(inner.ref_count > 0);
            inner.ref_count -= 1;
            should_destroy = inner.ref_count == 0;
            inner.mutex.unlock(inner.io.*);

            if (!should_destroy) return;
            inner.allocator.free(inner.buffer);
            inner.allocator.destroy(inner);
        }
    };
}
