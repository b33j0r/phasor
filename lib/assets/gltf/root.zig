test "import tests" {
    _ = scene;
    _ = parse;
}

pub const scene = @import("scene.zig");
pub const parse = @import("parse.zig");

pub const SceneData = scene.SceneData;
pub const SceneDef = scene.SceneDef;
pub const NodeData = scene.NodeData;
pub const MeshData = scene.MeshData;
pub const PrimitiveData = scene.PrimitiveData;
pub const MaterialData = scene.MaterialData;
pub const TextureData = scene.TextureData;
pub const TextureRef = scene.TextureRef;
pub const ImageData = scene.ImageData;
pub const BufferViewData = scene.BufferViewData;
pub const AccessorData = scene.AccessorData;
pub const BufferData = scene.BufferData;
pub const BufferSource = scene.BufferSource;
pub const AlphaMode = scene.AlphaMode;
pub const Topology = scene.Topology;
pub const AccessorRef = scene.AccessorRef;

pub const parseFromBytes = parse.parseFromBytes;
pub const parseFromFile = parse.parseFromFile;
