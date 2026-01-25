const std = @import("std");
const Io = std.Io;
const Init = std.process.Init;

pub fn main(init: Init) !u8 {
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.print("Hello, Phasor!\n", .{});
    try stdout_writer.flush();
    return 0;
}