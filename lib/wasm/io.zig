const std = @import("std");

const Io = std.Io;
const Threaded = std.Io.Threaded;

pub fn io() Io {
    return Threaded.global_single_threaded.ioBasic();
}
