test "import tests" {
    _ = utils;
}

const builtin = @import("builtin");
const utils = @import("utils.zig");
const backend = if (builtin.target.cpu.arch.isWasm())
    @import("backend_web.zig")
else
    @import("backend_native.zig");

pub const Color = utils.Color;
pub const Size = utils.Size;
pub const SurfaceTarget = utils.SurfaceTarget;

pub const RendererConfig = backend.RendererConfig;
pub const Renderer = backend.Renderer;
pub const Frame = backend.Frame;
pub const Buffer = backend.Buffer;
pub const Texture = backend.Texture;
pub const Sampler = backend.Sampler;
pub const Pipeline = backend.Pipeline;
pub const Material = backend.Material;
pub const Mesh = backend.Mesh;
pub const MeshInstance = backend.MeshInstance;
pub const VertexColor = backend.VertexColor;
pub const VertexUv = backend.VertexUv;
pub const Triangle = backend.Triangle;
pub const TexturedQuad = backend.TexturedQuad;
pub const DrawCmd = backend.DrawCmd;

pub const surface_glfw = if (builtin.target.cpu.arch.isWasm())
    struct {}
else
    @import("surface_glfw.zig");
pub const surface_canvas = @import("surface_canvas.zig");
