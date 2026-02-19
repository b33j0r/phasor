pub const PanoramaSky = struct {
    material: render.Material,
    size: f32 = 220.0,
    follow_camera: bool = true,
    face_segments: u16 = 24,
};

const PanoramaAnchor = struct {
    offset: common.Vec3,
    follow_camera: bool,
};

const PanoramaBuilt = struct {};

const Face = enum {
    front,
    right,
    back,
    left,
    top,
    bottom,
};

pub fn install(app: *AppCommands, _: *Commands) !void {
    try app.addSystem("Update", buildPanoramaSkies);
    try app.addSystem("Update", updatePanoramaSkies);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(buildPanoramaSkies);
    app.removeSystem(updatePanoramaSkies);
}

fn buildPanoramaSkies(
    commands: *Commands,
    cameras: Query(.{common.Camera3d}),
    skies: Query(.{ common.Transform, PanoramaSky, ecs.system_params.Without(PanoramaBuilt) }),
) !void {
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    const state = commands.getResourceMut(RenderState) orelse return;

    var it = skies.iterator();
    while (it.next()) |row| {
        const transform = row.get(common.Transform) orelse continue;
        const sky = row.get(PanoramaSky) orelse continue;
        const size = clampSkySizeToCameraFar(sky.size, cameras);
        const segments = clampFaceSegments(sky.face_segments);
        const center = transform.translation;

        try spawnPanoramaFace(commands, mesh_library, &state.renderer, sky.material, center, size, .front, sky.follow_camera, segments);
        try spawnPanoramaFace(commands, mesh_library, &state.renderer, sky.material, center, size, .right, sky.follow_camera, segments);
        try spawnPanoramaFace(commands, mesh_library, &state.renderer, sky.material, center, size, .back, sky.follow_camera, segments);
        try spawnPanoramaFace(commands, mesh_library, &state.renderer, sky.material, center, size, .left, sky.follow_camera, segments);
        try spawnPanoramaFace(commands, mesh_library, &state.renderer, sky.material, center, size, .top, sky.follow_camera, segments);
        try spawnPanoramaFace(commands, mesh_library, &state.renderer, sky.material, center, size, .bottom, sky.follow_camera, segments);
        try commands.addComponent(row.entity_id, PanoramaBuilt{});
    }
}

fn clampSkySizeToCameraFar(requested_size: f32, cameras: Query(.{common.Camera3d})) f32 {
    if (requested_size <= 0.0) return 32.0;

    var min_far: ?f32 = null;
    var it = cameras.iterator();
    while (it.next()) |row| {
        const camera = row.get(common.Camera3d) orelse continue;
        const far_dist: f32 = switch (camera.*) {
            .Perspective => |persp| persp.far,
            .Orthographic => |ortho| @abs(ortho.far - ortho.near),
            .Viewport => continue,
        };
        if (far_dist <= 0.0) continue;
        min_far = if (min_far) |existing| @min(existing, far_dist) else far_dist;
    }

    if (min_far) |far_dist| {
        // Keep panorama cube corners comfortably inside far clip.
        const max_half = far_dist * 0.45;
        const clamped_half = @min(requested_size * 0.5, max_half);
        return @max(8.0, clamped_half * 2.0);
    }

    return requested_size;
}

fn updatePanoramaSkies(
    cameras: Query(.{ common.Transform, common.Camera3d }),
    faces: Query(.{ common.Transform, PanoramaAnchor }),
) void {
    var camera_center: ?common.Vec3 = null;
    var camera_it = cameras.iterator();
    while (camera_it.next()) |row| {
        const transform = row.get(common.Transform) orelse continue;
        const camera = row.get(common.Camera3d) orelse continue;
        switch (camera.*) {
            .Viewport => continue,
            else => {
                camera_center = transform.translation;
                break;
            },
        }
    }
    const center = camera_center orelse return;

    var face_it = faces.iterator();
    while (face_it.next()) |row| {
        const transform = row.get(common.Transform) orelse continue;
        const anchor = row.get(PanoramaAnchor) orelse continue;
        if (!anchor.follow_camera) continue;
        transform.translation = center.add(anchor.offset);
    }
}

fn spawnPanoramaFace(
    commands: *Commands,
    mesh_library: *render.MeshLibrary,
    renderer_state: *render.Renderer,
    material: render.Material,
    center: common.Vec3,
    size: f32,
    face: Face,
    follow_camera: bool,
    segments: u16,
) !void {
    const spec = faceSpec(face, size);
    const mesh = try createPanoramaFaceMesh(commands.allocator, mesh_library, renderer_state, size, spec, segments);
    _ = try commands.createEntity(.{
        common.Transform{
            .translation = center.add(spec.offset),
            .rotation = spec.rotation,
            .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        },
        render.MeshInstance{
            .mesh_handle = mesh,
            .material = material,
            .color = common.Color.WHITE,
        },
        PanoramaAnchor{
            .offset = spec.offset,
            .follow_camera = follow_camera,
        },
    });
}

const FaceSpec = struct {
    offset: common.Vec3,
    rotation: common.Quat,
};

