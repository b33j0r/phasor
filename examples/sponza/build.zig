const std = @import("std");
const support = @import("build_phasor.zig");

pub fn build(b: *std.Build) void {
    support.buildExample(b, .{
        .name = "sponza",
        .root_source = "main.zig",
        .asset_dirs = &.{
            .{
                .source = "assets/sponza",
                .dest = "assets/sponza",
            },
        },
        .fetch = .{
            .step_name = "fetch-sponza",
            .step_description = "Download the Sponza glTF sample into assets/sponza",
            .tool_source = "fetch_sponza.zig",
        },
        .enable_wasm = false,
        .enable_physics = true,
    });
}
