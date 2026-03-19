const std = @import("std");
const support = @import("build_phasor.zig");

pub fn build(b: *std.Build) void {
    support.buildExample(b, .{
        .name = "gltf",
        .root_source = "main.zig",
        .extra_modules = &.{
            .{
                .name = "gltf_embedded_assets",
                .source = .{
                    .phasor_path = "assets/gltf/embedded_assets.zig",
                },
            },
        },
    });
}
