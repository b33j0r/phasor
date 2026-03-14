const std = @import("std");

pub fn stdOptions(comptime level: std.log.Level) std.Options {
    return .{
        .log_level = level,
        .logFn = emojiLogFn,
    };
}

pub fn moduleStdOptions() std.Options {
    return .{
        .logFn = emojiLogFn,
    };
}

pub fn emojiLogFn(
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
