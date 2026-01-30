pub const HorizontalAlignment = enum {
    Left,
    Center,
    Right,
};

pub const VerticalAlignment = enum {
    Top,
    Center,
    Baseline,
    Bottom,
};

pub const Text = struct {
    content: []const u8 = "",
    color: common.Color = common.Color.WHITE,
    font_size: f32 = 72.0,
    horizontal_alignment: HorizontalAlignment = .Left,
    vertical_alignment: VerticalAlignment = .Top,
    mesh_handle: mesh.MeshHandle = mesh.MeshHandle.invalid(),
    layout_hash: u64 = 0,
};

pub const DefaultFont = struct {
    font: Font,
};

pub const Font = struct {
    name: []const u8,
    data: []const u8,
    pixel_height: f32 = 64.0,
    atlas_width: u32 = 512,
    atlas_height: u32 = 512,
    atlas: ?FontAtlas = null,
    texture: ?Texture = null,
    material: ?Material = null,

    pub fn orbitronDefault() Font {
        return .{
            .name = "Orbitron",
            .data = @embedFile("assets/fonts/Orbitron/Orbitron-VariableFont_wght.ttf"),
        };
    }

    pub fn load(self: *Font, allocator: std.mem.Allocator, renderer: *Renderer, sampler: Sampler) !void {
        if (self.material != null) return;

        var atlas = try FontAtlas.init(allocator, self.data, self.pixel_height, self.atlas_width, self.atlas_height);
        errdefer atlas.deinit(allocator);
        errdefer if (atlas.char_data) |data| allocator.free(data);
        _ = try atlas.bakeASCII(32, 96, allocator);

        const pixel_count: usize = @intCast(self.atlas_width * self.atlas_height);
        var rgba = try allocator.alloc(u8, pixel_count * 4);
        defer allocator.free(rgba);
        for (0..pixel_count) |i| {
            const alpha = atlas.bitmap[i];
            const base = i * 4;
            rgba[base + 0] = 255;
            rgba[base + 1] = 255;
            rgba[base + 2] = 255;
            rgba[base + 3] = alpha;
        }

        var texture = try renderer.createTextureRgba8(self.atlas_width, self.atlas_height, rgba);
        errdefer renderer.destroyTexture(&texture);

        var material = try renderer.createMaterial(texture, sampler);
        errdefer renderer.destroyMaterial(&material);

        self.atlas = atlas;
        self.texture = texture;
        self.material = material;
    }

    pub fn unload(self: *Font, allocator: std.mem.Allocator, renderer: *Renderer) void {
        if (self.material) |*material| {
            renderer.destroyMaterial(material);
            self.material = null;
        }
        if (self.texture) |*texture| {
            renderer.destroyTexture(texture);
            self.texture = null;
        }
        if (self.atlas) |*atlas| {
            if (atlas.char_data) |data| allocator.free(data);
            atlas.deinit(allocator);
            self.atlas = null;
        }
    }
};

