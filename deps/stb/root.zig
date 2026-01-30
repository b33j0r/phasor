//! Thin C wrapper for stb_truetype.

pub const c = @cImport({
    @cInclude("stb_truetype.h");
});
