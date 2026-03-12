pub fn Events(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        io: *const std.Io,
        queue_capacity: usize,
        subs: std.AutoHashMap(u64, *Subscription),
        mutex: std.Io.Mutex = .init,

        const Self = @This();
        const Subscription = struct {
            queue: std.Io.Queue(T),
            buffer: []T,
        };

        pub const Error = error{
            QueueClosed,
            QueueFull,
            Canceled,
            OutOfMemory,
        };

        pub fn init(allocator: std.mem.Allocator, io: *const std.Io, queue_capacity: usize) !Self {
            if (queue_capacity == 0) return error.InvalidCapacity;
            return .{
                .allocator = allocator,
                .io = io,
                .queue_capacity = queue_capacity,
                .subs = std.AutoHashMap(u64, *Subscription).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lockUncancelable(self.io.*);
            var it = self.subs.valueIterator();
            while (it.next()) |sub_ptr| {
                const sub = sub_ptr.*;
                sub.queue.close(self.io.*);
                self.allocator.free(sub.buffer);
                self.allocator.destroy(sub);
            }
            self.subs.deinit();
            self.mutex.unlock(self.io.*);
        }

        pub fn send(self: *Self, value: T) Error!void {
            const subs = try self.snapshotSubscriptions();
            defer self.allocator.free(subs);

            var futures: std.ArrayListUnmanaged(std.Io.Future(Error!void)) = .{};
            defer futures.deinit(self.allocator);

            const io_value = self.io.*;
            for (subs) |sub| {
                const future = std.Io.concurrent(io_value, sendToSubscription, .{ io_value, sub, value }) catch |err| switch (err) {
                    error.ConcurrencyUnavailable => {
                        try sendToSubscription(io_value, sub, value);
                        continue;
                    },
                };
                try futures.append(self.allocator, future);
            }

            for (futures.items) |*future| {
                try future.await(io_value);
            }
        }

        pub fn trySend(self: *Self, value: T) Error!void {
            const subs = try self.snapshotSubscriptions();
            defer self.allocator.free(subs);

            for (subs) |sub| {
                var buffer = [_]T{value};
                const queued = sub.queue.put(self.io.*, &buffer, 0) catch |err| switch (err) {
                    error.Closed => return Error.QueueClosed,
                    error.Canceled => return Error.Canceled,
                };
                if (queued == 0) return Error.QueueFull;
            }
        }

        pub fn makeKey(comptime system_fn: anytype) u64 {
            const system_ptr = @intFromPtr(&system_fn);
            const type_hash = meta.typeId(T);
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&system_ptr));
            hasher.update(std.mem.asBytes(&type_hash));
            return hasher.final();
        }

        pub fn subscribe(self: *Self, key: u64) !*Subscription {
            self.mutex.lockUncancelable(self.io.*);
            defer self.mutex.unlock(self.io.*);

            if (self.subs.get(key)) |existing| return existing;

            const sub = try self.allocator.create(Subscription);
            errdefer self.allocator.destroy(sub);
            const buffer = try self.allocator.alloc(T, self.queue_capacity);
            errdefer self.allocator.free(buffer);

            sub.* = .{
                .queue = std.Io.Queue(T).init(buffer),
                .buffer = buffer,
            };
            try self.subs.put(key, sub);
            return sub;
        }

        pub fn get(self: *Self, key: u64) ?*Subscription {
            self.mutex.lockUncancelable(self.io.*);
            defer self.mutex.unlock(self.io.*);
            return self.subs.get(key);
        }

        pub fn remove(self: *Self, key: u64) bool {
            self.mutex.lockUncancelable(self.io.*);
            defer self.mutex.unlock(self.io.*);
            if (self.subs.fetchRemove(key)) |kv| {
                const sub = kv.value;
                sub.queue.close(self.io.*);
                self.allocator.free(sub.buffer);
                self.allocator.destroy(sub);
                return true;
            }
            return false;
        }

        pub fn getSubscriptionCount(self: *Self) usize {
            self.mutex.lockUncancelable(self.io.*);
            defer self.mutex.unlock(self.io.*);
            return self.subs.count();
        }

        fn snapshotSubscriptions(self: *Self) ![]*Subscription {
            self.mutex.lockUncancelable(self.io.*);
            const count = self.subs.count();
            const subs = self.allocator.alloc(*Subscription, count) catch |err| {
                self.mutex.unlock(self.io.*);
                return err;
            };
            var i: usize = 0;
            var it = self.subs.valueIterator();
            while (it.next()) |sub_ptr| : (i += 1) {
                subs[i] = sub_ptr.*;
            }
            self.mutex.unlock(self.io.*);
            return subs;
        }

        fn sendToSubscription(io: std.Io, sub: *Subscription, value: T) Error!void {
            sub.queue.putOneUncancelable(io, value) catch |err| switch (err) {
                error.Closed => return Error.QueueClosed,
            };
        }
    };
}

pub fn EventWriter(comptime T: type) type {
    return struct {
        events: ?*Events(T) = null,

        const Self = @This();
        pub const Error = Events(T).Error || error{
            EventMustBeRegistered,
            EventNotInitialized,
        };

        pub fn init_system_param(self: *Self, comptime _: anytype, commands: *Commands) !void {
            self.events = commands.getResourceMut(Events(T));
            if (self.events == null) return error.EventMustBeRegistered;
        }

        pub fn send(self: Self, event: T) Error!void {
            const events = self.events orelse return error.EventNotInitialized;
            try events.send(event);
        }

        pub fn trySend(self: Self, event: T) Error!void {
            const events = self.events orelse return error.EventNotInitialized;
            try events.trySend(event);
        }
    };
}

