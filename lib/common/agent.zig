const std = @import("std");
const channel_mod = @import("channel.zig");

pub fn Agent(comptime InboxT: type, comptime OutboxT: type) type {
    return struct {
        inbox_sender: ChannelT(InboxT).Sender,
        task_inbox: ?ChannelT(InboxT).Receiver,
        outbox_receiver: ChannelT(OutboxT).Receiver,
        task_outbox: ?ChannelT(OutboxT).Sender,
        future: ?std.Io.Future(anyerror!void) = null,

        const Self = @This();

        fn ChannelT(comptime T: type) type {
            return channel_mod.Channel(T);
        }

        pub fn init(allocator: std.mem.Allocator, io: *const std.Io, inbox_capacity: usize, outbox_capacity: usize) !Self {
            var inbox = try ChannelT(InboxT).init(allocator, io, inbox_capacity);
            errdefer inbox.deinit();
            var outbox = try ChannelT(OutboxT).init(allocator, io, outbox_capacity);
            errdefer outbox.deinit();

            const inbox_split = inbox.split();
            const outbox_split = outbox.split();
            inbox.deinit();
            outbox.deinit();

            return .{
                .inbox_sender = inbox_split.sender,
                .task_inbox = inbox_split.receiver,
                .outbox_receiver = outbox_split.receiver,
                .task_outbox = outbox_split.sender,
            };
        }

        pub fn deinit(self: *Self, io: std.Io) void {
            self.inbox_sender.close();

            if (self.future) |*future| {
                _ = future.await(io) catch {};
                self.future = null;
            }

            if (self.task_inbox) |*receiver| {
                receiver.deinit();
                self.task_inbox = null;
            }
            if (self.task_outbox) |*sender| {
                sender.deinit();
                self.task_outbox = null;
            }

            self.inbox_sender.deinit();
            self.outbox_receiver.deinit();
            self.* = undefined;
        }

        pub fn start(self: *Self, io: std.Io, comptime run_fn: anytype, context: anytype) !void {
            if (self.future != null) return error.AgentAlreadyStarted;

            const inbox = self.task_inbox orelse return error.AgentAlreadyStarted;
            const outbox = self.task_outbox orelse return error.AgentAlreadyStarted;
            self.task_inbox = null;
            self.task_outbox = null;

            const ContextT = @TypeOf(context);
            const Task = struct {
                fn run(task_io: std.Io, task_inbox: ChannelT(InboxT).Receiver, task_outbox: ChannelT(OutboxT).Sender, task_context: ContextT) anyerror!void {
                    var inbox_handle = task_inbox;
                    defer inbox_handle.deinit();
                    var outbox_handle = task_outbox;
                    defer outbox_handle.deinit();
                    try @call(.auto, run_fn, .{ task_io, inbox_handle, outbox_handle, task_context });
                }
            };

            self.future = try std.Io.concurrent(io, Task.run, .{ io, inbox, outbox, context });
        }

        pub fn send(self: *Self, value: InboxT) !void {
            try self.inbox_sender.send(value);
        }

        pub fn trySend(self: *Self, value: InboxT) !bool {
            return self.inbox_sender.trySend(value);
        }

        pub fn recv(self: *Self) !OutboxT {
            return self.outbox_receiver.recv();
        }

        pub fn tryRecv(self: *Self) ?OutboxT {
            return self.outbox_receiver.tryRecv();
        }

        pub fn join(self: *Self, io: std.Io) anyerror!void {
            if (self.future) |*future| {
                const result = future.await(io);
                self.future = null;
                return result;
            }
        }
    };
}

test "agent runs a concurrent task and exchanges channel messages" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    const Inbox = enum { ping, shutdown };
    const Outbox = enum { pong, stopped };

    var agent = try Agent(Inbox, Outbox).init(allocator, &io, 2, 2);
    defer agent.deinit(io);

    try agent.start(io, struct {
        fn run(_: std.Io, inbox: channel_mod.Channel(Inbox).Receiver, outbox: channel_mod.Channel(Outbox).Sender, _: void) anyerror!void {
            while (true) {
                switch (try inbox.recv()) {
                    .ping => try outbox.send(.pong),
                    .shutdown => {
                        try outbox.send(.stopped);
                        return;
                    },
                }
            }
        }
    }.run, {});

    try agent.send(.ping);
    try std.testing.expectEqual(Outbox.pong, try agent.recv());
    try agent.send(.shutdown);
    try std.testing.expectEqual(Outbox.stopped, try agent.recv());
    try agent.join(io);
}
