//! Thin C wrapper for stb_image.

const builtin = @import("builtin");

pub const c = if (builtin.target.cpu.arch.isWasm())
    struct {
        pub extern fn stbi_load_from_memory(
            buffer: [*]const u8,
            len: c_int,
            x: *c_int,
            y: *c_int,
            channels_in_file: *c_int,
            desired_channels: c_int,
        ) ?[*]u8;

        pub extern fn stbi_image_free(retval_from_stbi_load: ?*anyopaque) void;
    }
else
    @cImport({
        @cInclude("stb_image.h");
    });
