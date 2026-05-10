pub fn updateTextMeshes(
    commands: *Commands,
    default_font: ResMut(render.DefaultFont),
    font_library_opt: ResOpt(render.FontLibrary),
    texts: Query(.{ render.Text, common.Transform }),
) !void {
    const state = commands.getResourceMut(types.RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    const fallback_font = &default_font.ptr.font;
    const fallback_material = fallback_font.material orelse return;
    if (fallback_font.atlas == null) return;

    var it = texts.iterator();
    while (it.next()) |row| {
        const text = row.get(render.Text) orelse continue;
        _ = row.get(common.Transform) orelse continue;
        const font = blk: {
            if (text.font_handle) |font_handle| {
                if (font_library_opt.ptr) |font_library| {
                    if (font_library.get(font_handle)) |loaded_font| {
                        if (loaded_font.atlas != null and loaded_font.material != null) {
                            break :blk loaded_font;
                        }
                    }
                }
            }
            break :blk fallback_font;
        };
        const material = font.material orelse fallback_material;

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
    cameras_zero: Query(.{ common.Camera3d, common.Transform, render.CameraLayer(0) }),
    cameras_unlayered: Query(.{ common.Camera3d, common.Transform, Without(render.CameraLayerN) }),
    camera_groups: GroupBy(render.CameraLayerN),
    layer_cameras: ResMut(types.LayerCameras),
) !void {
    layer_cameras.ptr.clear();

    try collectLayerCameras(layer_cameras.ptr, cameras_zero, 0);
    try collectLayerCameras(layer_cameras.ptr, cameras_unlayered, 0);

    var it = camera_groups.iterator();
    while (it.next()) |group| {
        if (group.key == 0) continue;
        var rows = try group.query(.{ common.Camera3d, common.Transform });
        defer rows.deinit();
        try collectLayerCameras(layer_cameras.ptr, rows, group.key);
    }
}

fn collectLayerCameras(layer_cameras: *types.LayerCameras, query: anytype, forced_layer: i32) !void {
    var it = query.iterator();
    while (it.next()) |row| {
        const cam = row.get(common.Camera3d) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        try layer_cameras.map.put(forced_layer, .{
            .camera = cam.*,
            .view = viewMatrix(transform.*),
            .transform = transform.*,
        });
    }
}

pub fn cleanupUnusedMeshes(
    commands: *Commands,
    instances: Query(.{render.MeshInstance}),
    texts: Query(.{render.Text}),
    generated_cache_opt: ResOpt(render.GeneratedMeshCache),
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

    if (generated_cache_opt.ptr) |cache| {
        var cache_it = cache.map.iterator();
        while (cache_it.next()) |entry| {
            const handle = entry.value_ptr.mesh_handle;
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
        try commands.insertResource(types.ViewportSize{
            .width = @floatFromInt(evt.width),
            .height = @floatFromInt(evt.height),
        });
        try commands.insertResource(types.FramebufferSize{
            .width = @floatFromInt(evt.framebuffer_width),
            .height = @floatFromInt(evt.framebuffer_height),
        });
        return;
    }

    if (!commands.hasResource(types.ViewportSize)) {
        if (window_bounds_opt.ptr) |bounds| {
            try commands.insertResource(types.ViewportSize{
                .width = resolvedLogicalExtent(@floatFromInt(bounds.width), render_bounds_opt.ptr, .width),
                .height = resolvedLogicalExtent(@floatFromInt(bounds.height), render_bounds_opt.ptr, .height),
            });
        } else if (render_bounds_opt.ptr) |bounds| {
            try commands.insertResource(types.ViewportSize{
                .width = bounds.width,
                .height = bounds.height,
            });
        }
    }

    if (!commands.hasResource(types.FramebufferSize)) {
        if (render_bounds_opt.ptr) |bounds| {
            try commands.insertResource(types.FramebufferSize{
                .width = bounds.width,
                .height = bounds.height,
            });
        } else if (window_bounds_opt.ptr) |bounds| {
            try commands.insertResource(types.FramebufferSize{
                .width = @floatFromInt(bounds.width),
                .height = @floatFromInt(bounds.height),
            });
        }
    }
}

const LogicalAxis = enum { width, height };

fn resolvedLogicalExtent(candidate: f32, framebuffer: ?*const common.RenderBounds, axis: LogicalAxis) f32 {
    if (candidate > 1.0) return candidate;
    if (framebuffer) |bounds| {
        const extent = switch (axis) {
            .width => bounds.width,
            .height => bounds.height,
        };
        if (extent > 1.0) return extent;
    }
    return @max(1.0, candidate);
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
const render = @import("root.zig");
const types = @import("types.zig");

const Commands = ecs.Commands;
const system_params = ecs.system_params;
const GroupBy = system_params.GroupBy;
const Query = system_params.Query;
const ResMut = system_params.ResMut;
const ResOpt = system_params.ResOpt;
const Without = system_params.Without;
const events = ecs.events;
const EventReader = events.EventReader;
