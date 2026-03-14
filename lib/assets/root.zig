pub const gltf = @import("gltf/root.zig");
pub const scene = @import("scene.zig");
pub const SceneData = scene.SceneData;
pub const Scene = struct {
    path: ?[:0]const u8 = null,
    data: ?[]const u8 = null,
    scene_data: ?SceneData = null,

    pub fn file(path: [:0]const u8) Scene {
        return .{ .path = path };
    }

    pub fn embedded(bytes: []const u8) Scene {
        return .{ .data = bytes };
    }

    pub fn load(self: *Scene, ctx: AssetsContext) !void {
        if (self.scene_data != null) return;

        if (self.data) |bytes| {
            self.scene_data = try gltf.parseFromBytes(ctx.allocator, bytes);
            return;
        }

        const path = self.path orelse return error.MissingSceneSource;
        const resolved = try resolveFileSearch(ctx.allocator, ctx.io, path);
        defer ctx.allocator.free(resolved);
        self.scene_data = try gltf.parseFromFile(ctx.allocator, resolved);
    }

    pub fn unload(self: *Scene, _: AssetsContext) !void {
        if (self.scene_data) |*scene_data| {
            scene_data.deinit();
            self.scene_data = null;
        }
    }
};

pub const AssetsContext = struct {
    allocator: std.mem.Allocator,
    io: *const std.Io,
    renderer: ?*render.Renderer = null,
    sampler: ?*render.Sampler = null,
    font_library: ?*render.FontLibrary = null,
    mesh_library: ?*render.MeshLibrary = null,
    shader_library: ?*render.ShaderLibrary = null,
    post_process_shader_library: ?*render.PostProcessShaderLibrary = null,
    texture_library: ?*render.TextureLibrary = null,
    material_library: ?*render.MaterialLibrary = null,
};

