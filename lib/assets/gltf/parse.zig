const std = @import("std");
const cgltf = @import("cgltf");
const common = @import("common");
const scene = @import("scene.zig");

const c = cgltf.c;

pub const Error = error{
    ParseFailed,
    LoadBuffersFailed,
    ValidateFailed,
    InvalidPrimitive,
    UnsupportedAttributeName,
};

pub fn parseFromBytes(allocator: std.mem.Allocator, bytes: []const u8) !scene.SceneData {
    var options: c.cgltf_options = std.mem.zeroes(c.cgltf_options);
    var data: ?*c.cgltf_data = null;
    const result = c.cgltf_parse(&options, bytes.ptr, bytes.len, &data);
    if (result != c.cgltf_result_success or data == null) return Error.ParseFailed;
    defer c.cgltf_free(data);

    if (needsCgltfLoadBuffers(data.?)) {
        if (c.cgltf_load_buffers(&options, data, null) != c.cgltf_result_success) return Error.LoadBuffersFailed;
    }

    if (c.cgltf_validate(data) != c.cgltf_result_success) return Error.ValidateFailed;
    return try buildSceneData(allocator, data.?);
}

pub fn parseFromFile(allocator: std.mem.Allocator, path: [:0]const u8) !scene.SceneData {
    var options: c.cgltf_options = std.mem.zeroes(c.cgltf_options);
    var data: ?*c.cgltf_data = null;
    const result = c.cgltf_parse_file(&options, path, &data);
    if (result != c.cgltf_result_success or data == null) return Error.ParseFailed;
    defer c.cgltf_free(data);

    if (c.cgltf_load_buffers(&options, data, path) != c.cgltf_result_success) return Error.LoadBuffersFailed;
    if (c.cgltf_validate(data) != c.cgltf_result_success) return Error.ValidateFailed;
    return try buildSceneData(allocator, data.?);
}

fn buildSceneData(allocator: std.mem.Allocator, data: *const c.cgltf_data) !scene.SceneData {
    return .{
        .allocator = allocator,
        .scenes = try buildScenes(allocator, data),
        .default_scene = ptrIndex(c.cgltf_scene, data.scene, data.scenes, data.scenes_count),
        .nodes = try buildNodes(allocator, data),
        .meshes = try buildMeshes(allocator, data),
        .materials = try buildMaterials(allocator, data),
        .textures = try buildTextures(allocator, data),
        .images = try buildImages(allocator, data),
        .buffer_views = try buildBufferViews(allocator, data),
        .accessors = try buildAccessors(allocator, data),
        .buffers = try buildBuffers(allocator, data),
    };
}

fn needsCgltfLoadBuffers(data: *const c.cgltf_data) bool {
    var found_loadable = false;
    for (0..data.buffers_count) |i| {
        const buffer = &data.buffers[i];
        if (buffer.data != null) continue;
        const uri = buffer.uri orelse {
            found_loadable = true;
            continue;
        };
        if (!std.mem.startsWith(u8, std.mem.span(uri), "data:")) return false;
        found_loadable = true;
    }
    return found_loadable;
}

fn buildScenes(allocator: std.mem.Allocator, data: *const c.cgltf_data) ![]scene.SceneDef {
    const count: usize = data.scenes_count;
    const out = try allocator.alloc(scene.SceneDef, count);
    errdefer allocator.free(out);

    for (out, 0..) |*dst, i| {
        const src = &data.scenes[i];
        dst.* = .{
            .name = try dupCString(allocator, src.name),
            .root_nodes = try mapPointersToIndices(allocator, c.cgltf_node, src.nodes, src.nodes_count, data.nodes, data.nodes_count),
        };
    }
    return out;
}

fn buildNodes(allocator: std.mem.Allocator, data: *const c.cgltf_data) ![]scene.NodeData {
    const count: usize = data.nodes_count;
    const out = try allocator.alloc(scene.NodeData, count);
    errdefer allocator.free(out);

    for (out, 0..) |*dst, i| {
        const src = &data.nodes[i];
        dst.* = .{
            .name = try dupCString(allocator, src.name),
            .parent_index = ptrIndex(c.cgltf_node, src.parent, data.nodes, data.nodes_count),
            .mesh_index = ptrIndex(c.cgltf_mesh, src.mesh, data.meshes, data.meshes_count),
            .local_transform = nodeTransform(src),
            .children = try mapPointersToIndices(allocator, c.cgltf_node, src.children, src.children_count, data.nodes, data.nodes_count),
        };
    }
    return out;
}

