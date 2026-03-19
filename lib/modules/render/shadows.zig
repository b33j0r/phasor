pub const ShadowTechnique = enum(u32) {
    none = 0,
    directional_shadow_map = 1,
};

pub const ShadowSettings = struct {
    technique: ShadowTechnique = .none,
    map_resolution: u32 = 1536,
    map_slot: u32 = 61,
    strength: f32 = 1.0,
    depth_bias: f32 = 0.00008,
    normal_bias: f32 = 0.00045,
    max_distance: f32 = 42.0,
    frustum_padding: f32 = 5.0,
    depth_padding: f32 = 36.0,
    caster_range: f32 = 24.0,
    stabilize: bool = true,
};

pub const ShadowFrameData = struct {
    enabled: bool = false,
    map_size: render.Size = .{ .width = 1, .height = 1 },
    map_slot: u32 = 0,
    light_view_proj: common.Mat4 = common.Mat4.identity(),
    uniforms: render.ShadowUniforms = .{},
};

pub fn evaluateShadowFrame(
    settings: ShadowSettings,
    extracted_lighting: *const types.ExtractedSceneLighting,
    camera: types.LayerCamera,
    viewport_size: render.Size,
    surface_size: render.Size,
) ShadowFrameData {
    if (settings.technique == .none) return .{};
    const to_light = firstDirectionalLightDirection(extracted_lighting) orelse return .{};
    const shadow_size = resolvedMapSize(settings.map_resolution, surface_size);
    const corners = cameraFrustumSliceCorners(camera, viewport_size, settings.max_distance) orelse return .{};

    var focus = common.Vec3{};
    for (corners) |corner| focus = focus.add(corner);
    focus = focus.scale(1.0 / 8.0);

    var radius: f32 = 1.0;
    for (corners) |corner| {
        radius = @max(radius, corner.sub(focus).length());
    }

    const eye_distance = radius + settings.depth_padding + settings.max_distance * 0.25;
    const eye = focus.add(to_light.scale(eye_distance));
    const up_hint = if (@abs(to_light.y) > 0.95)
        common.Vec3{ .x = 0.0, .y = 0.0, .z = 1.0 }
    else
        common.Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
    const view = lookAt(eye, focus, up_hint);

    var bounds = Bounds.init();
    for (corners) |corner| {
        bounds.include(view.transformVec3(corner));
        if (settings.caster_range > 0.0) {
            bounds.include(view.transformVec3(corner.add(to_light.scale(settings.caster_range))));
        }
    }
    if (!bounds.valid) return .{};

    bounds.min.x -= settings.frustum_padding;
    bounds.max.x += settings.frustum_padding;
    bounds.min.y -= settings.frustum_padding;
    bounds.max.y += settings.frustum_padding;
    bounds.min.z -= settings.depth_padding;
    bounds.max.z += settings.frustum_padding;

    var center_ls = bounds.center();
    const width = @max(bounds.max.x - bounds.min.x, 2.0);
    const height = @max(bounds.max.y - bounds.min.y, 2.0);
    if (settings.stabilize) {
        const texel_x = width / @as(f32, @floatFromInt(@max(shadow_size.width, 1)));
        const texel_y = height / @as(f32, @floatFromInt(@max(shadow_size.height, 1)));
        if (texel_x > 0.0) center_ls.x = snapToTexel(center_ls.x, texel_x);
        if (texel_y > 0.0) center_ls.y = snapToTexel(center_ls.y, texel_y);
    }

    const near_plane = @max(0.1, -bounds.max.z);
    const far_plane = @max(near_plane + 1.0, -bounds.min.z);
    const proj = common.Mat4.orthographic(
        center_ls.x - width * 0.5,
        center_ls.x + width * 0.5,
        center_ls.y - height * 0.5,
        center_ls.y + height * 0.5,
        near_plane,
        far_plane,
    );
    const light_view_proj = common.Mat4.mul(proj, view);

    var uniforms = render.ShadowUniforms{};
    uniforms.light_view_proj = light_view_proj;
    uniforms.params0 = .{
        1.0 / @as(f32, @floatFromInt(@max(shadow_size.width, 1))),
        1.0 / @as(f32, @floatFromInt(@max(shadow_size.height, 1))),
        settings.depth_bias,
        settings.normal_bias,
    };
    uniforms.params1 = .{
        settings.strength,
        1.0,
        @floatFromInt(@intFromEnum(settings.technique)),
        0.0,
    };

    return .{
        .enabled = true,
        .map_size = shadow_size,
        .map_slot = settings.map_slot,
        .light_view_proj = light_view_proj,
        .uniforms = uniforms,
    };
}