pub const Texture = struct {
    path: ?[:0]const u8 = null,
    data: ?[]const u8 = null,
    alpha_mode: ?render.Material.AlphaMode = null,
    sampler_descriptor: ?render.SamplerDescriptor = null,
    width: u32 = 0,
    height: u32 = 0,
    texture_handle: render.TextureHandle = render.TextureHandle.invalid(),
    material_handle: render.MaterialHandle = render.MaterialHandle.invalid(),
    material: render.Material = render.Material.default,
    owned_sampler: ?render.Sampler = null,

    pub fn embedded(bytes: []const u8) Texture {
        return .{ .data = bytes };
    }

    pub fn file(path: [:0]const u8) Texture {
        return .{ .path = path };
    }

    pub fn withAlphaMode(self: Texture, mode: render.Material.AlphaMode) Texture {
        var out = self;
        out.alpha_mode = mode;
        return out;
    }

    pub fn asOpaque(self: Texture) Texture {
        return self.withAlphaMode(.Opaque);
    }

    pub fn asBlended(self: Texture) Texture {
        return self.withAlphaMode(.Blend);
    }

    pub fn withSampler(self: Texture, descriptor: render.SamplerDescriptor) Texture {
        var out = self;
        out.sampler_descriptor = descriptor;
        return out;
    }

    pub fn tiledLinear(self: Texture) Texture {
        return self.withSampler(render.SamplerDescriptor.tiledLinear());
    }

    pub fn equirectangularLinear(self: Texture) Texture {
        return self.withSampler(.{
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_filter = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
        });
    }

    pub fn pixelArtTiled(self: Texture) Texture {
        return self.withSampler(render.SamplerDescriptor.pixelArtTiled());
    }

    pub fn load(self: *Texture, ctx: AssetsContext) !void {
        if (self.material_handle.isValid()) return;

        const renderer = ctx.renderer orelse return error.MissingRenderer;
        const sampler = ctx.sampler orelse return error.MissingSampler;
        const texture_library = ctx.texture_library orelse return error.MissingTextureLibrary;
        const material_library = ctx.material_library orelse return error.MissingMaterialLibrary;

        if (builtin.target.cpu.arch.isWasm()) {
            const image = if (self.data) |bytes|
                try loadImageFromBytes(ctx.allocator, bytes)
            else
                return error.MissingImageSource;
            defer ctx.allocator.free(image.data);

            self.width = image.width;
            self.height = image.height;

            const texture = try renderer.createTextureRgba8(self.width, self.height, image.data);
            errdefer {
                var t = texture;
                renderer.destroyTexture(&t);
            }
            const texture_handle = try texture_library.addTexture(texture);
            errdefer _ = texture_library.destroyTexture(renderer, texture_handle);

            var active_sampler = sampler.*;
            var owned_sampler: ?render.Sampler = null;
            if (self.sampler_descriptor) |descriptor| {
                var custom_sampler = try renderer.createSamplerWithDescriptor(descriptor);
                errdefer renderer.destroySampler(&custom_sampler);
                owned_sampler = custom_sampler;
                active_sampler = custom_sampler;
            }

            const texture_ptr = texture_library.get(texture_handle) orelse return error.MissingTexture;
            const material = try renderer.createMaterial(texture_ptr.*, active_sampler);
            errdefer {
                var m = material;
                renderer.destroyMaterial(&m);
            }
            const material_handle = try material_library.addMaterial(material);
            errdefer _ = material_library.destroyMaterial(renderer, material_handle);

            self.texture_handle = texture_handle;
            self.material_handle = material_handle;
            self.owned_sampler = owned_sampler;
            var material_instance = render.Material.withTextured(material_handle);
            if (self.alpha_mode) |mode| {
                material_instance.alpha_mode = mode;
            }
            self.material = material_instance;
            return;
        }

        const image = if (self.data) |bytes|
            try loadImageFromBytes(ctx.allocator, bytes)
        else if (self.path) |path|
            try loadImage(ctx.allocator, ctx.io, path)
        else
            return error.MissingImageSource;
        defer ctx.allocator.free(image.data);

        self.width = image.width;
        self.height = image.height;

        const texture = try renderer.createTextureRgba8(self.width, self.height, image.data);
        errdefer {
            var t = texture;
            renderer.destroyTexture(&t);
        }
        const texture_handle = try texture_library.addTexture(texture);
        errdefer _ = texture_library.destroyTexture(renderer, texture_handle);

        var active_sampler = sampler.*;
        var owned_sampler: ?render.Sampler = null;
        if (self.sampler_descriptor) |descriptor| {
            var custom_sampler = try renderer.createSamplerWithDescriptor(descriptor);
            errdefer renderer.destroySampler(&custom_sampler);
            owned_sampler = custom_sampler;
            active_sampler = custom_sampler;
        }

        const texture_ptr = texture_library.get(texture_handle) orelse return error.MissingTexture;
        const material = try renderer.createMaterial(texture_ptr.*, active_sampler);
        errdefer {
            var m = material;
            renderer.destroyMaterial(&m);
        }
        const material_handle = try material_library.addMaterial(material);
        errdefer _ = material_library.destroyMaterial(renderer, material_handle);

        self.texture_handle = texture_handle;
        self.material_handle = material_handle;
        self.owned_sampler = owned_sampler;
        var material_instance = render.Material.withTextured(material_handle);
        if (self.alpha_mode) |mode| {
            material_instance.alpha_mode = mode;
        }
        self.material = material_instance;
    }

    pub fn unload(self: *Texture, ctx: AssetsContext) !void {
        const renderer = ctx.renderer orelse return;
        const texture_library = ctx.texture_library orelse return;
        const material_library = ctx.material_library orelse return;

        if (self.material_handle.isValid()) {
            _ = material_library.destroyMaterial(renderer, self.material_handle);
            self.material_handle = render.MaterialHandle.invalid();
        }
        if (self.texture_handle.isValid()) {
            _ = texture_library.destroyTexture(renderer, self.texture_handle);
            self.texture_handle = render.TextureHandle.invalid();
        }
        if (self.owned_sampler) |owned| {
            var sampler = owned;
            renderer.destroySampler(&sampler);
            self.owned_sampler = null;
        }
        self.material = render.Material.default;
    }
};

