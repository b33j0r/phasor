const std = @import("std");

pub const Channel = @import("channel/Channel.zig").Channel;
pub const Broadcast = @import("channel/Broadcast.zig").Broadcast;

test "channel split sender clones close when last sender drops" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var channel = try Channel(u32).init(allocator, &io, 2);
    var split = channel.split();
    defer split.receiver.deinit();
    defer split.sender.deinit();
    defer channel.deinit();

    var sender_clone = split.sender.clone();
    defer sender_clone.deinit();

    try split.sender.send(1);
    try sender_clone.send(2);
    try std.testing.expectEqual(@as(u32, 1), try split.receiver.recv());
    try std.testing.expectEqual(@as(u32, 2), try split.receiver.recv());

    split.sender.deinit();
    try std.testing.expectEqual(@as(?u32, null), split.receiver.tryRecv());

    try sender_clone.send(3);
    try std.testing.expectEqual(@as(u32, 3), try split.receiver.recv());

    sender_clone.deinit();
    try std.testing.expectError(error.Closed, split.receiver.recv());
}

test "channel receiver drop closes senders" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var channel = try Channel(u32).init(allocator, &io, 1);
    var split = channel.split();
    defer split.sender.deinit();
    defer channel.deinit();

    split.receiver.deinit();

    try std.testing.expectError(error.Closed, split.sender.send(9));
    try std.testing.expectError(error.Closed, split.sender.send(10));
}

test "channel trySend and tryRecv obey capacity" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var channel = try Channel(u32).init(allocator, &io, 1);
    defer channel.deinit();

    try std.testing.expect(try channel.trySend(7));
    try std.testing.expect(!(try channel.trySend(8)));
    try std.testing.expectEqual(@as(?u32, 7), channel.tryRecv());
    try std.testing.expectEqual(@as(?u32, null), channel.tryRecv());
}

test "broadcast fans out and subscriber removal stops delivery" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var broadcast = try Broadcast(u32).init(allocator, &io, 2);
    defer broadcast.deinit();
    var first = try broadcast.subscribe();
    defer first.deinit();
    var second = try broadcast.subscribe();

    try broadcast.send(11);
    try std.testing.expectEqual(@as(u32, 11), try first.recv());
    try std.testing.expectEqual(@as(u32, 11), try second.recv());

    second.deinit();
    try broadcast.send(12);

    try std.testing.expectEqual(@as(u32, 12), try first.recv());
}

test "broadcast trySend reports subscriber backpressure" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var broadcast = try Broadcast(u32).init(allocator, &io, 1);
    defer broadcast.deinit();

    var receiver = try broadcast.subscribe();
    defer receiver.deinit();

    try broadcast.trySend(1);
    try std.testing.expectError(error.QueueFull, broadcast.trySend(2));
    try std.testing.expectEqual(@as(u32, 1), try receiver.recv());
}