fn buildMeshes(allocator: std.mem.Allocator, data: *const c.cgltf_data) ![]scene.MeshData {
    const count: usize = data.meshes_count;
    const out = try allocator.alloc(scene.MeshData, count);
    errdefer allocator.free(out);

    for (out, 0..) |*dst, i| {
        const src = &data.meshes[i];
        const primitives = try allocator.alloc(scene.PrimitiveData, src.primitives_count);
        errdefer allocator.free(primitives);
        for (primitives, 0..) |*primitive, p_index| {
            primitive.* = try buildPrimitive(data, &src.primitives[p_index]);
        }
        dst.* = .{
            .name = try dupCString(allocator, src.name),
            .primitives = primitives,
        };
    }
    return out;
}

fn buildPrimitive(data: *const c.cgltf_data, primitive: *allowzero const c.cgltf_primitive) !scene.PrimitiveData {
    var out = scene.PrimitiveData{
        .topology = switch (primitive.type) {
            c.cgltf_primitive_type_points => .Points,
            c.cgltf_primitive_type_lines => .Lines,
            c.cgltf_primitive_type_line_strip => .LineStrip,
            c.cgltf_primitive_type_triangles => .Triangles,
            c.cgltf_primitive_type_triangle_strip => .TriangleStrip,
            c.cgltf_primitive_type_triangle_fan => .TriangleFan,
            else => return Error.InvalidPrimitive,
        },
        .material_index = ptrIndex(c.cgltf_material, primitive.material, data.materials, data.materials_count),
        .indices_accessor = accessorRef(data, primitive.indices),
    };

    var i: usize = 0;
    while (i < primitive.attributes_count) : (i += 1) {
        const attr = primitive.attributes[i];
        const ref = accessorRef(data, attr.data) orelse continue;
        switch (attr.type) {
            c.cgltf_attribute_type_position => out.position_accessor = ref,
            c.cgltf_attribute_type_normal => out.normal_accessor = ref,
            c.cgltf_attribute_type_tangent => out.tangent_accessor = ref,
            c.cgltf_attribute_type_texcoord => {
                if (attr.index == 0) out.uv0_accessor = ref;
            },
            else => {},
        }
    }

    return out;
}

fn buildMaterials(allocator: std.mem.Allocator, data: *const c.cgltf_data) ![]scene.MaterialData {
    const count: usize = data.materials_count;
    const out = try allocator.alloc(scene.MaterialData, count);
    errdefer allocator.free(out);

    for (out, 0..) |*dst, i| {
        const src = &data.materials[i];
        const base_color = common.Color.F32{
            .r = @floatCast(src.pbr_metallic_roughness.base_color_factor[0]),
            .g = @floatCast(src.pbr_metallic_roughness.base_color_factor[1]),
            .b = @floatCast(src.pbr_metallic_roughness.base_color_factor[2]),
            .a = @floatCast(src.pbr_metallic_roughness.base_color_factor[3]),
        };
        const emissive = common.Color.F32{
            .r = @floatCast(src.emissive_factor[0]),
            .g = @floatCast(src.emissive_factor[1]),
            .b = @floatCast(src.emissive_factor[2]),
            .a = 1.0,
        };
        dst.* = .{
            .name = try dupCString(allocator, src.name),
            .base_color_factor = base_color,
            .base_color_texture = textureRef(data, src.pbr_metallic_roughness.base_color_texture),
            .metallic_factor = @floatCast(src.pbr_metallic_roughness.metallic_factor),
            .roughness_factor = @floatCast(src.pbr_metallic_roughness.roughness_factor),
            .metallic_roughness_texture = textureRef(data, src.pbr_metallic_roughness.metallic_roughness_texture),
            .normal_texture = textureRef(data, src.normal_texture),
            .normal_scale = @floatCast(src.normal_texture.scale),
            .occlusion_texture = textureRef(data, src.occlusion_texture),
            .occlusion_strength = @floatCast(src.occlusion_texture.scale),
            .emissive_factor = emissive,
            .emissive_texture = textureRef(data, src.emissive_texture),
            .alpha_mode = switch (src.alpha_mode) {
                c.cgltf_alpha_mode_mask => .Mask,
                c.cgltf_alpha_mode_blend => .Blend,
                else => .Opaque,
            },
            .alpha_cutoff = src.alpha_cutoff,
            .double_sided = src.double_sided != 0,
        };
    }
    return out;
}

