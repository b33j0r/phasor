//! Thin C wrapper for cgltf.

pub const c = @cImport({
    @cInclude("cgltf.h");
});
