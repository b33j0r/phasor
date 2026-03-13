const std = @import("std");
const backend = if (@import("builtin").target.cpu.arch.isWasm())
    @import("backend_web.zig")
else
    @import("backend_native.zig");
const mesh = @import("mesh.zig");
const post_process = @import("post_process.zig");
const text = @import("text.zig");

pub const BuildContext = struct {
    allocator: std.mem.Allocator,
    renderer: *backend.Renderer,
    default_sampler: *backend.Sampler,
    mesh_library: *mesh.MeshLibrary,
    shader_library: *mesh.ShaderLibrary,
    post_process_shader_library: *post_process.PostProcessShaderLibrary,
    texture_library: *mesh.TextureLibrary,
    material_library: *mesh.MaterialLibrary,
    font_library: *text.FontLibrary,

    pub fn meshFactory(self: *BuildContext) mesh.MeshFactory {
        return mesh.MeshFactory.init(self.allocator, self.mesh_library, self.renderer);
    }

    pub fn addMesh(self: *BuildContext, vertices: []const backend.VertexUv, indices: []const u16) !mesh.MeshHandle {
        return self.mesh_library.addMesh(self.renderer, vertices, indices);
    }

    pub fn addMeshPos3Color(self: *BuildContext, vertices: []const backend.VertexPos3Color, indices: []const u16) !mesh.MeshHandle {
        return self.mesh_library.addMeshPos3Color(self.renderer, vertices, indices);
    }

    pub fn updateMesh(self: *BuildContext, handle: mesh.MeshHandle, vertices: []const backend.VertexUv, indices: []const u16) !bool {
        return self.mesh_library.updateMesh(self.renderer, handle, vertices, indices);
    }

    pub fn updateMeshPos3Color(self: *BuildContext, handle: mesh.MeshHandle, vertices: []const backend.VertexPos3Color, indices: []const u16) !bool {
        return self.mesh_library.updateMeshPos3Color(self.renderer, handle, vertices, indices);
    }

    pub fn destroyMesh(self: *BuildContext, handle: mesh.MeshHandle) bool {
        return self.mesh_library.destroyMesh(self.renderer, handle);
    }

    pub fn createShader(self: *BuildContext, source: backend.ShaderSource) !mesh.ShaderHandle {
        const shader = try self.renderer.createShader(source);
        errdefer {
            var cleanup = shader;
            self.renderer.destroyShader(&cleanup);
        }
        return self.shader_library.addShader(shader);
    }

    pub fn destroyShader(self: *BuildContext, handle: mesh.ShaderHandle) bool {
        return self.shader_library.destroyShader(self.renderer, handle);
    }

    pub fn createPostProcessShader(self: *BuildContext, fragment_snippet: []const u8) !post_process.PostProcessShaderHandle {
        const wgsl = try post_process.buildWgsl(self.allocator, fragment_snippet);
        defer self.allocator.free(wgsl);
        const shader = try self.renderer.createPostProcessShader(.{ .wgsl = wgsl });
        errdefer {
            var cleanup = shader;
            self.renderer.destroyPostProcessShader(&cleanup);
        }
        return self.post_process_shader_library.addShader(shader);
    }

    pub fn destroyPostProcessShader(self: *BuildContext, handle: post_process.PostProcessShaderHandle) bool {
        return self.post_process_shader_library.destroyShader(self.renderer, handle);
    }

    pub fn createTextureRgba8(self: *BuildContext, width: u32, height: u32, data: []const u8) !mesh.TextureHandle {
        const texture = try self.renderer.createTextureRgba8(width, height, data);
        errdefer {
            var cleanup = texture;
            self.renderer.destroyTexture(&cleanup);
        }
        return self.texture_library.addTexture(texture);
    }

    pub fn destroyTexture(self: *BuildContext, handle: mesh.TextureHandle) bool {
        return self.texture_library.destroyTexture(self.renderer, handle);
    }

    pub fn createMaterial(self: *BuildContext, texture_handle: mesh.TextureHandle, sampler: ?backend.Sampler) !mesh.MaterialHandle {
        const texture = self.texture_library.get(texture_handle) orelse return error.MissingTexture;
        const material = try self.renderer.createMaterial(texture.*, sampler orelse self.default_sampler.*);
        errdefer {
            var cleanup = material;
            self.renderer.destroyMaterial(&cleanup);
        }
        return self.material_library.addMaterial(material);
    }

    pub fn destroyMaterial(self: *BuildContext, handle: mesh.MaterialHandle) bool {
        return self.material_library.destroyMaterial(self.renderer, handle);
    }

    pub fn getFont(self: *const BuildContext, handle: text.FontHandle) ?*const text.Font {
        return self.font_library.get(handle);
    }
};
