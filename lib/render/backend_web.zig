pub const RendererConfig = struct {
    present_mode: ?u32 = null,
    enable_validation: bool = false,
};

pub const Buffer = struct {
    handle: u32 = 0,
    size: u64 = 0,
};

pub const Texture = struct {
    handle: u32,
    width: u32,
    height: u32,
};

pub const Sampler = struct {
    handle: u32,
};

pub const Pipeline = struct {
    handle: u32,
};

pub const Material = struct {
    handle: u32,
};

pub const Mesh = struct {
    handle: u32,
};

pub const MeshInstance = struct {
    transform: common.Mat4 = common.Mat4.identity(),
    color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
};

pub const VertexColor = extern struct {
    position: [2]f32,
    color: [3]f32,
};

pub const VertexUv = extern struct {
    position: [2]f32,
    uv: [2]f32,
};

pub const Triangle = struct {
    vertices: [3]VertexColor,
};

pub const TexturedQuad = struct {
    mesh: Mesh,
    material: Material,
    instance: MeshInstance,
    blend: bool = false,
};

pub const DrawCmd = union(enum) {
    triangle: Triangle,
    textured_quad: TexturedQuad,
};

const InstanceData = extern struct {
    model0: [4]f32,
    model1: [4]f32,
    model2: [4]f32,
    model3: [4]f32,
    color: [4]f32,
};

extern "env" fn webgpu_init(canvas_id_ptr: [*]const u8, canvas_id_len: usize, enable_validation: bool) u32;
extern "env" fn webgpu_deinit(ctx: u32) void;
extern "env" fn webgpu_resize(ctx: u32, width: u32, height: u32) void;
extern "env" fn webgpu_begin_frame(ctx: u32, clear_r: f32, clear_g: f32, clear_b: f32, clear_a: f32) void;
extern "env" fn webgpu_draw_triangle(ctx: u32) void;
extern "env" fn webgpu_draw_textured_quad(ctx: u32, mesh_handle: u32, material_handle: u32, instance_ptr: *const InstanceData, blend: u32) void;
extern "env" fn webgpu_end_frame(ctx: u32) void;
extern "env" fn webgpu_create_sampler(ctx: u32) u32;
extern "env" fn webgpu_destroy_sampler(ctx: u32, handle: u32) void;
extern "env" fn webgpu_create_texture_rgba8(ctx: u32, sampler_handle: u32, data_ptr: [*]const u8, data_len: usize, width: u32, height: u32) u32;
extern "env" fn webgpu_destroy_texture(ctx: u32, handle: u32) void;
extern "env" fn webgpu_create_mesh(ctx: u32, vertices_ptr: [*]const u8, vertices_len: usize, indices_ptr: [*]const u8, indices_len: usize) u32;
extern "env" fn webgpu_destroy_mesh(ctx: u32, handle: u32) void;
extern "env" fn webgpu_create_material(ctx: u32, texture_handle: u32, sampler_handle: u32) u32;
extern "env" fn webgpu_destroy_material(ctx: u32, handle: u32) void;