pub const FontAtlas = struct {
    texture_width: u32,
    texture_height: u32,
    bitmap: []u8,
    font_info: c.stbtt_fontinfo,
    font_data: []const u8,
    scale: f32,
    baseline: f32,
    char_data: ?[]CharData = null,

    pub fn init(allocator: std.mem.Allocator, font_data: []const u8, font_height: f32, atlas_width: u32, atlas_height: u32) !FontAtlas {
        var font_info: c.stbtt_fontinfo = undefined;
        if (c.stbtt_InitFont(&font_info, font_data.ptr, 0) == 0) {
            return error.FontInitFailed;
        }

        const scale = c.stbtt_ScaleForPixelHeight(&font_info, font_height);

        var ascent: c_int = 0;
        var descent: c_int = 0;
        var line_gap: c_int = 0;
        c.stbtt_GetFontVMetrics(&font_info, &ascent, &descent, &line_gap);
        const baseline = @as(f32, @floatFromInt(ascent)) * scale;

        const bitmap = try allocator.alloc(u8, @as(usize, @intCast(atlas_width * atlas_height)));
        @memset(bitmap, 0);

        return .{
            .texture_width = atlas_width,
            .texture_height = atlas_height,
            .bitmap = bitmap,
            .font_info = font_info,
            .font_data = font_data,
            .scale = scale,
            .baseline = baseline,
        };
    }

    pub fn deinit(self: *FontAtlas, allocator: std.mem.Allocator) void {
        allocator.free(self.bitmap);
    }

    pub fn bakeASCII(self: *FontAtlas, first_char: u8, num_chars: u8, allocator: std.mem.Allocator) ![]CharData {
        const char_data = try allocator.alloc(CharData, @as(usize, @intCast(num_chars)));
        self.char_data = char_data;

        var x: u32 = 0;
        var y: u32 = 0;
        var row_height: u32 = 0;

        for (0..num_chars) |i| {
            const codepoint: c_int = first_char + @as(u8, @intCast(i));

            var width: c_int = 0;
            var height: c_int = 0;
            var xoff: c_int = 0;
            var yoff: c_int = 0;

            const glyph_bitmap = c.stbtt_GetCodepointBitmap(
                &self.font_info,
                0,
                self.scale,
                codepoint,
                &width,
                &height,
                &xoff,
                &yoff,
            );
            defer c.stbtt_FreeBitmap(glyph_bitmap, null);

            const w = @as(u32, @intCast(width));
            const h = @as(u32, @intCast(height));

            if (x + w > self.texture_width) {
                x = 0;
                y += row_height + 1;
                row_height = 0;
            }

            if (y + h > self.texture_height) {
                return error.AtlasFull;
            }

            for (0..h) |row| {
                const dst_offset = (y + row) * self.texture_width + x;
                const src_offset = row * w;
                @memcpy(
                    self.bitmap[dst_offset..][0..w],
                    glyph_bitmap[src_offset..][0..w],
                );
            }

            var advance: c_int = 0;
            var lsb: c_int = 0;
            c.stbtt_GetCodepointHMetrics(&self.font_info, codepoint, &advance, &lsb);

            char_data[i] = .{
                .x0 = @floatFromInt(x),
                .y0 = @floatFromInt(y),
                .x1 = @floatFromInt(x + w),
                .y1 = @floatFromInt(y + h),
                .xoff = @floatFromInt(xoff),
                .yoff = @floatFromInt(yoff),
                .xadvance = @as(f32, @floatFromInt(advance)) * self.scale,
            };

            x += w + 1;
            row_height = @max(row_height, h);
        }

        return char_data;
    }
};

pub const CharData = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    xoff: f32,
    yoff: f32,
    xadvance: f32,
};

pub const MeshData = struct {
    vertices: []VertexUv,
    indices: []u16,

    pub fn deinit(self: *MeshData, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
        self.* = undefined;
    }
};

pub fn layoutHash(text: Text) u64 {
    var hash = std.hash.Wyhash.init(0);
    hash.update(text.content);
    hash.update(std.mem.asBytes(&text.font_size));
    const h_align: u8 = @intFromEnum(text.horizontal_alignment);
    const v_align: u8 = @intFromEnum(text.vertical_alignment);
    hash.update(std.mem.asBytes(&h_align));
    hash.update(std.mem.asBytes(&v_align));
    return hash.final();
}