fn buildTextures(allocator: std.mem.Allocator, data: *const c.cgltf_data) ![]scene.TextureData {
    const count: usize = data.textures_count;
    const out = try allocator.alloc(scene.TextureData, count);
    errdefer allocator.free(out);

    for (out, 0..) |*dst, i| {
        const src = &data.textures[i];
        dst.* = .{
            .name = try dupCString(allocator, src.name),
            .image_index = ptrIndex(c.cgltf_image, src.image, data.images, data.images_count),
            .sampler = textureSampler(src.sampler),
        };
    }
    return out;
}

fn buildImages(allocator: std.mem.Allocator, data: *const c.cgltf_data) ![]scene.ImageData {
    const count: usize = data.images_count;
    const out = try allocator.alloc(scene.ImageData, count);
    errdefer allocator.free(out);

    for (out, 0..) |*dst, i| {
        const src = &data.images[i];
        dst.* = .{
            .name = try dupCString(allocator, src.name),
            .uri = try dupCString(allocator, src.uri),
            .mime_type = try dupCString(allocator, src.mime_type),
            .buffer_view_index = ptrIndex(c.cgltf_buffer_view, src.buffer_view, data.buffer_views, data.buffer_views_count),
            .bytes = null,
        };
    }
    return out;
}

fn buildBuffers(allocator: std.mem.Allocator, data: *const c.cgltf_data) ![]scene.BufferData {
    const count: usize = data.buffers_count;
    const out = try allocator.alloc(scene.BufferData, count);
    errdefer allocator.free(out);

    for (out, 0..) |*dst, i| {
        const src = &data.buffers[i];
        const uri = try dupCString(allocator, src.uri);
        dst.* = .{
            .uri = uri,
            .byte_length = src.size,
            .source = if (uri) |value|
                if (std.mem.startsWith(u8, value, "data:")) .DataUri else .ExternalUri
            else if (src.data != null)
                .GlbBinary
            else
                .None,
            .bytes = if (src.data != null and src.size > 0) blk: {
                const src_bytes: [*]const u8 = @ptrCast(src.data);
                break :blk try allocator.dupe(u8, src_bytes[0..src.size]);
            } else null,
        };
    }
    return out;
}

fn buildBufferViews(allocator: std.mem.Allocator, data: *const c.cgltf_data) ![]scene.BufferViewData {
    const count: usize = data.buffer_views_count;
    const out = try allocator.alloc(scene.BufferViewData, count);
    errdefer allocator.free(out);

    for (out, 0..) |*dst, i| {
        const src = &data.buffer_views[i];
        dst.* = .{
            .buffer_index = ptrIndex(c.cgltf_buffer, src.buffer, data.buffers, data.buffers_count) orelse 0,
            .byte_offset = src.offset,
            .byte_length = src.size,
            .byte_stride = src.stride,
        };
    }
    return out;
}

fn buildAccessors(allocator: std.mem.Allocator, data: *const c.cgltf_data) ![]scene.AccessorData {
    const count: usize = data.accessors_count;
    const out = try allocator.alloc(scene.AccessorData, count);
    errdefer allocator.free(out);

    for (out, 0..) |*dst, i| {
        const src = &data.accessors[i];
        const element_type = switch (src.type) {
            c.cgltf_type_scalar => scene.AccessorRef.ElementType.Scalar,
            c.cgltf_type_vec2 => .Vec2,
            c.cgltf_type_vec3 => .Vec3,
            c.cgltf_type_vec4 => .Vec4,
            c.cgltf_type_mat2 => .Mat2,
            c.cgltf_type_mat3 => .Mat3,
            c.cgltf_type_mat4 => .Mat4,
            else => .Scalar,
        };
        const component_size = c.cgltf_component_size(src.component_type);
        const element_components = c.cgltf_num_components(src.type);
        const element_size = component_size * element_components;
        const stride = if (src.stride > 0) src.stride else element_size;
        dst.* = .{
            .buffer_view_index = ptrIndex(c.cgltf_buffer_view, src.buffer_view, data.buffer_views, data.buffer_views_count),
            .count = src.count,
            .component_type = gltfComponentType(src.component_type),
            .element_type = element_type,
            .byte_offset = src.offset,
            .byte_stride = stride,
            .byte_length = stride * src.count,
            .normalized = src.normalized != 0,
        };
    }
    return out;
}