pub const Renderer = struct {
    ctx: u32,
    surface_size: Size,

    pub fn init(_: std.mem.Allocator, target: SurfaceTarget, config: RendererConfig) !Renderer {
        if (!builtin.target.cpu.arch.isWasm()) return error.InvalidTarget;
        if (target != .web) return error.InvalidSurfaceTarget;
        const canvas = target.web;
        const ctx = webgpu_init(canvas.canvas_id.ptr, canvas.canvas_id.len, config.enable_validation);
        if (ctx == 0) return error.WebGpuInitFailed;
        return Renderer{
            .ctx = ctx,
            .surface_size = canvas.size,
        };
    }

    pub fn deinit(self: *Renderer) void {
        webgpu_deinit(self.ctx);
    }

    pub fn resize(self: *Renderer, width: u32, height: u32) void {
        if (width == 0 or height == 0) return;
        self.surface_size = .{ .width = width, .height = height };
        webgpu_resize(self.ctx, width, height);
    }

    pub fn beginFrame(self: *Renderer, clear: Color) !Frame {
        const clear_f = Color.F32.fromColor(clear);
        webgpu_begin_frame(self.ctx, clear_f.r, clear_f.g, clear_f.b, clear_f.a);
        return Frame{ .renderer = self };
    }

    pub fn createSampler(self: *Renderer) !Sampler {
        return Sampler{ .handle = webgpu_create_sampler(self.ctx) };
    }

    pub fn destroySampler(self: *Renderer, sampler: *Sampler) void {
        if (sampler.handle == 0) return;
        webgpu_destroy_sampler(self.ctx, sampler.handle);
        sampler.handle = 0;
    }

    pub fn createTextureRgba8(self: *Renderer, width: u32, height: u32, data: []const u8) !Texture {
        const handle = webgpu_create_texture_rgba8(self.ctx, 0, data.ptr, data.len, width, height);
        return Texture{
            .handle = handle,
            .width = width,
            .height = height,
        };
    }

    pub fn destroyTexture(self: *Renderer, texture: *Texture) void {
        if (texture.handle == 0) return;
        webgpu_destroy_texture(self.ctx, texture.handle);
        texture.handle = 0;
    }

    pub fn createMaterial(self: *Renderer, texture: Texture, sampler: Sampler) !Material {
        const handle = webgpu_create_material(self.ctx, texture.handle, sampler.handle);
        return Material{ .handle = handle };
    }

    pub fn destroyMaterial(self: *Renderer, material: *Material) void {
        if (material.handle == 0) return;
        webgpu_destroy_material(self.ctx, material.handle);
        material.handle = 0;
    }

    pub fn createMesh(self: *Renderer, vertices: []const VertexUv, indices: []const u16) !Mesh {
        const vbytes = std.mem.sliceAsBytes(vertices);
        const ibytes = std.mem.sliceAsBytes(indices);
        const handle = webgpu_create_mesh(self.ctx, vbytes.ptr, vbytes.len, ibytes.ptr, ibytes.len);
        return Mesh{ .handle = handle };
    }

    pub fn destroyMesh(self: *Renderer, mesh: *Mesh) void {
        if (mesh.handle == 0) return;
        webgpu_destroy_mesh(self.ctx, mesh.handle);
        mesh.handle = 0;
    }
};

pub const Frame = struct {
    renderer: *Renderer,

    pub fn draw(self: *Frame, cmd: DrawCmd) void {
        switch (cmd) {
            .triangle => webgpu_draw_triangle(self.renderer.ctx),
            .textured_quad => |quad| self.drawTexturedQuad(quad),
        }
    }

    fn drawTexturedQuad(self: *Frame, quad: TexturedQuad) void {
        const instance = buildInstanceData(quad.instance);
        const blend: u32 = if (quad.blend) 1 else 0;
        webgpu_draw_textured_quad(self.renderer.ctx, quad.mesh.handle, quad.material.handle, &instance, blend);
    }

    pub fn endFrame(self: *Frame) !void {
        webgpu_end_frame(self.renderer.ctx);
    }
};

fn buildInstanceData(instance: MeshInstance) InstanceData {
    const m = instance.transform.m;
    return .{
        .model0 = .{ m[0][0], m[0][1], m[0][2], m[0][3] },
        .model1 = .{ m[1][0], m[1][1], m[1][2], m[1][3] },
        .model2 = .{ m[2][0], m[2][1], m[2][2], m[2][3] },
        .model3 = .{ m[3][0], m[3][1], m[3][2], m[3][3] },
        .color = instance.color,
    };
}

// Imports
const std = @import("std");
const builtin = @import("builtin");
const utils = @import("utils.zig");
const common = @import("common");

const Color = common.Color;
const Size = utils.Size;
const SurfaceTarget = utils.SurfaceTarget;
