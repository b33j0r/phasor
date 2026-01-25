const std = @import("std");
const Io = std.Io;
const Init = std.process.Init;

pub fn main(init: Init) !u8 {
    const arena: std.mem.Allocator = init.arena.allocator();
    const name = "Phasor";
    const greeting = try std.fmt.allocPrint(arena, "Hello, {s}!\n", .{name});

    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stderr(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.print("{s}", .{greeting});
    try stdout_writer.flush();
    return 0;
}