fn nodeTransform(node: *allowzero const c.cgltf_node) common.LocalTransform {
    var out = common.LocalTransform{};
    if (node.has_matrix != 0) {
        return transformFromMatrix(&node.matrix);
    }
    if (node.has_translation != 0) {
        out.translation = .{
            .x = @floatCast(node.translation[0]),
            .y = @floatCast(node.translation[1]),
            .z = @floatCast(node.translation[2]),
        };
    }
    if (node.has_rotation != 0) {
        out.rotation = .{
            .x = @floatCast(node.rotation[0]),
            .y = @floatCast(node.rotation[1]),
            .z = @floatCast(node.rotation[2]),
            .w = @floatCast(node.rotation[3]),
        };
    }
    if (node.has_scale != 0) {
        out.scale = .{
            .x = @floatCast(node.scale[0]),
            .y = @floatCast(node.scale[1]),
            .z = @floatCast(node.scale[2]),
        };
    }
    return out;
}

fn transformFromMatrix(matrix: [*c]const c.cgltf_float) common.LocalTransform {
    var x_axis = common.Vec3{ .x = @floatCast(matrix[0]), .y = @floatCast(matrix[1]), .z = @floatCast(matrix[2]) };
    const y_axis = common.Vec3{ .x = @floatCast(matrix[4]), .y = @floatCast(matrix[5]), .z = @floatCast(matrix[6]) };
    const z_axis = common.Vec3{ .x = @floatCast(matrix[8]), .y = @floatCast(matrix[9]), .z = @floatCast(matrix[10]) };

    var scale = common.Vec3{
        .x = x_axis.length(),
        .y = y_axis.length(),
        .z = z_axis.length(),
    };
    if (x_axis.cross(y_axis).dot(z_axis) < 0.0) {
        scale.x = -scale.x;
    }

    if (@abs(scale.x) > 0.00001) x_axis = x_axis.scale(1.0 / scale.x);
    const ry = if (@abs(scale.y) > 0.00001) y_axis.scale(1.0 / scale.y) else common.Vec3{ .y = 1.0 };
    const rz = if (@abs(scale.z) > 0.00001) z_axis.scale(1.0 / scale.z) else common.Vec3{ .z = 1.0 };

    return .{
        .translation = .{
            .x = @floatCast(matrix[12]),
            .y = @floatCast(matrix[13]),
            .z = @floatCast(matrix[14]),
        },
        .rotation = quatFromRotationColumns(x_axis, ry, rz),
        .scale = scale,
    };
}

fn quatFromRotationColumns(x_axis: common.Vec3, y_axis: common.Vec3, z_axis: common.Vec3) common.Quat {
    const m00 = x_axis.x;
    const m01 = y_axis.x;
    const m02 = z_axis.x;
    const m10 = x_axis.y;
    const m11 = y_axis.y;
    const m12 = z_axis.y;
    const m20 = x_axis.z;
    const m21 = y_axis.z;
    const m22 = z_axis.z;
    const trace = m00 + m11 + m22;

    if (trace > 0.0) {
        const s = @sqrt(trace + 1.0) * 2.0;
        return (common.Quat{
            .w = 0.25 * s,
            .x = (m21 - m12) / s,
            .y = (m02 - m20) / s,
            .z = (m10 - m01) / s,
        }).normalize();
    }
    if (m00 > m11 and m00 > m22) {
        const s = @sqrt(1.0 + m00 - m11 - m22) * 2.0;
        return (common.Quat{
            .w = (m21 - m12) / s,
            .x = 0.25 * s,
            .y = (m01 + m10) / s,
            .z = (m02 + m20) / s,
        }).normalize();
    }
    if (m11 > m22) {
        const s = @sqrt(1.0 + m11 - m00 - m22) * 2.0;
        return (common.Quat{
            .w = (m02 - m20) / s,
            .x = (m01 + m10) / s,
            .y = 0.25 * s,
            .z = (m12 + m21) / s,
        }).normalize();
    }

    const s = @sqrt(1.0 + m22 - m00 - m11) * 2.0;
    return (common.Quat{
        .w = (m10 - m01) / s,
        .x = (m02 + m20) / s,
        .y = (m12 + m21) / s,
        .z = 0.25 * s,
    }).normalize();
}

