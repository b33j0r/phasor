const std = @import("std");
const backend = if (@import("builtin").target.cpu.arch.isWasm())
    @import("backend_web.zig")
else
    @import("backend_native.zig");

pub const PostProcessShaderHandle = struct {
    index: u32,
    generation: u32,

    pub fn invalid() PostProcessShaderHandle {
        return .{ .index = std.math.maxInt(u32), .generation = 0 };
    }

    pub fn isValid(self: PostProcessShaderHandle) bool {
        return self.index != std.math.maxInt(u32);
    }
};

pub const PostProcessParams = extern struct {
    values: [16]f32 = @splat(0.0),

    pub fn setVec4(self: *PostProcessParams, index: usize, value: [4]f32) void {
        if (index >= 4) return;
        const base = index * 4;
        self.values[base + 0] = value[0];
        self.values[base + 1] = value[1];
        self.values[base + 2] = value[2];
        self.values[base + 3] = value[3];
    }

    pub fn vec4(self: *const PostProcessParams, index: usize) [4]f32 {
        if (index >= 4) return .{ 0.0, 0.0, 0.0, 0.0 };
        const base = index * 4;
        return .{
            self.values[base + 0],
            self.values[base + 1],
            self.values[base + 2],
            self.values[base + 3],
        };
    }
};

pub const PostProcessMaterial = struct {
    shader: PostProcessShaderHandle = PostProcessShaderHandle.invalid(),
    params: PostProcessParams = .{},
    blend: bool = false,
};

pub const PostProcessSceneScope = struct {
    // Scene layers up to and including this value are captured into the chain input.
    max_layer: i32 = std.math.maxInt(i32),
};

pub const PostProcessPass = struct {
    material: PostProcessMaterial,
    input_slot: u32 = 0,
    output_slot: u32 = 1,
    scene: PostProcessSceneScope = .{},
    enabled: bool = true,
};

pub const PostProcessOrder = struct {
    value: i32 = 0,
};

pub const PostProcessPresentSlot = struct {
    slot: u32 = 0,
};

pub const PostProcessShaderLibrary = struct {
    allocator: std.mem.Allocator,
    slots: std.ArrayListUnmanaged(PostProcessShaderSlot) = .empty,
    free_list: std.ArrayListUnmanaged(u32) = .empty,

    pub fn init(allocator: std.mem.Allocator) PostProcessShaderLibrary {
        return .{
            .allocator = allocator,
            .slots = .empty,
            .free_list = .empty,
        };
    }

    pub fn deinit(self: *PostProcessShaderLibrary) void {
        self.slots.deinit(self.allocator);
        self.free_list.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn destroyShaders(self: *PostProcessShaderLibrary, renderer: *backend.Renderer) void {
        self.free_list.clearRetainingCapacity();
        for (self.slots.items, 0..) |*slot, index| {
            if (!slot.alive) continue;
            renderer.destroyPostProcessShader(&slot.shader);
            slot.alive = false;
            slot.generation +%= 1;
            _ = self.free_list.append(self.allocator, @intCast(index)) catch {};
        }
    }

    pub fn addShader(self: *PostProcessShaderLibrary, shader: backend.PostProcessShader) !PostProcessShaderHandle {
        if (self.free_list.items.len > 0) {
            const index = self.free_list.pop() orelse unreachable;
            var slot = &self.slots.items[@intCast(index)];
            slot.shader = shader;
            slot.alive = true;
            return .{ .index = index, .generation = slot.generation };
        }

        const index: u32 = @intCast(self.slots.items.len);
        try self.slots.append(self.allocator, .{
            .shader = shader,
            .generation = 1,
            .alive = true,
        });
        return .{ .index = index, .generation = 1 };
    }

    pub fn get(self: *const PostProcessShaderLibrary, handle: PostProcessShaderHandle) ?*const backend.PostProcessShader {
        const slot = self.slotPtrConst(handle) orelse return null;
        return &slot.shader;
    }

    pub fn destroyShader(self: *PostProcessShaderLibrary, renderer: *backend.Renderer, handle: PostProcessShaderHandle) bool {
        const slot = self.slotPtr(handle) orelse return false;
        renderer.destroyPostProcessShader(&slot.shader);
        slot.alive = false;
        slot.generation +%= 1;
        _ = self.free_list.append(self.allocator, handle.index) catch {};
        return true;
    }

    fn slotPtr(self: *PostProcessShaderLibrary, handle: PostProcessShaderHandle) ?*PostProcessShaderSlot {
        if (!handle.isValid()) return null;
        const index: usize = @intCast(handle.index);
        if (index >= self.slots.items.len) return null;
        const slot = &self.slots.items[index];
        if (!slot.alive or slot.generation != handle.generation) return null;
        return slot;
    }

    fn slotPtrConst(self: *const PostProcessShaderLibrary, handle: PostProcessShaderHandle) ?*const PostProcessShaderSlot {
        if (!handle.isValid()) return null;
        const index: usize = @intCast(handle.index);
        if (index >= self.slots.items.len) return null;
        const slot = &self.slots.items[index];
        if (!slot.alive or slot.generation != handle.generation) return null;
        return slot;
    }
};

const PostProcessShaderSlot = struct {
    shader: backend.PostProcessShader,
    generation: u32,
    alive: bool,
};

pub fn buildWgsl(allocator: std.mem.Allocator, fragment_snippet: []const u8) ![]u8 {
    return std.mem.concat(allocator, u8, &[_][]const u8{
        wgsl_prefix,
        fragment_snippet,
        wgsl_suffix,
    });
}

const wgsl_prefix =
    \\struct PostProcessUniforms {
    \\    params0: vec4<f32>,
    \\    params1: vec4<f32>,
    \\    params2: vec4<f32>,
    \\    params3: vec4<f32>,
    \\    meta0: vec4<f32>,
    \\};
    \\
    \\struct VertexOut {
    \\    @builtin(position) position: vec4<f32>,
    \\    @location(0) uv: vec2<f32>,
    \\};
    \\
    \\@group(0) @binding(0) var post_sampler: sampler;
    \\@group(0) @binding(1) var post_texture: texture_2d<f32>;
    \\@group(0) @binding(2) var<uniform> post_uniforms: PostProcessUniforms;
    \\
    \\@vertex
    \\fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOut {
    \\    var positions = array<vec2<f32>, 3>(
    \\        vec2<f32>(-1.0, -3.0),
    \\        vec2<f32>(-1.0, 1.0),
    \\        vec2<f32>(3.0, 1.0),
    \\    );
    \\    var uvs = array<vec2<f32>, 3>(
    \\        vec2<f32>(0.0, 2.0),
    \\        vec2<f32>(0.0, 0.0),
    \\        vec2<f32>(2.0, 0.0),
    \\    );
    \\    var out: VertexOut;
    \\    out.position = vec4<f32>(positions[vertex_index], 0.0, 1.0);
    \\    out.uv = uvs[vertex_index];
    \\    return out;
    \\}
    \\
;

const wgsl_suffix =
    \\
    \\@fragment
    \\fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    \\    let source = textureSample(post_texture, post_sampler, in.uv);
    \\    let texel_size = post_uniforms.meta0.xy;
    \\    let viewport_size = post_uniforms.meta0.zw;
    \\    return post_process_color(
    \\        in.uv,
    \\        source,
    \\        post_uniforms.params0,
    \\        post_uniforms.params1,
    \\        post_uniforms.params2,
    \\        post_uniforms.params3,
    \\        texel_size,
    \\        viewport_size,
    \\    );
    \\}
;