pub const DecodedSound = struct {
    format: u32,
    channels: u32,
    sample_rate: u32,
    frame_count: u64,
    pcm: []f32,
};

pub const Mesh = struct {
    uv_vertices: ?[]const render.VertexUv = null,
    pos3_color_vertices: ?[]const render.VertexPos3Color = null,
    indices: []const u16 = &.{},
    handle: render.MeshHandle = render.MeshHandle.invalid(),

    pub fn load(self: *Mesh, ctx: AssetsContext) !void {
        if (self.handle.isValid()) return;
        const renderer = ctx.renderer orelse return error.MissingRenderer;
        const library = ctx.mesh_library orelse return error.MissingMeshLibrary;
        if (self.indices.len == 0) return error.EmptyMeshIndices;

        if (self.uv_vertices) |vertices| {
            self.handle = try library.addMesh(renderer, vertices, self.indices);
            return;
        }
        if (self.pos3_color_vertices) |vertices| {
            self.handle = try library.addMeshPos3Color(renderer, vertices, self.indices);
            return;
        }

        return error.MissingMeshVertices;
    }

    pub fn unload(self: *Mesh, ctx: AssetsContext) !void {
        if (!self.handle.isValid()) return;
        const renderer = ctx.renderer orelse return;
        const library = ctx.mesh_library orelse return;
        _ = library.destroyMesh(renderer, self.handle);
        self.handle = render.MeshHandle.invalid();
    }
};

pub const Shader = struct {
    wgsl_source: ?[]const u8 = null,
    glsl_vertex_source: ?[]const u8 = null,
    glsl_fragment_source: ?[]const u8 = null,
    handle: render.ShaderHandle = render.ShaderHandle.invalid(),

    pub fn load(self: *Shader, ctx: AssetsContext) !void {
        if (self.handle.isValid()) return;
        const renderer = ctx.renderer orelse return error.MissingRenderer;
        const library = ctx.shader_library orelse return error.MissingShaderLibrary;

        const shader = try renderer.createShader(.{
            .wgsl = self.wgsl_source,
            .glsl_vertex = self.glsl_vertex_source,
            .glsl_fragment = self.glsl_fragment_source,
        });
        self.handle = try library.addShader(shader);
    }

    pub fn unload(self: *Shader, ctx: AssetsContext) !void {
        if (!self.handle.isValid()) return;
        const renderer = ctx.renderer orelse return;
        const library = ctx.shader_library orelse return;
        _ = library.destroyShader(renderer, self.handle);
        self.handle = render.ShaderHandle.invalid();
    }
};

pub const PostProcessShader = struct {
    wgsl_fragment: ?[]const u8 = null,
    handle: render.PostProcessShaderHandle = render.PostProcessShaderHandle.invalid(),
    generated_wgsl: ?[]u8 = null,

    pub fn load(self: *PostProcessShader, ctx: AssetsContext) !void {
        if (self.handle.isValid()) return;
        const renderer = ctx.renderer orelse return error.MissingRenderer;
        const library = ctx.post_process_shader_library orelse return error.MissingPostProcessShaderLibrary;
        const fragment = self.wgsl_fragment orelse return error.MissingShaderSource;

        const wgsl = try render.buildPostProcessWgsl(ctx.allocator, fragment);
        errdefer ctx.allocator.free(wgsl);
        const shader = try renderer.createPostProcessShader(.{ .wgsl = wgsl });
        errdefer {
            var cleanup = shader;
            renderer.destroyPostProcessShader(&cleanup);
        }
        self.generated_wgsl = wgsl;
        self.handle = try library.addShader(shader);
    }

    pub fn unload(self: *PostProcessShader, ctx: AssetsContext) !void {
        const renderer = ctx.renderer orelse return;
        const library = ctx.post_process_shader_library orelse return;
        if (self.handle.isValid()) {
            _ = library.destroyShader(renderer, self.handle);
            self.handle = render.PostProcessShaderHandle.invalid();
        }
        if (self.generated_wgsl) |wgsl| {
            ctx.allocator.free(wgsl);
            self.generated_wgsl = null;
        }
    }
};

