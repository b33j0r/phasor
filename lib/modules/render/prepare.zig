pub fn updateSpriteMeshes(commands: *Commands, sprites: Query(.{ render.Sprite, common.Transform })) !void {
    const state = commands.getResourceMut(types.RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    const sprite_cache = commands.getResourceMut(types.SpriteMeshCache) orelse return;

    var it = sprites.iterator();
    while (it.next()) |row| {
        const sprite = row.get(render.Sprite) orelse continue;
        const size_hash = render.spriteSizeHash(sprite.*);
        if (sprite.mesh_handle.isValid() and sprite.size_hash == size_hash) {
            if (row.get(render.MeshInstance)) |instance| {
                instance.mesh_handle = sprite.mesh_handle;
                instance.color = sprite.color;
            } else {
                try commands.addComponent(row.entity_id, render.MeshInstance{
                    .mesh_handle = sprite.mesh_handle,
                    .color = sprite.color,
                });
            }
            continue;
        }

        var width: f32 = 1.0;
        var height: f32 = 1.0;
        switch (sprite.size_mode) {
            .Auto => {
                if (sprite.source_size) |size| {
                    width = @floatFromInt(size.width);
                    height = @floatFromInt(size.height);
                }
            },
            .Manual => |m| {
                width = m.width;
                height = m.height;
            },
        }

        const half_w = width * 0.5;
        const half_h = height * 0.5;
        const vertices = [_]render.VertexUv{
            .{ .position = .{ -half_w, -half_h }, .uv = .{ 0.0, 0.0 } },
            .{ .position = .{ half_w, -half_h }, .uv = .{ 1.0, 0.0 } },
            .{ .position = .{ half_w, half_h }, .uv = .{ 1.0, 1.0 } },
            .{ .position = .{ -half_w, half_h }, .uv = .{ 0.0, 1.0 } },
        };
        const indices = [_]u16{ 0, 1, 2, 0, 2, 3 };

        var mesh_handle: render.MeshHandle = render.MeshHandle.invalid();
        if (sprite_cache.map.get(size_hash)) |cached| {
            if (mesh_library.get(cached) != null) {
                mesh_handle = cached;
            } else {
                _ = sprite_cache.map.remove(size_hash);
            }
        }

        if (!mesh_handle.isValid()) {
            mesh_handle = try mesh_library.addMesh(&state.renderer, vertices[0..], indices[0..]);
            try sprite_cache.map.put(size_hash, mesh_handle);
        }

        sprite.mesh_handle = mesh_handle;
        sprite.size_hash = size_hash;

        if (row.get(render.MeshInstance)) |instance| {
            instance.mesh_handle = mesh_handle;
            instance.color = sprite.color;
        } else {
            try commands.addComponent(row.entity_id, render.MeshInstance{
                .mesh_handle = mesh_handle,
                .color = sprite.color,
            });
        }
    }
}

pub fn updateTextMeshes(
    commands: *Commands,
    default_font: ResMut(render.DefaultFont),
    texts: Query(.{ render.Text, common.Transform }),
) !void {
    const state = commands.getResourceMut(types.RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    const font = &default_font.ptr.font;
    const material = font.material orelse return;
    if (font.atlas == null) return;

    var it = texts.iterator();
    while (it.next()) |row| {
        const text = row.get(render.Text) orelse continue;
        _ = row.get(common.Transform) orelse continue;

        const layout_hash = render.textLayoutHash(text.*);
        if (text.content.len == 0) {
            if (text.mesh_handle.isValid()) {
                _ = mesh_library.destroyMesh(&state.renderer, text.mesh_handle);
                text.mesh_handle = render.MeshHandle.invalid();
            }
            text.layout_hash = layout_hash;
            if (row.get(render.MeshInstance)) |instance| {
                instance.mesh_handle = render.MeshHandle.invalid();
            }
            continue;
        }
        if (!text.mesh_handle.isValid() or text.layout_hash != layout_hash) {
            var mesh_data = render.buildTextMesh(commands.allocator, font, text.*) catch |err| {
                if (err == error.EmptyText) {
                    text.layout_hash = layout_hash;
                    if (row.get(render.MeshInstance)) |instance| {
                        instance.mesh_handle = render.MeshHandle.invalid();
                    }
                    continue;
                }
                return err;
            };
            defer mesh_data.deinit(commands.allocator);

            if (text.mesh_handle.isValid()) {
                const updated = try mesh_library.updateMesh(&state.renderer, text.mesh_handle, mesh_data.vertices, mesh_data.indices);
                if (!updated) {
                    text.mesh_handle = render.MeshHandle.invalid();
                }
            }

            if (!text.mesh_handle.isValid()) {
                const mesh_handle = try mesh_library.addMesh(&state.renderer, mesh_data.vertices, mesh_data.indices);
                text.mesh_handle = mesh_handle;
            }

            text.layout_hash = layout_hash;
        }

        if (row.get(render.MeshInstance)) |instance| {
            instance.mesh_handle = text.mesh_handle;
            instance.color = text.color;
            instance.material = render.Material.withBackend(material);
        } else {
            try commands.addComponent(row.entity_id, render.MeshInstance{
                .mesh_handle = text.mesh_handle,
                .color = text.color,
                .material = render.Material.withBackend(material),
            });
        }
    }
}

pub fn updateLayerCameras(
    cameras: Query(.{ common.Camera3d, common.Transform }),
    layer_cameras: ResMut(types.LayerCameras),
) !void {
    layer_cameras.ptr.clear();

    var it = cameras.iterator();
    while (it.next()) |row| {
        const cam = row.get(common.Camera3d) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        const layer = types.cameraLayerKeyForRow(row);
        try layer_cameras.ptr.map.put(layer, .{
            .camera = cam.*,
            .view = viewMatrix(transform.*),
        });
    }
}

pub fn cleanupUnusedMeshes(
    commands: *Commands,
    instances: Query(.{render.MeshInstance}),
    texts: Query(.{render.Text}),
    sprite_cache_opt: ResOpt(types.SpriteMeshCache),
) !void {
    const state = commands.getResourceMut(types.RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;

    const slot_count = mesh_library.slots.items.len;
    if (slot_count == 0) return;

    var used = try std.DynamicBitSetUnmanaged.initEmpty(commands.allocator, slot_count);
    defer used.deinit(commands.allocator);

    var it = instances.iterator();
    while (it.next()) |row| {
        const instance = row.get(render.MeshInstance) orelse continue;
        if (!instance.mesh_handle.isValid()) continue;
        const index: usize = @intCast(instance.mesh_handle.index);
        if (index >= slot_count) continue;
        const slot = &mesh_library.slots.items[index];
        if (!slot.alive or slot.generation != instance.mesh_handle.generation) continue;
        used.set(index);
    }

    var text_it = texts.iterator();
    while (text_it.next()) |row| {
        const text = row.get(render.Text) orelse continue;
        if (!text.mesh_handle.isValid()) continue;
        const index: usize = @intCast(text.mesh_handle.index);
        if (index >= slot_count) continue;
        const slot = &mesh_library.slots.items[index];
        if (!slot.alive or slot.generation != text.mesh_handle.generation) continue;
        used.set(index);
    }

    if (sprite_cache_opt.ptr) |cache| {
        var cache_it = cache.map.iterator();
        while (cache_it.next()) |entry| {
            const handle = entry.value_ptr.*;
            if (!handle.isValid()) continue;
            const index: usize = @intCast(handle.index);
            if (index >= slot_count) continue;
            const slot = &mesh_library.slots.items[index];
            if (!slot.alive or slot.generation != handle.generation) continue;
            used.set(index);
        }
    }

    for (mesh_library.slots.items, 0..) |*slot, index| {
        if (!slot.alive) continue;
        if (used.isSet(index)) continue;
        _ = mesh_library.destroyMesh(&state.renderer, .{
            .index = @intCast(index),
            .generation = slot.generation,
        });
    }
}

pub fn handleViewportResize(
    commands: *Commands,
    reader: EventReader(common.WindowResized),
    window_bounds_opt: ResOpt(common.WindowBounds),
    render_bounds_opt: ResOpt(common.RenderBounds),
) !void {
    var latest: ?common.WindowResized = null;
    while (reader.tryRecv()) |evt| {
        latest = evt;
    }

    if (latest) |evt| {
        if (render_bounds_opt.ptr) |bounds| {
            try commands.insertResource(types.ViewportSize{
                .width = bounds.width,
                .height = bounds.height,
            });
            return;
        }
        try commands.insertResource(types.ViewportSize{
            .width = @floatFromInt(evt.width),
            .height = @floatFromInt(evt.height),
        });
        return;
    }

    if (!commands.hasResource(types.ViewportSize)) {
        if (window_bounds_opt.ptr) |bounds| {
            try commands.insertResource(types.ViewportSize{
                .width = @floatFromInt(bounds.width),
                .height = @floatFromInt(bounds.height),
            });
        } else if (render_bounds_opt.ptr) |bounds| {
            try commands.insertResource(types.ViewportSize{ .width = bounds.width, .height = bounds.height });
        }
    }
}

fn viewMatrix(transform: common.Transform) common.Mat4 {
    const inv_scale = common.Vec3{
        .x = if (transform.scale.x != 0.0) 1.0 / transform.scale.x else 0.0,
        .y = if (transform.scale.y != 0.0) 1.0 / transform.scale.y else 0.0,
        .z = if (transform.scale.z != 0.0) 1.0 / transform.scale.z else 0.0,
    };
    const scale_mat = common.Mat4.scaleVec3(inv_scale);
    const rot_mat = common.Mat4.fromQuaternion(transform.rotation.inverse());
    const trans_mat = common.Mat4.translateVec3(transform.translation.scale(-1.0));
    return common.Mat4.mul(common.Mat4.mul(scale_mat, rot_mat), trans_mat);
}

const std = @import("std");
const common = @import("common");
const ecs = @import("ecs");
const render = @import("render");
const types = @import("types.zig");

const Commands = ecs.Commands;
const system_params = ecs.system_params;
const Query = system_params.Query;
const ResMut = system_params.ResMut;
const ResOpt = system_params.ResOpt;
const events = ecs.events;
const EventReader = events.EventReader;
