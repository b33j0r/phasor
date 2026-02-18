pub const AssetsContext = struct {
    allocator: std.mem.Allocator,
    io: *const std.Io,
    renderer: ?*render.Renderer = null,
    sampler: ?*render.Sampler = null,
    mesh_library: ?*render.MeshLibrary = null,
    shader_library: ?*render.ShaderLibrary = null,
};

pub const Texture = struct {
    path: ?[:0]const u8 = null,
    data: ?[]const u8 = null,
    width: u32 = 0,
    height: u32 = 0,
    texture: ?render.Texture = null,
    material: ?render.Material = null,

    pub fn load(self: *Texture, ctx: AssetsContext) !void {
        if (self.material != null) return;

        const renderer = ctx.renderer orelse return error.MissingRenderer;
        const sampler = ctx.sampler orelse return error.MissingSampler;

        if (builtin.target.cpu.arch.isWasm()) {
            const image = if (self.data) |bytes|
                try loadImageFromBytes(ctx.allocator, bytes)
            else
                return error.MissingImageSource;
            defer ctx.allocator.free(image.data);

            self.width = image.width;
            self.height = image.height;

            var texture = try renderer.createTextureRgba8(self.width, self.height, image.data);
            errdefer renderer.destroyTexture(&texture);

            const material = try renderer.createMaterial(texture, sampler.*);

            self.texture = texture;
            self.material = material;
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

        var texture = try renderer.createTextureRgba8(self.width, self.height, image.data);
        errdefer renderer.destroyTexture(&texture);

        const material = try renderer.createMaterial(texture, sampler.*);

        self.texture = texture;
        self.material = material;
    }

    pub fn unload(self: *Texture, ctx: AssetsContext) !void {
        const renderer = ctx.renderer orelse return;

        if (self.material) |*material| {
            renderer.destroyMaterial(material);
            self.material = null;
        }
        if (self.texture) |*texture| {
            renderer.destroyTexture(texture);
            self.texture = null;
        }
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
    const rel_path = std.mem.sliceTo(path, 0);
    const max_bytes: usize = 32 * 1024 * 1024;

    if (std.fs.path.isAbsolute(rel_path)) {
        if (readFileAllocAbsolute(allocator, io, rel_path, max_bytes)) |bytes| {
            return bytes;
        } else |_| {}
    }

    if (std.Io.Dir.cwd().readFileAlloc(io.*, rel_path, allocator, std.Io.Limit.limited(max_bytes))) |bytes| {
        return bytes;
    } else |_| {}

    const cwd_path = std.Io.Dir.cwd().realPathFileAlloc(io.*, ".", allocator) catch null;
    defer if (cwd_path) |p| allocator.free(p);

    var base: ?[]const u8 = if (cwd_path) |p| p else null;
    var depth: usize = 0;
    while (base) |dir| : (depth += 1) {
        if (depth > 4) break;
        const candidate = try std.fs.path.join(allocator, &.{ dir, rel_path });
        defer allocator.free(candidate);

        if (readFileAllocAbsolute(allocator, io, candidate, max_bytes)) |bytes| {
            return bytes;
        } else |_| {}

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

extern "env" fn wasmAudioUnload(id: u32) void;

// Imports
const std = @import("std");
const render = @import("render");
const builtin = @import("builtin");
const stb_image = @import("stb_image");