pub const Sound = struct {
    path: ?[:0]const u8 = null,
    data: ?[]const u8 = null,
    bytes: ?[]u8 = null,
    decoded: ?DecodedSound = null,
    wasm_id: ?u32 = null,

    pub fn load(self: *Sound, ctx: AssetsContext) !void {
        if (self.data != null or self.bytes != null) return;
        if (self.path) |path| {
            self.bytes = try readFileSearch(ctx.allocator, ctx.io, path);
        }
    }

    pub fn unload(self: *Sound, ctx: AssetsContext) !void {
        if (self.decoded) |decoded| {
            ctx.allocator.free(decoded.pcm);
            self.decoded = null;
        }
        if (self.bytes) |bytes| {
            ctx.allocator.free(bytes);
            self.bytes = null;
        }
        if (builtin.target.cpu.arch.isWasm()) {
            if (self.wasm_id) |id| {
                wasmAudioUnload(id);
                self.wasm_id = null;
            }
        }
    }

    pub fn bytesSlice(self: *const Sound) ?[]const u8 {
        if (self.data) |data| return data;
        if (self.bytes) |bytes| return bytes;
        return null;
    }
};

pub const Font = struct {
    name: []const u8 = "Font",
    path: ?[:0]const u8 = null,
    data: ?[]const u8 = null,
    bytes: ?[]u8 = null,
    pixel_height: f32 = 64.0,
    atlas_width: u32 = 512,
    atlas_height: u32 = 512,
    handle: render.FontHandle = render.FontHandle.invalid(),

    pub fn embedded(name: []const u8, bytes: []const u8) Font {
        return .{
            .name = name,
            .data = bytes,
        };
    }

    pub fn file(name: []const u8, path: [:0]const u8) Font {
        return .{
            .name = name,
            .path = path,
        };
    }

    pub fn withPixelHeight(self: Font, pixel_height: f32) Font {
        var out = self;
        out.pixel_height = pixel_height;
        return out;
    }

    pub fn withAtlasSize(self: Font, width: u32, height: u32) Font {
        var out = self;
        out.atlas_width = width;
        out.atlas_height = height;
        return out;
    }

    pub fn load(self: *Font, ctx: AssetsContext) !void {
        if (self.handle.isValid()) return;

        const renderer = ctx.renderer orelse return error.MissingRenderer;
        const sampler = ctx.sampler orelse return error.MissingSampler;
        const font_library = ctx.font_library orelse return error.MissingFontLibrary;

        if (self.data == null and self.bytes == null) {
            if (self.path) |path| {
                self.bytes = try readFileSearch(ctx.allocator, ctx.io, path);
            } else {
                return error.MissingFontSource;
            }
        }

        var font = render.Font{
            .name = self.name,
            .data = if (self.data) |data| data else self.bytes.?,
            .pixel_height = self.pixel_height,
            .atlas_width = self.atlas_width,
            .atlas_height = self.atlas_height,
        };
        try font.load(ctx.allocator, renderer, sampler.*);
        errdefer font.unload(ctx.allocator, renderer);

        self.handle = try font_library.addFont(font);
    }

    pub fn unload(self: *Font, ctx: AssetsContext) !void {
        const renderer = ctx.renderer orelse return;
        const font_library = ctx.font_library orelse return;

        if (self.handle.isValid()) {
            _ = font_library.destroyFont(ctx.allocator, renderer, self.handle);
            self.handle = render.FontHandle.invalid();
        }
        if (self.bytes) |bytes| {
            ctx.allocator.free(bytes);
            self.bytes = null;
        }
    }
};

const ImageData = struct {
    width: u32,
    height: u32,
    data: []u8,
};

