const std = @import("std");
const support = @import("build_phasor.zig");

pub fn build(b: *std.Build) void {
    support.buildExample(b, .{
        .name = "window",
        .root_source = "main.zig",
        .enable_wasm = false,
    });
}