pub fn buildMesh(allocator: std.mem.Allocator, font: *const Font, text: Text) !MeshData {
    const atlas = font.atlas orelse return error.FontNotLoaded;
    const char_data = atlas.char_data orelse return error.FontNotLoaded;
    if (text.content.len == 0) return error.EmptyText;

    const scale = text.font_size / font.pixel_height;
    const line_height = font.pixel_height * scale;

    const Line = struct {
        start_index: usize,
        end_index: usize,
        width: f32,
    };

    var lines: std.ArrayList(Line) = .empty;
    defer lines.deinit(allocator);

    var current_line_start: usize = 0;
    var current_line_width: f32 = 0;
    var glyph_count: usize = 0;

    var char_idx: usize = 0;
    while (char_idx < text.content.len) : (char_idx += 1) {
        const char = text.content[char_idx];
        if (char == '\n' or char == '\r') {
            try lines.append(allocator, .{
                .start_index = current_line_start,
                .end_index = char_idx,
                .width = current_line_width,
            });
            if (char == '\r' and char_idx + 1 < text.content.len and text.content[char_idx + 1] == '\n') {
                char_idx += 1;
            }
            current_line_start = char_idx + 1;
            current_line_width = 0;
            continue;
        }

        if (char < 32 or char >= 128) continue;
        const data = char_data[char - 32];
        current_line_width += data.xadvance * scale;
        glyph_count += 1;
    }

    try lines.append(allocator, .{
        .start_index = current_line_start,
        .end_index = char_idx,
        .width = current_line_width,
    });

    if (glyph_count == 0) return error.EmptyText;

    const vertex_count: usize = glyph_count * 6;
    const max_vertices: usize = std.math.maxInt(u16);
    if (vertex_count > max_vertices) return error.TooManyVertices;

    var vertices = try allocator.alloc(VertexUv, vertex_count);
    var indices = try allocator.alloc(u16, vertex_count);
    errdefer allocator.free(vertices);
    errdefer allocator.free(indices);

    const total_height = @as(f32, @floatFromInt(lines.items.len)) * line_height;
    const start_y: f32 = switch (text.vertical_alignment) {
        .Top => 0,
        .Center => -total_height / 2.0,
        .Baseline => -(atlas.baseline * scale),
        .Bottom => -total_height,
    };

    const atlas_w = @as(f32, @floatFromInt(atlas.texture_width));
    const atlas_h = @as(f32, @floatFromInt(atlas.texture_height));

    var v_idx: usize = 0;
    var i_idx: usize = 0;
    for (lines.items, 0..) |line, line_idx| {
        const x_offset: f32 = switch (text.horizontal_alignment) {
            .Left => 0,
            .Center => -line.width / 2.0,
            .Right => -line.width,
        };

        const y = start_y + (@as(f32, @floatFromInt(line_idx)) * line_height);
        var x: f32 = x_offset;

        var i: usize = line.start_index;
        while (i < line.end_index) : (i += 1) {
            const char = text.content[i];
            if (char < 32 or char >= 128) continue;
            const data = char_data[char - 32];

            const x0 = x + data.xoff * scale;
            const y0 = y + (data.yoff + atlas.baseline) * scale;
            const x1 = x0 + (data.x1 - data.x0) * scale;
            const y1 = y0 + (data.y1 - data.y0) * scale;

            const tex_u0 = data.x0 / atlas_w;
            const tex_v0 = data.y0 / atlas_h;
            const tex_u1 = data.x1 / atlas_w;
            const tex_v1 = data.y1 / atlas_h;

            vertices[v_idx + 0] = .{ .position = .{ x0, y0 }, .uv = .{ tex_u0, tex_v0 } };
            vertices[v_idx + 1] = .{ .position = .{ x1, y0 }, .uv = .{ tex_u1, tex_v0 } };
            vertices[v_idx + 2] = .{ .position = .{ x1, y1 }, .uv = .{ tex_u1, tex_v1 } };
            vertices[v_idx + 3] = .{ .position = .{ x0, y0 }, .uv = .{ tex_u0, tex_v0 } };
            vertices[v_idx + 4] = .{ .position = .{ x1, y1 }, .uv = .{ tex_u1, tex_v1 } };
            vertices[v_idx + 5] = .{ .position = .{ x0, y1 }, .uv = .{ tex_u0, tex_v1 } };

            indices[i_idx + 0] = @intCast(v_idx + 0);
            indices[i_idx + 1] = @intCast(v_idx + 1);
            indices[i_idx + 2] = @intCast(v_idx + 2);
            indices[i_idx + 3] = @intCast(v_idx + 3);
            indices[i_idx + 4] = @intCast(v_idx + 4);
            indices[i_idx + 5] = @intCast(v_idx + 5);

            v_idx += 6;
            i_idx += 6;
            x += data.xadvance * scale;
        }
    }

    return .{
        .vertices = vertices,
        .indices = indices,
    };
}

const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");
const mesh = @import("mesh.zig");
const stb = @import("stb");
const c = stb.c;
const backend = if (builtin.target.cpu.arch.isWasm())
    @import("backend_web.zig")
else
    @import("backend_native.zig");
const VertexUv = backend.VertexUv;
const Renderer = backend.Renderer;
const Texture = backend.Texture;
const Material = backend.Material;
const Sampler = backend.Sampler;
