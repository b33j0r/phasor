pub const ShapeKind = enum(u8) {
    sprite_quad,
    circle,
    rectangle,
};

pub const GeneratedMeshKey = struct {
    kind: ShapeKind,
    a: u32 = 0,
    b: u32 = 0,
    c: u32 = 0,
    d: u32 = 0,

    pub fn spriteQuad(width: f32, height: f32) GeneratedMeshKey {
        return .{
            .kind = .sprite_quad,
            .a = floatBits(width),
            .b = floatBits(height),
        };
    }

    pub fn circle(radius: f32, segments: u32) GeneratedMeshKey {
        return .{
            .kind = .circle,
            .a = floatBits(radius),
            .b = segments,
        };
    }

    pub fn rectangle(width: f32, height: f32) GeneratedMeshKey {
        return .{
            .kind = .rectangle,
            .a = floatBits(width),
            .b = floatBits(height),
        };
    }
};

pub const GeneratedMeshInstance = struct {
    key: GeneratedMeshKey,
};

pub const GeneratedMeshCache = struct {
    allocator: std.mem.Allocator,
    generation: u64 = 0,
    map: std.AutoHashMap(GeneratedMeshKey, Entry),

    pub const Entry = struct {
        mesh_handle: mesh.MeshHandle,
        last_seen_generation: u64,
    };

    pub fn init(allocator: std.mem.Allocator) GeneratedMeshCache {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(GeneratedMeshKey, Entry).init(allocator),
        };
    }

    pub fn deinit(self: *GeneratedMeshCache) void {
        self.map.deinit();
        self.* = undefined;
    }

    pub fn beginFrame(self: *GeneratedMeshCache) void {
        self.generation +%= 1;
        if (self.generation == 0) self.generation = 1;
    }

    pub fn touch(self: *GeneratedMeshCache, key: GeneratedMeshKey, mesh_handle: mesh.MeshHandle) !void {
        try self.map.put(key, .{
            .mesh_handle = mesh_handle,
            .last_seen_generation = self.generation,
        });
    }
};

pub const Circle = struct {
    radius: f32 = 0.5,
    segments: u32 = 32,
    color: common.Color = common.Color.WHITE,
    material: ?mesh.Material = null,
    shader_handle: mesh.ShaderHandle = mesh.ShaderHandle.invalid(),
    scene_material: mesh.SceneMaterial = .{},

    pub fn meshKey(self: Circle) GeneratedMeshKey {
        return .circle(self.radius, self.segments);
    }

    pub fn withMaterial(self: Circle, material: mesh.Material) Circle {
        var out = self;
        out.material = material;
        return out;
    }
};

pub const Rectangle = struct {
    width: f32 = 1.0,
    height: f32 = 1.0,
    color: common.Color = common.Color.WHITE,
    material: ?mesh.Material = null,
    shader_handle: mesh.ShaderHandle = mesh.ShaderHandle.invalid(),
    scene_material: mesh.SceneMaterial = .{},

    pub fn meshKey(self: Rectangle) GeneratedMeshKey {
        return .rectangle(self.width, self.height);
    }

    pub fn withMaterial(self: Rectangle, material: mesh.Material) Rectangle {
        var out = self;
        out.material = material;
        return out;
    }
};

pub const ShapesModule = struct {
    pub fn install(app: *AppCommands, commands: *Commands) !void {
        if (!commands.hasResource(GeneratedMeshCache)) {
            try commands.insertResource(GeneratedMeshCache.init(commands.allocator));
        }

        try app.addSystem("BeforeFrame", updateGeneratedMeshes);
        try app.addSystem("AfterFrame", removeOrphanedGeneratedMeshInstances);
        try app.addSystem("AfterFrame", cleanupGeneratedMeshes);
    }

    pub fn uninstall(app: *AppCommands) void {
        app.removeSystem(updateGeneratedMeshes);
        app.removeSystem(removeOrphanedGeneratedMeshInstances);
        app.removeSystem(cleanupGeneratedMeshes);
    }
};

