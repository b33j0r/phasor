test "import tests" {
    _ = mesh_formats;
    _ = mesh_bake;
}

pub const mesh_formats = @import("mesh_formats.zig");
pub const mesh_bake = @import("mesh_bake.zig");

pub const Header = mesh_formats.Header;
pub const Mesh = mesh_formats.Mesh;
pub const Vertex = mesh_formats.Vertex;
pub const File = mesh_formats.File;
pub const Builder = mesh_bake.Builder;