fn faceSpec(face: Face, size: f32) FaceSpec {
    const half = size * 0.5;
    return switch (face) {
        .front => .{
            .offset = .{ .x = 0.0, .y = 0.0, .z = half },
            .rotation = quatFromEuler(0.0, std.math.pi, 0.0),
        },
        .right => .{
            .offset = .{ .x = half, .y = 0.0, .z = 0.0 },
            .rotation = quatFromEuler(0.0, -std.math.pi * 0.5, 0.0),
        },
        .back => .{
            .offset = .{ .x = 0.0, .y = 0.0, .z = -half },
            .rotation = quatFromEuler(0.0, 0.0, 0.0),
        },
        .left => .{
            .offset = .{ .x = -half, .y = 0.0, .z = 0.0 },
            .rotation = quatFromEuler(0.0, std.math.pi * 0.5, 0.0),
        },
        .top => .{
            .offset = .{ .x = 0.0, .y = half, .z = 0.0 },
            .rotation = quatFromEuler(std.math.pi * 0.5, 0.0, 0.0),
        },
        .bottom => .{
            .offset = .{ .x = 0.0, .y = -half, .z = 0.0 },
            .rotation = quatFromEuler(-std.math.pi * 0.5, 0.0, 0.0),
        },
    };
}

fn directionForFacePoint(spec: FaceSpec, x: f32, y: f32) common.Vec3 {
    const local = common.Vec3{ .x = x, .y = y, .z = 0.0 };
    const rotated = spec.rotation.rotateVec3(local);
    return rotated.add(spec.offset).normalize();
}

fn directionToEquirectUv(direction: common.Vec3) [2]f32 {
    const u = 0.5 + (std.math.atan2(direction.x, direction.z) / (2.0 * std.math.pi));
    const v = 0.5 - (std.math.asin(std.math.clamp(direction.y, -1.0, 1.0)) / std.math.pi);
    return .{ u, v };
}

fn unwrapSeam(uvs: *[4][2]f32) void {
    var min_u = uvs.*[0][0];
    var max_u = uvs.*[0][0];
    for (uvs.*[1..]) |uv| {
        min_u = @min(min_u, uv[0]);
        max_u = @max(max_u, uv[0]);
    }
    if (max_u - min_u <= 0.5) return;
    for (&uvs.*) |*uv| {
        if (uv[0] < 0.5) uv[0] += 1.0;
    }
}

fn clampFaceSegments(segments: u16) u16 {
    return @max(@as(u16, 1), @min(segments, 128));
}

fn createPanoramaFaceMesh(
    allocator: std.mem.Allocator,
    mesh_library: *render.MeshLibrary,
    renderer_state: *render.Renderer,
    size: f32,
    spec: FaceSpec,
    segments: u16,
) !render.MeshHandle {
    const half = size * 0.5;
    const seg_count: usize = @intCast(segments);

    var vertices: std.ArrayListUnmanaged(render.VertexUv) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayListUnmanaged(u16) = .empty;
    defer indices.deinit(allocator);

    try vertices.ensureTotalCapacity(allocator, seg_count * seg_count * 4);
    try indices.ensureTotalCapacity(allocator, seg_count * seg_count * 6);

    const inv_segments: f32 = 1.0 / @as(f32, @floatFromInt(segments));

    var y: usize = 0;
    while (y < seg_count) : (y += 1) {
        const t0 = @as(f32, @floatFromInt(y)) * inv_segments;
        const t1 = @as(f32, @floatFromInt(y + 1)) * inv_segments;

        var x: usize = 0;
        while (x < seg_count) : (x += 1) {
            const s0 = @as(f32, @floatFromInt(x)) * inv_segments;
            const s1 = @as(f32, @floatFromInt(x + 1)) * inv_segments;

            const x0 = std.math.lerp(-half, half, s0);
            const x1 = std.math.lerp(-half, half, s1);
            const y0 = std.math.lerp(-half, half, t0);
            const y1 = std.math.lerp(-half, half, t1);

            var uvs = [4][2]f32{
                directionToEquirectUv(directionForFacePoint(spec, x0, y0)),
                directionToEquirectUv(directionForFacePoint(spec, x1, y0)),
                directionToEquirectUv(directionForFacePoint(spec, x1, y1)),
                directionToEquirectUv(directionForFacePoint(spec, x0, y1)),
            };
            unwrapSeam(&uvs);

            const base = vertices.items.len;
            if (base + 3 > std.math.maxInt(u16)) return error.TooManySkyVertices;
            const idx0: u16 = @intCast(base);
            const idx1: u16 = @intCast(base + 1);
            const idx2: u16 = @intCast(base + 2);
            const idx3: u16 = @intCast(base + 3);

            try vertices.append(allocator, .{ .position = .{ x0, y0 }, .uv = uvs[0] });
            try vertices.append(allocator, .{ .position = .{ x1, y0 }, .uv = uvs[1] });
            try vertices.append(allocator, .{ .position = .{ x1, y1 }, .uv = uvs[2] });
            try vertices.append(allocator, .{ .position = .{ x0, y1 }, .uv = uvs[3] });

            try indices.append(allocator, idx0);
            try indices.append(allocator, idx1);
            try indices.append(allocator, idx2);
            try indices.append(allocator, idx2);
            try indices.append(allocator, idx3);
            try indices.append(allocator, idx0);
        }
    }

    return mesh_library.addMesh(renderer_state, vertices.items, indices.items);
}

fn quatFromEuler(pitch: f32, yaw: f32, roll: f32) common.Quat {
    const qx = common.Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, pitch);
    const qy = common.Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, yaw);
    const qz = common.Quat.fromAxisAngle(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, roll);
    return qy.mul(qx).mul(qz).normalize();
}

const std = @import("std");
const common = @import("common");
const ecs = @import("ecs");
const render = @import("render");

const RenderState = @import("RenderModule.zig").RenderState;

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