fn accessorRef(data: *const c.cgltf_data, accessor: ?*const c.cgltf_accessor) ?scene.AccessorRef {
    const value = accessor orelse return null;
    return .{
        .accessor_index = ptrIndex(c.cgltf_accessor, value, data.accessors, data.accessors_count) orelse return null,
        .count = value.count,
        .component_type = gltfComponentType(value.component_type),
        .element_type = switch (value.type) {
            c.cgltf_type_scalar => .Scalar,
            c.cgltf_type_vec2 => .Vec2,
            c.cgltf_type_vec3 => .Vec3,
            c.cgltf_type_vec4 => .Vec4,
            c.cgltf_type_mat2 => .Mat2,
            c.cgltf_type_mat3 => .Mat3,
            c.cgltf_type_mat4 => .Mat4,
            else => .Scalar,
        },
        .byte_offset = value.offset,
    };
}

fn gltfComponentType(component_type: c.cgltf_component_type) u32 {
    return switch (component_type) {
        c.cgltf_component_type_r_8 => 5120,
        c.cgltf_component_type_r_8u => 5121,
        c.cgltf_component_type_r_16 => 5122,
        c.cgltf_component_type_r_16u => 5123,
        c.cgltf_component_type_r_32u => 5125,
        c.cgltf_component_type_r_32f => 5126,
        else => 0,
    };
}

fn textureRef(data: *const c.cgltf_data, texture_view: c.cgltf_texture_view) ?scene.TextureRef {
    const texture = texture_view.texture orelse return null;
    return .{
        .texture_index = ptrIndex(c.cgltf_texture, texture, data.textures, data.textures_count) orelse return null,
        .texcoord_set = @intCast(texture_view.texcoord),
    };
}

fn textureSampler(sampler: ?*const c.cgltf_sampler) scene.TextureSamplerData {
    const value = sampler orelse return .{};
    return .{
        .mag_filter = gltfMagFilter(value.mag_filter),
        .min_filter = gltfMinFilter(value.min_filter),
        .mipmap_filter = gltfMipmapFilter(value.min_filter),
        .address_mode_u = gltfWrapMode(value.wrap_s),
        .address_mode_v = gltfWrapMode(value.wrap_t),
        .address_mode_w = .repeat,
    };
}

fn gltfMagFilter(filter: c.cgltf_uint) scene.SamplerFilter {
    return switch (filter) {
        9728 => .nearest,
        9729 => .linear,
        else => .linear,
    };
}

fn gltfMinFilter(filter: c.cgltf_uint) scene.SamplerFilter {
    return switch (filter) {
        9728, 9984, 9986 => .nearest,
        9729, 9985, 9987 => .linear,
        else => .linear,
    };
}

fn gltfMipmapFilter(filter: c.cgltf_uint) scene.SamplerFilter {
    return switch (filter) {
        9984, 9985 => .nearest,
        9986, 9987 => .linear,
        else => .linear,
    };
}

fn gltfWrapMode(mode: c.cgltf_uint) scene.SamplerAddressMode {
    return switch (mode) {
        33071 => .clamp_to_edge,
        33648 => .mirror_repeat,
        10497 => .repeat,
        else => .repeat,
    };
}

fn mapPointersToIndices(
    allocator: std.mem.Allocator,
    comptime T: type,
    ptrs: ?[*]const ?*const T,
    count: usize,
    base: ?[*]const T,
    base_count: usize,
) ![]u32 {
    const out = try allocator.alloc(u32, count);
    errdefer allocator.free(out);
    for (out, 0..) |*dst, i| {
        const ptr = ptrs.?[i] orelse return error.InvalidPointer;
        dst.* = ptrIndex(T, ptr, base, base_count) orelse return error.InvalidPointer;
    }
    return out;
}

fn ptrIndex(comptime T: type, ptr: ?*const T, base: ?[*]const T, count: usize) ?u32 {
    const value = ptr orelse return null;
    const start = base orelse return null;
    const start_addr = @intFromPtr(start);
    const value_addr = @intFromPtr(value);
    if (value_addr < start_addr) return null;
    const size = @sizeOf(T);
    const diff = value_addr - start_addr;
    if (size == 0 or diff % size != 0) return null;
    const index = diff / size;
    if (index >= count) return null;
    return @intCast(index);
}