fn updateGeneratedMeshes(
    commands: *Commands,
    sprites: Query(.{ sprite.Sprite, common.Transform }),
    circles: Query(.{ Circle, common.Transform }),
    rectangles: Query(.{ Rectangle, common.Transform }),
) !void {
    const state = commands.getResourceMut(types.RenderState) orelse return;
    const mesh_library = commands.getResourceMut(mesh.MeshLibrary) orelse return;
    const cache = commands.getResourceMut(GeneratedMeshCache) orelse return;
    cache.beginFrame();

    var sprite_it = sprites.iterator();
    while (sprite_it.next()) |row| {
        const spr = row.get(sprite.Sprite) orelse continue;
        const key = spr.meshKey();
        const size = spr.dimensions();
        const mesh_handle = try generatedMeshHandle(commands.allocator, &state.renderer, mesh_library, cache, key, .{
            .sprite_quad = .{ .width = size.width, .height = size.height },
        });
        try syncGeneratedMeshInstance(commands, row, key, .{
            .mesh_handle = mesh_handle,
            .color = spr.color,
            .material = spr.material orelse mesh.Material.default,
        });
    }

    var circle_it = circles.iterator();
    while (circle_it.next()) |row| {
        const circle = row.get(Circle) orelse continue;
        const key = circle.meshKey();
        const mesh_handle = try generatedMeshHandle(commands.allocator, &state.renderer, mesh_library, cache, key, .{
            .circle = .{ .radius = circle.radius, .segments = circle.segments },
        });
        try syncGeneratedMeshInstance(commands, row, key, .{
            .mesh_handle = mesh_handle,
            .shader_handle = circle.shader_handle,
            .color = circle.color,
            .material = circle.material orelse mesh.Material.default,
            .scene_material = circle.scene_material,
        });
    }

    var rectangle_it = rectangles.iterator();
    while (rectangle_it.next()) |row| {
        const rectangle = row.get(Rectangle) orelse continue;
        const key = rectangle.meshKey();
        const mesh_handle = try generatedMeshHandle(commands.allocator, &state.renderer, mesh_library, cache, key, .{
            .rectangle = .{ .width = rectangle.width, .height = rectangle.height },
        });
        try syncGeneratedMeshInstance(commands, row, key, .{
            .mesh_handle = mesh_handle,
            .shader_handle = rectangle.shader_handle,
            .color = rectangle.color,
            .material = rectangle.material orelse mesh.Material.default,
            .scene_material = rectangle.scene_material,
        });
    }
}

fn removeOrphanedGeneratedMeshInstances(
    commands: *Commands,
    orphaned_meshes: Query(.{
        GeneratedMeshInstance,
        mesh.MeshInstance,
        Without(sprite.Sprite),
        Without(Circle),
        Without(Rectangle),
        Without(text.Text),
    }),
    orphaned_text_meshes: Query(.{
        GeneratedMeshInstance,
        text.Text,
        Without(sprite.Sprite),
        Without(Circle),
        Without(Rectangle),
    }),
) !void {
    var text_it = orphaned_text_meshes.iterator();
    while (text_it.next()) |row| {
        try commands.removeComponent(row.entity_id, GeneratedMeshInstance);
    }

    var it = orphaned_meshes.iterator();
    while (it.next()) |row| {
        try commands.removeComponents(row.entity_id, .{ GeneratedMeshInstance, mesh.MeshInstance });
    }
}

fn cleanupGeneratedMeshes(commands: *Commands) !void {
    const state = commands.getResourceMut(types.RenderState) orelse return;
    const mesh_library = commands.getResourceMut(mesh.MeshLibrary) orelse return;
    const cache = commands.getResourceMut(GeneratedMeshCache) orelse return;

    var stale_keys = std.ArrayListUnmanaged(GeneratedMeshKey).empty;
    defer stale_keys.deinit(commands.allocator);

    var it = cache.map.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.last_seen_generation == cache.generation) continue;
        _ = mesh_library.destroyMesh(&state.renderer, entry.value_ptr.mesh_handle);
        try stale_keys.append(commands.allocator, entry.key_ptr.*);
    }

    for (stale_keys.items) |key| {
        _ = cache.map.remove(key);
    }
}