fn loadImageFromBytes(allocator: std.mem.Allocator, bytes: []const u8) !ImageData {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    const data_ptr = stb_image.c.stbi_load_from_memory(
        bytes.ptr,
        @intCast(bytes.len),
        &width,
        &height,
        &channels,
        4,
    );
    if (data_ptr == null) return error.ImageLoadFailed;
    defer stb_image.c.stbi_image_free(data_ptr);

    const pixel_count: usize = @intCast(width * height);
    const rgba_data = try allocator.alloc(u8, pixel_count * 4);
    const src_data: [*]const u8 = @ptrCast(data_ptr);
    @memcpy(rgba_data, src_data[0 .. pixel_count * 4]);

    return .{
        .width = @intCast(width),
        .height = @intCast(height),
        .data = rgba_data,
    };
}

fn loadImage(allocator: std.mem.Allocator, io: *const std.Io, path: [:0]const u8) !ImageData {
    const bytes = try readFileSearch(allocator, io, path);
    defer allocator.free(bytes);

    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    const data_ptr = stb_image.c.stbi_load_from_memory(
        bytes.ptr,
        @intCast(bytes.len),
        &width,
        &height,
        &channels,
        4,
    );
    if (data_ptr == null) return error.ImageLoadFailed;
    defer stb_image.c.stbi_image_free(data_ptr);

    const pixel_count: usize = @intCast(width * height);
    const rgba_data = try allocator.alloc(u8, pixel_count * 4);
    const src_data: [*]const u8 = @ptrCast(data_ptr);
    @memcpy(rgba_data, src_data[0 .. pixel_count * 4]);

    return .{
        .width = @intCast(width),
        .height = @intCast(height),
        .data = rgba_data,
    };
}

fn readFileSearch(allocator: std.mem.Allocator, io: *const std.Io, path: [:0]const u8) ![]u8 {
    const max_bytes: usize = 32 * 1024 * 1024;
    const resolved = try resolveFileSearch(allocator, io, path);
    defer allocator.free(resolved);
    return readFileAllocAbsolute(allocator, io, resolved, max_bytes);
}

fn resolveFileSearch(allocator: std.mem.Allocator, io: *const std.Io, path: [:0]const u8) ![:0]u8 {
    const rel_path = std.mem.sliceTo(path, 0);

    if (std.fs.path.isAbsolute(rel_path)) {
        if (fileExistsAbsolute(io, rel_path)) {
            return try allocator.dupeZ(u8, rel_path);
        }
    }

    if (fileExistsAbsolute(io, rel_path)) {
        return try allocator.dupeZ(u8, rel_path);
    }

    const cwd_path = std.Io.Dir.cwd().realPathFileAlloc(io.*, ".", allocator) catch null;
    defer if (cwd_path) |p| allocator.free(p);

    var base: ?[]const u8 = if (cwd_path) |p| p else null;
    var depth: usize = 0;
    while (base) |dir| : (depth += 1) {
        if (depth > 4) break;
        const candidate = try std.fs.path.join(allocator, &.{ dir, rel_path });
        defer allocator.free(candidate);

        if (fileExistsAbsolute(io, candidate)) {
            return try allocator.dupeZ(u8, candidate);
        }

        base = std.fs.path.dirname(dir);
    }

    return error.FileNotFound;
}

fn readFileAllocAbsolute(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    absolute_path: []const u8,
    max_bytes: usize,
) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io.*, absolute_path, allocator, std.Io.Limit.limited(max_bytes));
}

fn fileExistsAbsolute(io: *const std.Io, absolute_path: []const u8) bool {
    std.Io.Dir.cwd().access(io.*, absolute_path, .{}) catch return false;
    return true;
}

extern "env" fn wasmAudioUnload(id: u32) void;

// Imports
const std = @import("std");
const common = @import("common");
const render = @import("render");
const builtin = @import("builtin");
const stb_image = @import("stb_image");

test "import tests" {
    _ = gltf;
    _ = common;
    _ = Scene;
}