fn resolvedMapSize(map_resolution: u32, surface_size: render.Size) render.Size {
    const size = @max(map_resolution, 1);
    return .{
        .width = if (map_resolution == 0) @max(surface_size.width, 1) else size,
        .height = if (map_resolution == 0) @max(surface_size.height, 1) else size,
    };
}

const Bounds = struct {
    min: common.Vec3 = .{},
    max: common.Vec3 = .{},
    valid: bool = false,

    fn init() Bounds {
        return .{};
    }

    fn include(self: *Bounds, point: common.Vec3) void {
        if (!self.valid) {
            self.min = point;
            self.max = point;
            self.valid = true;
            return;
        }
        self.min.x = @min(self.min.x, point.x);
        self.min.y = @min(self.min.y, point.y);
        self.min.z = @min(self.min.z, point.z);
        self.max.x = @max(self.max.x, point.x);
        self.max.y = @max(self.max.y, point.y);
        self.max.z = @max(self.max.z, point.z);
    }

    fn center(self: Bounds) common.Vec3 {
        return .{
            .x = (self.min.x + self.max.x) * 0.5,
            .y = (self.min.y + self.max.y) * 0.5,
            .z = (self.min.z + self.max.z) * 0.5,
        };
    }
};

fn cameraFrustumSliceCorners(
    layer_camera: types.LayerCamera,
    viewport_size: render.Size,
    max_distance: f32,
) ?[8]common.Vec3 {
    const transform = layer_camera.transform;
    const origin = transform.translation;
    const forward = transform.rotation.rotateVec3(.{ .x = 0.0, .y = 0.0, .z = -1.0 }).normalize();
    const right = transform.rotation.rotateVec3(.{ .x = 1.0, .y = 0.0, .z = 0.0 }).normalize();
    const up = transform.rotation.rotateVec3(.{ .x = 0.0, .y = 1.0, .z = 0.0 }).normalize();
    if (forward.length_squared() <= 0.00001 or right.length_squared() <= 0.00001 or up.length_squared() <= 0.00001) return null;

    const width = @as(f32, @floatFromInt(@max(viewport_size.width, 1)));
    const height = @as(f32, @floatFromInt(@max(viewport_size.height, 1)));
    const aspect = width / @max(height, 1.0);

    return switch (layer_camera.camera) {
        .Perspective => |persp| buildPerspectiveSlice(origin, forward, right, up, aspect, persp, max_distance),
        .Orthographic => |ortho| buildOrthographicSlice(origin, forward, right, up, ortho, max_distance),
        .Viewport => null,
    };
}

fn buildPerspectiveSlice(
    origin: common.Vec3,
    forward: common.Vec3,
    right: common.Vec3,
    up: common.Vec3,
    aspect: f32,
    persp: @FieldType(common.Camera3d, "Perspective"),
    max_distance: f32,
) ?[8]common.Vec3 {
    const zoom = if (persp.zoom <= 0.0) 1.0 else persp.zoom;
    const fov = persp.fov / zoom;
    const near_plane = @max(persp.near, 0.05);
    const far_plane = @max(near_plane + 0.5, @min(persp.far, @max(max_distance, near_plane + 0.5)));
    if (far_plane <= near_plane) return null;

    const tan_half = @tan(fov * 0.5);
    const near_half_h = tan_half * near_plane;
    const near_half_w = near_half_h * aspect;
    const far_half_h = tan_half * far_plane;
    const far_half_w = far_half_h * aspect;
    const near_center = origin.add(forward.scale(near_plane));
    const far_center = origin.add(forward.scale(far_plane));

    return [8]common.Vec3{
        near_center.add(right.scale(-near_half_w)).add(up.scale(-near_half_h)),
        near_center.add(right.scale(near_half_w)).add(up.scale(-near_half_h)),
        near_center.add(right.scale(near_half_w)).add(up.scale(near_half_h)),
        near_center.add(right.scale(-near_half_w)).add(up.scale(near_half_h)),
        far_center.add(right.scale(-far_half_w)).add(up.scale(-far_half_h)),
        far_center.add(right.scale(far_half_w)).add(up.scale(-far_half_h)),
        far_center.add(right.scale(far_half_w)).add(up.scale(far_half_h)),
        far_center.add(right.scale(-far_half_w)).add(up.scale(far_half_h)),
    };
}

