test "import tests" {
    _ = utils;
}

pub const Color = common.Color;
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
pub const MaterialInstance = struct {
    material: Material,

    pub const default: MaterialInstance = .{ .material = undefined };
};
pub const Mesh = backend.Mesh;
pub const BackendMeshInstance = backend.MeshInstance;
pub const MeshInstance = mesh.MeshInstance;
pub const MeshHandle = mesh.MeshHandle;
pub const MeshLibrary = mesh.MeshLibrary;
pub const MeshFactory = mesh.MeshFactory;
pub const RenderItem = queue.RenderItem;
pub const RenderQueue = queue.RenderQueue;
pub const VertexColor = backend.VertexColor;
pub const VertexUv = backend.VertexUv;
pub const Triangle = backend.Triangle;
pub const TexturedQuad = backend.TexturedQuad;
pub const DrawCmd = backend.DrawCmd;
pub const Text = text.Text;
pub const Font = text.Font;
pub const DefaultFont = text.DefaultFont;
pub const HorizontalAlignment = text.HorizontalAlignment;
pub const VerticalAlignment = text.VerticalAlignment;
pub const textLayoutHash = text.layoutHash;
pub const buildTextMesh = text.buildMesh;
pub const Sprite = sprite.Sprite;
pub const spriteSizeHash = sprite.sizeHash;

pub const surface_glfw = if (builtin.target.cpu.arch.isWasm())
    struct {}
else
    @import("surface_glfw.zig");
pub const surface_canvas = @import("surface_canvas.zig");

const builtin = @import("builtin");
const utils = @import("utils.zig");
const queue = @import("queue.zig");
const common = @import("common");
const mesh = @import("mesh.zig");
const text = @import("text.zig");
const sprite = @import("sprite.zig");
const backend = if (builtin.target.cpu.arch.isWasm())
    @import("backend_web.zig")
else
    @import("backend_native.zig");