fn dupCString(allocator: std.mem.Allocator, value: ?[*:0]const u8) !?[]u8 {
    const src = value orelse return null;
    return try allocator.dupe(u8, std.mem.span(src));
}

test "parse gltf metadata from bytes" {
    const allocator = std.testing.allocator;
    const bytes =
        \\{
        \\  "asset": {"version": "2.0"},
        \\  "scene": 0,
        \\  "scenes": [{"name": "MainScene", "nodes": [0]}],
        \\  "nodes": [
        \\    {
        \\      "name": "Root",
        \\      "mesh": 0,
        \\      "translation": [1.0, 2.0, 3.0],
        \\      "rotation": [0.0, 0.0, 0.0, 1.0],
        \\      "scale": [2.0, 2.0, 2.0],
        \\      "children": [1]
        \\    },
        \\    {
        \\      "name": "Child",
        \\      "translation": [4.0, 5.0, 6.0]
        \\    }
        \\  ],
        \\  "meshes": [{
        \\    "name": "MeshA",
        \\    "primitives": [{
        \\      "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
        \\      "indices": 3,
        \\      "material": 0
        \\    }]
        \\  }],
        \\  "materials": [{
        \\    "name": "MatA",
        \\    "pbrMetallicRoughness": {
        \\      "baseColorTexture": { "index": 0, "texCoord": 0 },
        \\      "baseColorFactor": [0.5, 0.6, 0.7, 1.0],
        \\      "metallicFactor": 0.2,
        \\      "roughnessFactor": 0.8,
        \\      "metallicRoughnessTexture": { "index": 1, "texCoord": 0 }
        \\    },
        \\    "normalTexture": { "index": 2, "scale": 0.7 },
        \\    "occlusionTexture": { "index": 3, "strength": 0.6 },
        \\    "emissiveTexture": { "index": 4, "texCoord": 1 },
        \\    "emissiveFactor": [0.1, 0.2, 0.3],
        \\    "alphaMode": "MASK",
        \\    "alphaCutoff": 0.42,
        \\    "doubleSided": true
        \\  }],
        \\  "textures": [
        \\    { "name": "TexA", "source": 0 },
        \\    { "name": "TexMR", "source": 1 },
        \\    { "name": "TexN", "source": 2 },
        \\    { "name": "TexO", "source": 3 },
        \\    { "name": "TexE", "source": 4 }
        \\  ],
        \\  "images": [
        \\    { "name": "ImgA", "uri": "albedo.png", "mimeType": "image/png" },
        \\    { "name": "ImgMR", "uri": "mr.png", "mimeType": "image/png" },
        \\    { "name": "ImgN", "uri": "normal.png", "mimeType": "image/png" },
        \\    { "name": "ImgO", "uri": "occ.png", "mimeType": "image/png" },
        \\    { "name": "ImgE", "uri": "emit.png", "mimeType": "image/png" }
        \\  ],
        \\  "buffers": [{ "byteLength": 128, "uri": "mesh.bin" }],
        \\  "bufferViews": [{ "buffer": 0, "byteOffset": 0, "byteLength": 36 }],
        \\  "accessors": [
        \\    { "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3" },
        \\    { "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3" },
        \\    { "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC2" },
        \\    { "bufferView": 0, "componentType": 5123, "count": 3, "type": "SCALAR" }
        \\  ]
        \\}
    ;

    var parsed = try parseFromBytes(allocator, bytes);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(?u32, 0), parsed.default_scene);
    try std.testing.expectEqual(@as(usize, 1), parsed.scenes.len);
    try std.testing.expectEqualStrings("MainScene", parsed.scenes[0].name.?);
    try std.testing.expectEqual(@as(u32, 0), parsed.scenes[0].root_nodes[0]);

    try std.testing.expectEqual(@as(usize, 2), parsed.nodes.len);
    try std.testing.expectEqualStrings("Root", parsed.nodes[0].name.?);
    try std.testing.expectEqual(@as(f32, 1.0), parsed.nodes[0].local_transform.translation.x);
    try std.testing.expectEqual(@as(f32, 2.0), parsed.nodes[0].local_transform.scale.x);
    try std.testing.expectEqual(@as(?u32, 0), parsed.nodes[0].mesh_index);
    try std.testing.expect(parsed.nodes[0].isRoot());
    try std.testing.expectEqual(@as(usize, 1), parsed.nodes[0].children.len);
    try std.testing.expectEqual(@as(u32, 1), parsed.nodes[0].children[0]);
    try std.testing.expectEqualStrings("Child", parsed.nodes[1].name.?);
    try std.testing.expectEqual(@as(?u32, 0), parsed.nodes[1].parent_index);
    try std.testing.expectEqual(@as(f32, 4.0), parsed.nodes[1].local_transform.translation.x);

    try std.testing.expectEqual(@as(usize, 1), parsed.meshes.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.meshes[0].primitives.len);
    try std.testing.expectEqual(@as(?u32, 0), parsed.meshes[0].primitives[0].material_index);

    try std.testing.expectEqual(@as(usize, 1), parsed.materials.len);
    try std.testing.expectEqual(scene.AlphaMode.Mask, parsed.materials[0].alpha_mode);
    try std.testing.expect(parsed.materials[0].double_sided);
    try std.testing.expectEqual(@as(?u32, 0), parsed.materials[0].base_color_texture.?.texture_index);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), parsed.materials[0].metallic_factor, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), parsed.materials[0].roughness_factor, 0.0001);
    try std.testing.expectEqual(@as(?u32, 1), parsed.materials[0].metallic_roughness_texture.?.texture_index);
    try std.testing.expectEqual(@as(?u32, 2), parsed.materials[0].normal_texture.?.texture_index);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), parsed.materials[0].normal_scale, 0.0001);
    try std.testing.expectEqual(@as(?u32, 3), parsed.materials[0].occlusion_texture.?.texture_index);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), parsed.materials[0].occlusion_strength, 0.0001);
    try std.testing.expectEqual(@as(?u32, 4), parsed.materials[0].emissive_texture.?.texture_index);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), parsed.materials[0].emissive_factor.r, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), parsed.materials[0].emissive_factor.g, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), parsed.materials[0].emissive_factor.b, 0.0001);

    try std.testing.expectEqual(@as(usize, 5), parsed.images.len);
    try std.testing.expectEqualStrings("albedo.png", parsed.images[0].uri.?);

    try std.testing.expectEqual(@as(usize, 1), parsed.buffers.len);
    try std.testing.expectEqual(scene.BufferSource.ExternalUri, parsed.buffers[0].source);
}

