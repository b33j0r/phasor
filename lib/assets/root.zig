pub const AssetsContext = struct {
    allocator: std.mem.Allocator,
    io: *const std.Io,
    renderer: ?*render.Renderer = null,
    sampler: ?*render.Sampler = null,
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

    const cwd_path = std.process.getCwdAlloc(allocator) catch null;
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

// Imports
const std = @import("std");
const render = @import("render");
const builtin = @import("builtin");
const stb_image = @import("stb_image");
