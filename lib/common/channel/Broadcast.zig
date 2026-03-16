const std = @import("std");
const channel_mod = @import("Channel.zig");

pub fn Broadcast(comptime T: type) type {
    return struct {
        sender: Sender,
        controller: Controller,

        const Self = @This();
        const ChannelT = channel_mod.Channel(T);

        const Inner = struct {
            allocator: std.mem.Allocator,
            io: *const std.Io,
            capacity: usize,
            mutex: std.Io.Mutex = .init,
            ref_count: usize = 2,
            sender_count: usize = 1,
            next_id: u64 = 1,
            closed: bool = false,
            subscribers: std.AutoHashMapUnmanaged(u64, Subscriber) = .empty,
        };

        const Subscriber = struct {
            sender: ChannelT.Sender,
        };

        pub fn init(allocator: std.mem.Allocator, io: *const std.Io, capacity: usize) !Self {
            if (capacity == 0) return error.InvalidCapacity;

            const inner = try allocator.create(Inner);
            inner.* = .{
                .allocator = allocator,
                .io = io,
                .capacity = capacity,
            };

            return .{
                .sender = .{ .inner = inner },
                .controller = .{ .inner = inner },
            };
        }

        pub fn deinit(self: *Self) void {
            self.sender.deinit();
            self.controller.deinit();
            self.* = undefined;
        }

        pub fn send(self: *Self, value: T) !void {
            try self.sender.send(value);
        }

        pub fn trySend(self: *Self, value: T) !void {
            try self.sender.trySend(value);
        }

        pub fn subscribe(self: *Self) !Receiver {
            return self.controller.subscribe();
        }

        pub fn close(self: *Self) void {
            self.sender.close();
        }

        pub const Sender = struct {
            inner: ?*Inner,

            pub fn clone(self: Sender) Sender {
                const inner = self.inner orelse @panic("attempted to clone released Broadcast sender");
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

                if (should_close) closeAll(inner);
                release(inner);
            }

            pub fn close(self: Sender) void {
                const inner = self.inner orelse return;
                closeAll(inner);
            }

            pub fn send(self: Sender, value: T) !void {
                const inner = self.inner orelse return error.Closed;
                inner.mutex.lockUncancelable(inner.io.*);
                defer inner.mutex.unlock(inner.io.*);

                if (inner.closed) return error.Closed;

                var it = inner.subscribers.valueIterator();
                while (it.next()) |subscriber| {
                    try subscriber.sender.send(value);
                }
            }

            pub fn trySend(self: Sender, value: T) !void {
                const inner = self.inner orelse return error.Closed;
                inner.mutex.lockUncancelable(inner.io.*);
                defer inner.mutex.unlock(inner.io.*);

                if (inner.closed) return error.Closed;

                var it = inner.subscribers.valueIterator();
                while (it.next()) |subscriber| {
                    const queued = try subscriber.sender.trySend(value);
                    if (!queued) return error.QueueFull;
                }
            }
        };

        pub const Controller = struct {
            inner: ?*Inner,

            pub fn deinit(self: *Controller) void {
                const inner = self.inner orelse return;
                self.inner = null;
                release(inner);
            }

            pub fn subscribe(self: Controller) !Receiver {
                const inner = self.inner orelse return error.Closed;

                var channel = try ChannelT.init(inner.allocator, inner.io, inner.capacity);
                var split = channel.split();
                channel.deinit();

                inner.mutex.lockUncancelable(inner.io.*);
                defer inner.mutex.unlock(inner.io.*);

                const id = inner.next_id;
                inner.next_id += 1;

                if (inner.closed) {
                    split.sender.close();
                }

                try inner.subscribers.put(inner.allocator, id, .{
                    .sender = split.sender,
                });

                inner.ref_count += 1;
                return .{
                    .inner = inner,
                    .id = id,
                    .channel = split.receiver,
                };
            }
        };

        pub const Receiver = struct {
            inner: ?*Inner,
            id: u64,
            channel: ChannelT.Receiver,

            pub fn deinit(self: *Receiver) void {
                const inner = self.inner orelse {
                    self.channel.deinit();
                    return;
                };
                self.inner = null;

                var sender: ?ChannelT.Sender = null;
                inner.mutex.lockUncancelable(inner.io.*);
                if (inner.subscribers.fetchRemove(self.id)) |entry| {
                    sender = entry.value.sender;
                }
                inner.mutex.unlock(inner.io.*);

                if (sender) |*sub_sender| sub_sender.deinit();
                self.channel.deinit();
                release(inner);
            }

            pub fn recv(self: Receiver) !T {
                return self.channel.recv();
            }

            pub fn tryRecv(self: Receiver) ?T {
                return self.channel.tryRecv();
            }

            pub fn next(self: Receiver) ?T {
                return self.channel.next();
            }
        };

        fn closeAll(inner: *Inner) void {
            inner.mutex.lockUncancelable(inner.io.*);
            if (inner.closed) {
                inner.mutex.unlock(inner.io.*);
                return;
            }
            inner.closed = true;

            var it = inner.subscribers.valueIterator();
            while (it.next()) |subscriber| {
                subscriber.sender.close();
            }
            inner.mutex.unlock(inner.io.*);
        }

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

            var it = inner.subscribers.valueIterator();
            while (it.next()) |subscriber| {
                var sender = subscriber.sender;
                sender.deinit();
            }
            inner.subscribers.deinit(inner.allocator);
            inner.allocator.destroy(inner);
        }
    };
}