test "parse gltf file resolves external buffer bytes" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{
        .sub_path = "mesh.bin",
        .data = &[_]u8{
            0, 0, 128, 63, 0, 0, 0,   64,
            0, 0, 64,  64, 0, 0, 128, 64,
        },
    });

    try tmp.dir.writeFile(io, .{
        .sub_path = "scene.gltf",
        .data =
        \\{
        \\  "asset": {"version": "2.0"},
        \\  "buffers": [{ "byteLength": 16, "uri": "mesh.bin" }],
        \\  "bufferViews": [{ "buffer": 0, "byteOffset": 0, "byteLength": 16 }],
        \\  "accessors": [{ "bufferView": 0, "componentType": 5126, "count": 2, "type": "VEC2" }]
        \\}
        ,
    });

    const scene_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/scene.gltf", .{tmp.sub_path});
    defer allocator.free(scene_path);
    const scene_path_z = try allocator.dupeZ(u8, scene_path);
    defer allocator.free(scene_path_z);

    var parsed = try parseFromFile(allocator, scene_path_z);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.buffers.len);
    try std.testing.expectEqual(@as(usize, 16), parsed.buffers[0].bytes.?.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.buffer_views.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.accessors.len);
    const slice = parsed.accessorByteSlice(0).?;
    try std.testing.expectEqual(@as(usize, 16), slice.len);
    try std.testing.expectEqual(@as(u8, 63), slice[3]);
}

test "node matrix preserves rotation and scale" {
    const matrix = [_]c.cgltf_float{
        1.0, 0.0, 0.0,  0.0,
        0.0, 0.0, -1.0, 0.0,
        0.0, 1.0, 0.0,  0.0,
        2.0, 3.0, 4.0,  1.0,
    };

    const transform = transformFromMatrix(&matrix);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), transform.translation.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), transform.translation.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), transform.translation.z, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), transform.scale.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), transform.scale.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), transform.scale.z, 0.0001);

    const rotated_y = transform.rotation.rotateVec3(.{ .y = 1.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), rotated_y.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), rotated_y.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), rotated_y.z, 0.0001);
}