pub fn EventReader(comptime T: type) type {
    return struct {
        events: ?*Events(T) = null,
        subscription: ?*Events(T).Subscription = null,

        const Self = @This();
        pub const Error = Events(T).Error || error{
            EventMustBeRegistered,
            EventNotInitialized,
            EventReaderNotSubscribed,
        };

        pub fn register_system_param(comptime system_fn: anytype, world: *World) !void {
            const events = world.getResourceMut(Events(T)) orelse return error.EventMustBeRegistered;
            const key = Events(T).makeKey(system_fn);
            _ = try events.subscribe(key);
        }

        pub fn unregister_system_param(comptime system_fn: anytype, world: *World) !void {
            const events = world.getResourceMut(Events(T)) orelse return;
            const key = Events(T).makeKey(system_fn);
            _ = events.remove(key);
        }

        pub fn init_system_param(self: *Self, comptime system_fn: anytype, commands: *Commands) !void {
            const events = commands.getResourceMut(Events(T)) orelse return error.EventMustBeRegistered;
            const key = Events(T).makeKey(system_fn);
            const sub = events.get(key) orelse return error.EventReaderNotSubscribed;
            self.events = events;
            self.subscription = sub;
        }

        pub fn deinit(self: *Self) void {
            self.events = null;
            self.subscription = null;
        }

        pub fn drain(self: Self) void {
            while (self.tryRecv()) |_| {}
        }

        pub fn recv(self: Self) Error!T {
            const events = self.events orelse return error.EventNotInitialized;
            const sub = self.subscription orelse return error.EventNotInitialized;
            return sub.queue.getOneUncancelable(events.io.*) catch |err| switch (err) {
                error.Closed => return Error.QueueClosed,
            };
        }

        pub fn tryRecv(self: Self) ?T {
            const events = self.events orelse return null;
            const sub = self.subscription orelse return null;
            var buffer: [1]T = undefined;
            const count = sub.queue.get(events.io.*, &buffer, 0) catch |err| switch (err) {
                error.Closed, error.Canceled => return null,
            };
            if (count == 0) return null;
            return buffer[0];
        }

        pub fn next(self: Self) ?T {
            return self.tryRecv();
        }
    };
}

// Tests
test "events send and receive through system params" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var app = try App.init(allocator, &io);
    defer app.deinit();

    try app.world.registerEvent(app.io, u32, 8);

    const Reader = EventReader(u32);
    const Writer = EventWriter(u32);
    const Received = struct { value: ?u32 = null };
    const sys_fn = struct {
        fn run(commands: *Commands, writer: Writer, reader: Reader) !void {
            try writer.send(42);
            const value = try reader.recv();
            try commands.insertResource(Received{ .value = value });
        }
    }.run;

    try app.schedule_manager.addSystem(&app.world, schedule_mod.DefaultSchedule.Update, sys_fn);
    try app.runScheduleByLabel(schedule_mod.DefaultSchedule.Update);

    const received = app.world.getResource(Received).?;
    try std.testing.expectEqual(@as(u32, 42), received.value.?);
}

test "events fan out to multiple readers" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var app = try App.init(allocator, &io);
    defer app.deinit();

    try app.world.registerEvent(app.io, u32, 4);

    const Reader = EventReader(u32);
    const Writer = EventWriter(u32);
    const ReceivedA = struct { value: ?u32 = null };
    const ReceivedB = struct { value: ?u32 = null };
    const sys_a = struct {
        fn run(commands: *Commands, reader: Reader) !void {
            const value = reader.tryRecv() orelse return;
            try commands.insertResource(ReceivedA{ .value = value });
        }
    }.run;
    const sys_b = struct {
        fn run(commands: *Commands, reader: Reader) !void {
            const value = reader.tryRecv() orelse return;
            try commands.insertResource(ReceivedB{ .value = value });
        }
    }.run;
    const sys_write = struct {
        fn run(writer: Writer) !void {
            try writer.send(7);
        }
    }.run;

    try app.schedule_manager.addSystem(&app.world, schedule_mod.DefaultSchedule.Update, sys_write);
    try app.schedule_manager.addSystem(&app.world, schedule_mod.DefaultSchedule.Update, sys_a);
    try app.schedule_manager.addSystem(&app.world, schedule_mod.DefaultSchedule.Update, sys_b);
    try app.runScheduleByLabel(schedule_mod.DefaultSchedule.Update);

    const received_a = app.world.getResource(ReceivedA).?;
    const received_b = app.world.getResource(ReceivedB).?;
    try std.testing.expectEqual(@as(u32, 7), received_a.value.?);
    try std.testing.expectEqual(@as(u32, 7), received_b.value.?);
}

test "events trySend reports full queues" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var app = try App.init(allocator, &io);
    defer app.deinit();

    try app.world.registerEvent(app.io, u32, 1);

    const Reader = EventReader(u32);
    const Writer = EventWriter(u32);
    const sys_fn = struct {
        fn run(writer: Writer) !void {
            try writer.trySend(1);
            try writer.trySend(2);
        }
    }.run;
    const sys_read = struct {
        fn run(_: Reader) void {}
    }.run;

    try app.schedule_manager.addSystem(&app.world, schedule_mod.DefaultSchedule.Update, sys_fn);
    try app.schedule_manager.addSystem(&app.world, schedule_mod.DefaultSchedule.Update, sys_read);

    try std.testing.expectError(error.QueueFull, app.runScheduleByLabel(schedule_mod.DefaultSchedule.Update));
}

// Imports
const std = @import("std");
const App = @import("App.zig");
const Commands = @import("Commands.zig");
const World = @import("World.zig");
const meta = @import("db").meta;
const schedule_mod = @import("schedule.zig");
