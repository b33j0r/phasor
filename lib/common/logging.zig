const std = @import("std");
const builtin = @import("builtin");

pub fn stdOptions(comptime level: std.log.Level) std.Options {
    return .{
        .log_level = level,
        .logFn = logFn,
    };
}

pub fn moduleStdOptions() std.Options {
    return .{
        .logFn = logFn,
    };
}

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    switch (builtin.os.tag) {
        .macos => emojiLogger(message_level, scope, format, args),
        else => ansiLogger(message_level, scope, format, args),
    }
}

pub fn emojiLogger(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);

    var buffer: [256]u8 = undefined;
    const stderr = std.debug.lockStderr(&buffer).terminal();
    defer std.debug.unlockStderr();

    writeEmojiLog(message_level, scope, format, args, stderr) catch {};
}

fn writeEmojiLog(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
    t: std.Io.Terminal,
) std.Io.Writer.Error!void {
    const prefix = switch (level) {
        .debug => "🔵",
        .info => "🟢",
        .warn => "🟡",
        .err => "🔴",
    };

    t.setColor(switch (level) {
        .err => .red,
        .warn => .yellow,
        .info => .green,
        .debug => .blue,
    }) catch {};
    t.setColor(.bold) catch {};
    try t.writer.print("{s} ", .{prefix});
    if (scope != .default) {
        try t.writer.print("[{t}] ", .{scope});
    }
    t.setColor(.reset) catch {};
    try t.writer.print(format ++ "\n", args);
}

pub fn ansiLogger(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);

    var buffer: [256]u8 = undefined;
    const stderr = std.debug.lockStderr(&buffer).terminal();
    defer std.debug.unlockStderr();

    writeAnsiLog(message_level, scope, format, args, stderr) catch {};
}

fn writeAnsiLog(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
    t: std.Io.Terminal,
) std.Io.Writer.Error!void {
    const prefix = switch (level) {
        .debug => "\x1b[34m●\x1b[0m",
        .info => "\x1b[32m●\x1b[0m",
        .warn => "\x1b[33m●\x1b[0m",
        .err => "\x1b[31m●\x1b[0m",
    };

    try t.writer.print("{s} ", .{prefix});
    if (scope != .default) {
        try t.writer.print("[{t}] ", .{scope});
    }
    try t.writer.print(format ++ "\n", args);
}