fn buildOrthographicSlice(
    origin: common.Vec3,
    forward: common.Vec3,
    right: common.Vec3,
    up: common.Vec3,
    ortho: @FieldType(common.Camera3d, "Orthographic"),
    max_distance: f32,
) ?[8]common.Vec3 {
    const zoom = if (ortho.zoom <= 0.0) 1.0 else ortho.zoom;
    const near_plane = ortho.near;
    const far_plane = @max(near_plane + 0.5, @min(ortho.far, @max(max_distance, near_plane + 0.5)));
    if (far_plane <= near_plane) return null;

    const left = ortho.left / zoom;
    const right_extent = ortho.right / zoom;
    const bottom = ortho.bottom / zoom;
    const top = ortho.top / zoom;
    const near_center = origin.add(forward.scale(near_plane));
    const far_center = origin.add(forward.scale(far_plane));

    return [8]common.Vec3{
        near_center.add(right.scale(left)).add(up.scale(bottom)),
        near_center.add(right.scale(right_extent)).add(up.scale(bottom)),
        near_center.add(right.scale(right_extent)).add(up.scale(top)),
        near_center.add(right.scale(left)).add(up.scale(top)),
        far_center.add(right.scale(left)).add(up.scale(bottom)),
        far_center.add(right.scale(right_extent)).add(up.scale(bottom)),
        far_center.add(right.scale(right_extent)).add(up.scale(top)),
        far_center.add(right.scale(left)).add(up.scale(top)),
    };
}

fn snapToTexel(value: f32, texel_size: f32) f32 {
    return @floor(value / texel_size) * texel_size;
}

fn firstDirectionalLightDirection(extracted: *const types.ExtractedSceneLighting) ?common.Vec3 {
    var i: usize = 0;
    while (i < extracted.light_count and i < render.max_scene_lights) : (i += 1) {
        const light = extracted.lights[i];
        const kind: u32 = @intFromFloat(light.direction_kind[3]);
        if (kind != @intFromEnum(render.SceneLightKind.directional)) continue;
        const to_light = (common.Vec3{
            .x = -light.direction_kind[0],
            .y = -light.direction_kind[1],
            .z = -light.direction_kind[2],
        }).normalize();
        if (to_light.length_squared() > 0.0001) return to_light;
    }
    return null;
}

fn lookAt(eye: common.Vec3, target: common.Vec3, up_hint: common.Vec3) common.Mat4 {
    const forward = target.sub(eye).normalize();
    if (forward.length_squared() <= 0.00001) return common.Mat4.identity();

    var right = forward.cross(up_hint);
    if (right.length_squared() <= 0.00001) {
        right = forward.cross(.{ .x = 1.0, .y = 0.0, .z = 0.0 });
    }
    right = right.normalize();
    const up = right.cross(forward).normalize();

    return .{
        .m = .{
            .{ right.x, up.x, -forward.x, 0.0 },
            .{ right.y, up.y, -forward.y, 0.0 },
            .{ right.z, up.z, -forward.z, 0.0 },
            .{ -right.dot(eye), -up.dot(eye), forward.dot(eye), 1.0 },
        },
    };
}

const common = @import("common");
const render = @import("render");
const types = @import("types.zig");
