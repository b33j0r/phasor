pub const std_options = @import("common").logging.moduleStdOptions();

test "import tests" {
    _ = utils;
}

pub const Color = common.Color;
pub const Size = utils.Size;
pub const SurfaceTarget = utils.SurfaceTarget;

pub const RendererConfig = backend.RendererConfig;
pub const Renderer = backend.Renderer;
pub const RendererStats = backend.RendererStats;
pub const Frame = backend.Frame;
pub const FrameTarget = backend.FrameTarget;
pub const Buffer = backend.Buffer;
pub const Texture = backend.Texture;
pub const Sampler = backend.Sampler;
pub const SamplerDescriptor = backend.SamplerDescriptor;
pub const SamplerFilter = backend.SamplerFilter;
pub const SamplerAddressMode = backend.SamplerAddressMode;
pub const Pipeline = backend.Pipeline;
pub const Shader = backend.Shader;
pub const ShaderSource = backend.ShaderSource;
pub const ShaderVertexLayout = backend.ShaderVertexLayout;
pub const ShaderBindingMode = backend.ShaderBindingMode;
pub const BackendMaterial = backend.Material;
pub const Material = mesh.Material;
pub const SceneMaterial = mesh.SceneMaterial;
pub const SceneTexture = mesh.SceneTexture;
pub const max_scene_lights = @import("scene_uniforms.zig").max_scene_lights;
pub const SceneLightKind = @import("scene_uniforms.zig").SceneLightKind;
pub const SceneLight = @import("scene_uniforms.zig").SceneLight;
pub const SceneUniforms = @import("scene_uniforms.zig").SceneUniforms;
pub const MaterialInstance = struct {
    material: BackendMaterial,

    pub const default: MaterialInstance = .{ .material = undefined };
};
pub const Mesh = backend.Mesh;
pub const BackendMeshInstance = backend.MeshInstance;
pub const MeshInstance = mesh.MeshInstance;
pub const ShaderInstance = mesh.ShaderInstance;
pub const MeshHandle = mesh.MeshHandle;
pub const ShaderHandle = mesh.ShaderHandle;
pub const TextureHandle = mesh.TextureHandle;
pub const MaterialHandle = mesh.MaterialHandle;
pub const MeshLibrary = mesh.MeshLibrary;
pub const ShaderLibrary = mesh.ShaderLibrary;
pub const TextureLibrary = mesh.TextureLibrary;
pub const MaterialLibrary = mesh.MaterialLibrary;
pub const MeshFactory = mesh.MeshFactory;
pub const max_instances_per_draw = backend.max_instances_per_draw;
pub const RenderItem = queue.RenderItem;
pub const RenderQueue = queue.RenderQueue;
pub const VSync = struct {
    enabled: bool = true,
};
pub const VertexColor = backend.VertexColor;
pub const VertexUv = backend.VertexUv;
pub const VertexPos3Uv = backend.VertexPos3Uv;
pub const VertexPos3NormUv = backend.VertexPos3NormUv;
pub const VertexPos3Color = backend.VertexPos3Color;
pub const Triangle = backend.Triangle;
pub const TexturedQuad = backend.TexturedQuad;
pub const DrawCmd = backend.DrawCmd;
pub const BuildContext = @import("build.zig").BuildContext;
pub const PostProcessShaderHandle = @import("post_process.zig").PostProcessShaderHandle;
pub const PostProcessParams = @import("post_process.zig").PostProcessParams;
pub const PostProcessMaterial = @import("post_process.zig").PostProcessMaterial;
pub const PostProcessSceneScope = @import("post_process.zig").PostProcessSceneScope;
pub const PostProcessPass = @import("post_process.zig").PostProcessPass;
pub const PostProcessOrder = @import("post_process.zig").PostProcessOrder;
pub const PostProcessPresentSlot = @import("post_process.zig").PostProcessPresentSlot;
pub const PostProcessShaderLibrary = @import("post_process.zig").PostProcessShaderLibrary;
pub const buildPostProcessWgsl = @import("post_process.zig").buildWgsl;
pub const Text = text.Text;
pub const Font = text.Font;
pub const DefaultFont = text.DefaultFont;
pub const FontHandle = text.FontHandle;
pub const FontLibrary = text.FontLibrary;
pub const HorizontalAlignment = text.HorizontalAlignment;
pub const VerticalAlignment = text.VerticalAlignment;
pub const textLayoutHash = text.layoutHash;
pub const buildTextMesh = text.buildMesh;
pub const Sprite = sprite.Sprite;
pub const spriteSizeHash = sprite.sizeHash;
pub const Layer = layer.Layer;
pub const LayerN = layer.LayerN;
pub const LayerOverride = layer.LayerOverride;
pub const LayerSortKey = layer.LayerSortKey;
pub const CameraLayer = layer.CameraLayer;
pub const CameraLayerN = layer.CameraLayerN;

pub fn configForVsync(vsync: bool) RendererConfig {
    return backend.configForVsync(vsync);
}

pub fn rendererStats(renderer: *const Renderer) RendererStats {
    return renderer.stats();
}

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
const layer = @import("layer.zig");
const backend = if (builtin.target.cpu.arch.isWasm())
    @import("backend_web.zig")
else
    @import("backend_native.zig");
