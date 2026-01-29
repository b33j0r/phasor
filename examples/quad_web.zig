const std = @import("std");
const render = @import("render");
const common = @import("common");

var g_renderer: ?render.Renderer = null;
var g_mesh: render.Mesh = undefined;
var g_material: render.Material = undefined;
var g_sampler: render.Sampler = undefined;
var g_texture: render.Texture = undefined;

pub fn main() void {}

pub export fn wasmInit() void {
    const target = render.surface_canvas.fromCanvasId("#canvas");
    var renderer = render.Renderer.init(std.heap.page_allocator, target, .{}) catch return;

    const quad_vertices = [_]render.VertexUv{
        .{ .position = .{ -0.5, -0.5 }, .uv = .{ 0.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5 }, .uv = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5 }, .uv = .{ 1.0, 0.0 } },
        .{ .position = .{ -0.5, 0.5 }, .uv = .{ 0.0, 0.0 } },
    };
    const quad_indices = [_]u16{ 0, 1, 2, 2, 3, 0 };
    g_mesh = renderer.createMesh(quad_vertices[0..], quad_indices[0..]) catch return;

    g_sampler = renderer.createSampler() catch return;

    const texture_data = [_]u8{
        255, 255, 255, 255, 40, 40, 40, 255,
        40, 40, 40, 255, 255, 255, 255, 255,
    };
    g_texture = renderer.createTextureRgba8(2, 2, texture_data[0..]) catch return;
    g_material = renderer.createMaterial(g_texture, g_sampler) catch return;

    g_renderer = renderer;
}

pub export fn wasmResize(width: u32, height: u32) void {
    if (g_renderer) |*renderer| {
        renderer.resize(width, height);
    }
}

pub export fn wasmFrame() void {
    if (g_renderer) |*renderer| {
        var frame = renderer.beginFrame(.{ .r = 0.04, .g = 0.06, .b = 0.09, .a = 1.0 }) catch return;
        const transform = common.Mat4.scale(1.2, 1.2, 1.0);
        frame.draw(.{ .textured_quad = .{
            .mesh = g_mesh,
            .material = g_material,
            .instance = .{ .transform = transform, .color = .{ 1.0, 1.0, 1.0, 1.0 } },
        } });
        _ = frame.endFrame() catch return;
    }
}