const BuildSpec = union(enum) {
    sprite_quad: struct { width: f32, height: f32 },
    circle: struct { radius: f32, segments: u32 },
    rectangle: struct { width: f32, height: f32 },
};

fn generatedMeshHandle(
    allocator: std.mem.Allocator,
    renderer: *backend.Renderer,
    mesh_library: *mesh.MeshLibrary,
    cache: *GeneratedMeshCache,
    key: GeneratedMeshKey,
    spec: BuildSpec,
) !mesh.MeshHandle {
    if (cache.map.getPtr(key)) |entry| {
        if (mesh_library.get(entry.mesh_handle) != null) {
            entry.last_seen_generation = cache.generation;
            return entry.mesh_handle;
        }
        _ = cache.map.remove(key);
    }

    const mesh_handle = switch (spec) {
        .sprite_quad => |quad| try buildQuadMesh(renderer, mesh_library, quad.width, quad.height),
        .circle => |circle| blk: {
            var factory = mesh.MeshFactory.init(allocator, mesh_library, renderer);
            break :blk try factory.circle(circle.radius, circle.segments);
        },
        .rectangle => |rectangle| try buildQuadMesh(renderer, mesh_library, rectangle.width, rectangle.height),
    };
    try cache.touch(key, mesh_handle);
    return mesh_handle;
}

fn buildQuadMesh(
    renderer: *backend.Renderer,
    mesh_library: *mesh.MeshLibrary,
    width: f32,
    height: f32,
) !mesh.MeshHandle {
    const half_w = width * 0.5;
    const half_h = height * 0.5;
    const vertices = [_]backend.VertexUv{
        .{ .position = .{ -half_w, -half_h }, .uv = .{ 0.0, 0.0 } },
        .{ .position = .{ half_w, -half_h }, .uv = .{ 1.0, 0.0 } },
        .{ .position = .{ half_w, half_h }, .uv = .{ 1.0, 1.0 } },
        .{ .position = .{ -half_w, half_h }, .uv = .{ 0.0, 1.0 } },
    };
    const indices = [_]u16{ 0, 1, 2, 0, 2, 3 };
    return mesh_library.addMesh(renderer, vertices[0..], indices[0..]);
}

fn syncGeneratedMeshInstance(
    commands: *Commands,
    row: anytype,
    key: GeneratedMeshKey,
    prepared: mesh.MeshInstance,
) !void {
    if (row.get(mesh.MeshInstance)) |instance| {
        instance.* = prepared;
        if (row.get(GeneratedMeshInstance)) |marker| {
            marker.key = key;
        } else {
            try commands.addComponent(row.entity_id, GeneratedMeshInstance{ .key = key });
        }
        return;
    }

    if (row.get(GeneratedMeshInstance)) |marker| {
        marker.key = key;
        try commands.addComponent(row.entity_id, prepared);
    } else {
        try commands.addComponents(row.entity_id, .{
            prepared,
            GeneratedMeshInstance{ .key = key },
        });
    }
}

fn floatBits(value: f32) u32 {
    return @as(u32, @bitCast(value));
}

test "generated mesh keys distinguish shape kinds" {
    try std.testing.expect(!std.meta.eql(GeneratedMeshKey.circle(1.0, 32), GeneratedMeshKey.rectangle(1.0, 32.0)));
    try std.testing.expectEqual(GeneratedMeshKey.circle(4.0, 48), (Circle{ .radius = 4.0, .segments = 48 }).meshKey());
    try std.testing.expectEqual(GeneratedMeshKey.rectangle(8.0, 4.0), (Rectangle{ .width = 8.0, .height = 4.0 }).meshKey());
}

const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");
const ecs = @import("ecs");
const mesh = @import("mesh.zig");
const sprite = @import("sprite.zig");
const text = @import("text.zig");
const types = @import("types.zig");
const backend = if (builtin.target.cpu.arch.isWasm())
    @import("backend_web.zig")
else
    @import("backend_native.zig");

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
const Without = ecs.system_params.Without;
