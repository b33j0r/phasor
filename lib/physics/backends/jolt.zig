const std = @import("std");
const ecs = @import("ecs");
const common = @import("common");
const components = @import("../components.zig");
const resources = @import("../resources.zig");
const queries = @import("../queries.zig");
const bake = @import("../bake/root.zig");

pub const State = struct {
    allocator: std.mem.Allocator,
    native: *NativeWorld,
    bodies: std.AutoArrayHashMapUnmanaged(ecs.Entity.Id, BodyRecord) = .empty,
    characters: std.AutoArrayHashMapUnmanaged(ecs.Entity.Id, CharacterRecord) = .empty,

    const BodyRecord = struct {
        body_id: u32,
    };

    const CharacterRecord = struct {
        character_id: u32,
    };

    pub fn init(allocator: std.mem.Allocator, config: resources.Config) !State {
        var native_ptr: ?*NativeWorld = null;
        var world_config = PjWorldConfig{
            .gravity = vec3ToArray(config.gravity),
            .max_bodies = 65536,
            .max_body_pairs = 65536,
            .max_contact_constraints = 10240,
            .temp_allocator_bytes = 10 * 1024 * 1024,
            .max_jobs = 0,
            .max_barriers = 0,
        };
        if (!pj_world_create(&world_config, &native_ptr)) {
            return error.BackendUnavailable;
        }
        return .{
            .allocator = allocator,
            .native = native_ptr.?,
        };
    }

    pub fn deinit(self: *State) void {
        for (self.bodies.values()) |record| {
            _ = pj_body_remove_destroy(self.native, record.body_id);
        }
        for (self.characters.values()) |record| {
            _ = pj_character_remove_destroy(self.native, record.character_id);
        }
        self.bodies.deinit(self.allocator);
        self.characters.deinit(self.allocator);
        pj_world_destroy(self.native);
        self.* = undefined;
    }

    pub fn syncIn(self: *State, commands: *ecs.Commands, config: resources.Config, step_state: *resources.StepState) void {
        step_state.steps_last_frame = 0;
        step_state.alpha = 0.0;

        var seen: std.AutoHashMapUnmanaged(ecs.Entity.Id, void) = .empty;
        defer seen.deinit(self.allocator);
        var seen_characters: std.AutoHashMapUnmanaged(ecs.Entity.Id, void) = .empty;
        defer seen_characters.deinit(self.allocator);

        var result = commands.query(.{
            common.Transform,
            components.Body,
            components.Collider,
            ecs.system_params.Without(components.PhysicsDisabled),
        }) catch return;
        defer result.deinit();

        var it = result.iterator();
        while (it.next()) |row| {
            seen.put(self.allocator, row.entity_id, {}) catch continue;

            const transform = row.get(common.Transform) orelse continue;
            const body = row.get(components.Body) orelse continue;
            const collider = row.get(components.Collider) orelse continue;
            const velocity = row.get(components.Velocity);
            const mass = row.get(components.MassProperties);
            const lock_axes = row.get(components.LockAxes);
            const kinematic_target = row.get(components.KinematicTarget);
            const dirty = row.get(components.PhysicsDirty) != null;
            const existing = self.bodies.get(row.entity_id);

            if (dirty and existing != null) {
                self.destroyBody(row.entity_id, existing.?.body_id);
            }

            const record = self.bodies.get(row.entity_id);
            if (record == null) {
                const created = self.createBody(commands, row.entity_id, transform.*, body.*, collider.*, velocity, mass, lock_axes, kinematic_target) orelse continue;
                self.bodies.put(self.allocator, row.entity_id, .{ .body_id = created }) catch {
                    _ = pj_body_remove_destroy(self.native, created);
                    continue;
                };

                if (row.get(components.BodyHandle)) |handle| {
                    handle.value = created;
                } else {
                    commands.addComponent(row.entity_id, components.BodyHandle{ .value = created }) catch {};
                }
                if (dirty) {
                    commands.removeComponent(row.entity_id, components.PhysicsDirty) catch {};
                }
                continue;
            }

            const body_id = record.?.body_id;
            switch (body.kind) {
                .Static => {
                    _ = pj_body_set_transform(self.native, body_id, &vec3ToArray(transform.translation), &quatToArray(transform.rotation), false);
                },
                .Kinematic => {
                    const target = if (kinematic_target) |value| value.transform else transform.*;
                    _ = pj_body_move_kinematic(self.native, body_id, &vec3ToArray(target.translation), &quatToArray(target.rotation), config.fixed_dt);
                },
                .Dynamic => {
                    if (velocity) |value| {
                        _ = pj_body_set_velocities(self.native, body_id, &vec3ToArray(value.linear), &vec3ToArray(value.angular));
                    }
                },
            }
        }

        var stale_index: usize = 0;
        while (stale_index < self.bodies.count()) {
            const entity_id = self.bodies.keys()[stale_index];
            if (seen.contains(entity_id)) {
                stale_index += 1;
                continue;
            }

            const body_id = self.bodies.values()[stale_index].body_id;
            _ = pj_body_remove_destroy(self.native, body_id);
            _ = self.bodies.swapRemoveAt(stale_index);
        }

        var character_result = commands.query(.{
            common.Transform,
            components.Character,
            components.Collider,
            ecs.system_params.Without(components.PhysicsDisabled),
        }) catch return;
        defer character_result.deinit();

        var character_it = character_result.iterator();
        while (character_it.next()) |row| {
            seen_characters.put(self.allocator, row.entity_id, {}) catch continue;

            const transform = row.get(common.Transform) orelse continue;
            const character = row.get(components.Character) orelse continue;
            const collider = row.get(components.Collider) orelse continue;
            const velocity = row.get(components.CharacterVelocity);
            const dirty = row.get(components.PhysicsDirty) != null;
            const existing = self.characters.get(row.entity_id);

            if (dirty and existing != null) {
                self.destroyCharacter(row.entity_id, existing.?.character_id);
            }

            const record = self.characters.get(row.entity_id);
            if (record == null) {
                const created = self.createCharacter(row.entity_id, transform.*, character.*, collider.*, velocity) orelse continue;
                self.characters.put(self.allocator, row.entity_id, .{ .character_id = created }) catch {
                    _ = pj_character_remove_destroy(self.native, created);
                    continue;
                };

                if (row.get(components.CharacterHandle)) |handle| {
                    handle.value = created;
                } else {
                    commands.addComponent(row.entity_id, components.CharacterHandle{ .value = created }) catch {};
                }
                if (row.get(components.CharacterState) == null) {
                    commands.addComponent(row.entity_id, components.CharacterState{}) catch {};
                }
                if (dirty) {
                    commands.removeComponent(row.entity_id, components.PhysicsDirty) catch {};
                }
                continue;
            }

            const character_id = record.?.character_id;
            _ = pj_character_set_transform(
                self.native,
                character_id,
                &vec3ToArray(transform.translation),
                &quatToArray(transform.rotation),
            );
            _ = pj_character_set_linear_velocity(
                self.native,
                character_id,
                &vec3ToArray(if (velocity) |value| value.linear else .{}),
            );
        }

        var stale_character_index: usize = 0;
        while (stale_character_index < self.characters.count()) {
            const entity_id = self.characters.keys()[stale_character_index];
            if (seen_characters.contains(entity_id)) {
                stale_character_index += 1;
                continue;
            }

            const character_id = self.characters.values()[stale_character_index].character_id;
            _ = pj_character_remove_destroy(self.native, character_id);
            _ = self.characters.swapRemoveAt(stale_character_index);
        }
    }

    pub fn step(self: *State, config: resources.Config, step_state: *resources.StepState, stats: *resources.Stats) void {
        for (self.characters.values()) |record| {
            _ = pj_character_extended_update(
                self.native,
                record.character_id,
                config.fixed_dt,
                &vec3ToArray(config.gravity),
            );
        }

        var step_ms: f32 = 0.0;
        var body_count: u32 = 0;
        var active_body_count: u32 = 0;
        if (!pj_world_step(self.native, config.fixed_dt, 1, &step_ms, &body_count, &active_body_count)) {
            stats.step_ms = 0.0;
            return;
        }
        step_state.steps_last_frame = 1;
        step_state.alpha = 0.0;
        stats.body_count = body_count;
        stats.active_body_count = active_body_count;
        stats.contact_count = 0;
        stats.broadphase_pairs = 0;
        stats.step_ms = step_ms;
        stats.last_substeps = 1;
    }

    pub fn collectEvents(_: *State) void {}

    pub fn syncOut(self: *State, commands: *ecs.Commands) void {
        var result = commands.query(.{
            common.Transform,
            components.Body,
            components.BodyHandle,
            ecs.system_params.Without(components.PhysicsDisabled),
        }) catch return;
        defer result.deinit();

        var state: PjBodyState = undefined;
        var it = result.iterator();
        while (it.next()) |row| {
            const transform = row.get(common.Transform) orelse continue;
            const body_handle = row.get(components.BodyHandle) orelse continue;
            const velocity = row.get(components.Velocity);
            if (!pj_body_get_state(self.native, @intCast(body_handle.value), &state)) continue;

            transform.translation = arrayToVec3(state.position);
            transform.rotation = arrayToQuat(state.rotation);
            if (velocity) |vel| {
                vel.linear = arrayToVec3(state.linear_velocity);
                vel.angular = arrayToVec3(state.angular_velocity);
            }
        }

        var character_result = commands.query(.{
            common.Transform,
            components.Character,
            components.CharacterHandle,
            ecs.system_params.Without(components.PhysicsDisabled),
        }) catch return;
        defer character_result.deinit();

        var character_state: PjCharacterState = undefined;
        var character_it = character_result.iterator();
        while (character_it.next()) |row| {
            const transform = row.get(common.Transform) orelse continue;
            const handle = row.get(components.CharacterHandle) orelse continue;
            const velocity = row.get(components.CharacterVelocity);
            const state_component = row.get(components.CharacterState);
            if (!pj_character_get_state(self.native, @intCast(handle.value), &character_state)) continue;

            transform.translation = arrayToVec3(character_state.position);
            transform.rotation = arrayToQuat(character_state.rotation);
            if (velocity) |value| {
                value.linear = arrayToVec3(character_state.linear_velocity);
            }
            if (state_component) |value| {
                value.ground_state = characterGroundStateFromPj(character_state.ground_state);
                value.ground_normal = arrayToVec3(character_state.ground_normal);
                value.ground_velocity = arrayToVec3(character_state.ground_velocity);
                value.ground_body = if (character_state.ground_body_id == 0) null else .{ .value = character_state.ground_body_id };
                value.ground_entity = if (character_state.ground_user_data == 0) null else character_state.ground_user_data;
                value.max_hits_exceeded = character_state.max_hits_exceeded;
            }
        }
    }

    pub fn castRay(self: *State, ray: queries.RayCast) ?queries.RayHit {
        var hit: PjRayCastHit = .{};
        if (!pj_world_cast_ray(
            self.native,
            &vec3ToArray(ray.origin),
            &vec3ToArray(ray.direction),
            ray.max_distance,
            ray.collision.layer,
            ray.collision.mask,
            &hit,
        )) return null;
        if (!hit.hit) return null;

        return .{
            .entity = if (hit.user_data == 0) null else hit.user_data,
            .body = .{ .value = hit.body_id },
            .position = arrayToVec3(hit.position),
            .normal = arrayToVec3(hit.normal),
            .distance = hit.distance,
        };
    }

    pub fn castShape(self: *State, cast: queries.ShapeCast) ?queries.ShapeHit {
        var desc = shapeCastDesc(cast) orelse return null;
        var hit: PjShapeCastHit = .{};
        if (!pj_world_cast_shape(
            self.native,
            &desc,
            &vec3ToArray(cast.translation),
            cast.collision.layer,
            cast.collision.mask,
            &hit,
        )) return null;
        if (!hit.hit) return null;

        return .{
            .entity = if (hit.user_data == 0) null else hit.user_data,
            .body = .{ .value = hit.body_id },
            .position = arrayToVec3(hit.position),
            .normal = arrayToVec3(hit.normal),
            .fraction = hit.fraction,
        };
    }

    fn destroyBody(self: *State, entity_id: ecs.Entity.Id, body_id: u32) void {
        _ = pj_body_remove_destroy(self.native, body_id);
        _ = self.bodies.swapRemove(entity_id);
    }

    fn destroyCharacter(self: *State, entity_id: ecs.Entity.Id, character_id: u32) void {
        _ = pj_character_remove_destroy(self.native, character_id);
        _ = self.characters.swapRemove(entity_id);
    }

    fn createBody(
        self: *State,
        commands: *ecs.Commands,
        entity_id: ecs.Entity.Id,
        transform: common.Transform,
        body: components.Body,
        collider: components.Collider,
        velocity: ?*components.Velocity,
        mass: ?*components.MassProperties,
        lock_axes: ?*components.LockAxes,
        kinematic_target: ?*components.KinematicTarget,
    ) ?u32 {
        var desc = PjBodyDesc{
            .user_data = entity_id,
            .motion_type = motionType(body.kind),
            .shape_kind = undefined,
            .object_layer = collider.collision.layer,
            .collision_mask = collider.collision.mask,
            .allowed_dofs_mask = lockAxesMask(lock_axes),
            .is_sensor = collider.is_sensor,
            .allow_sleep = body.allow_sleep,
            .use_ccd = body.is_ccd,
            .collide_kinematic_vs_non_dynamic = body.kind == .Kinematic,
            .use_enhanced_internal_edge_removal = body.kind != .Static,
            .override_mass = mass != null and mass.?.mode == .Explicit,
            .friction = collider.material.friction,
            .restitution = collider.material.restitution,
            .linear_damping = body.linear_damping,
            .angular_damping = body.angular_damping,
            .gravity_scale = body.gravity_scale,
            .density = collider.density,
            .mass = if (mass) |value| value.mass else 1.0,
            .position = vec3ToArray(if (body.kind == .Kinematic and kinematic_target != null) kinematic_target.?.transform.translation else transform.translation),
            .rotation = quatToArray(if (body.kind == .Kinematic and kinematic_target != null) kinematic_target.?.transform.rotation else transform.rotation),
            .linear_velocity = vec3ToArray(if (velocity) |value| value.linear else common.Vec3{}),
            .angular_velocity = vec3ToArray(if (velocity) |value| value.angular else common.Vec3{}),
            .half_extents = .{ 0.0, 0.0, 0.0 },
            .radius = 0.0,
            .half_height = 0.0,
            .heightfield_offset = .{ 0.0, 0.0, 0.0 },
            .heightfield_scale = .{ 1.0, 1.0, 1.0 },
            .heightfield_sample_count = 0,
        };

        var mesh_vertices: ?[]const f32 = null;
        var mesh_indices: ?[]const u32 = null;
        var height_samples: ?[]const f32 = null;
        var mesh_file: ?bake.mesh_formats.File = null;
        defer if (mesh_file) |*file| file.deinit(self.allocator);
        defer if (mesh_vertices) |value| self.allocator.free(value);

        switch (collider.shape) {
            .Sphere => |shape| {
                desc.shape_kind = .sphere;
                desc.radius = shape.radius;
            },
            .Capsule => |shape| {
                desc.shape_kind = .capsule;
                desc.radius = shape.radius;
                desc.half_height = shape.half_height;
            },
            .Box => |shape| {
                desc.shape_kind = .box;
                desc.half_extents = vec3ToArray(shape.half_extents);
            },
            .Cylinder => |shape| {
                desc.shape_kind = .cylinder;
                desc.radius = shape.radius;
                desc.half_height = shape.half_height;
            },
            .TriangleMesh => |handle| {
                desc.shape_kind = .triangle_mesh;
                const store = commands.getResource(resources.CollisionMeshStore) orelse return null;
                const asset = store.get(handle) orelse return null;
                if (asset.blob.format != .PhysicsMeshV1) return null;
                mesh_file = bake.mesh_formats.parseAlloc(self.allocator, asset.blob.bytes) catch return null;
                const file = &mesh_file.?;

                var vertices = self.allocator.alloc(f32, file.vertices.len * 3) catch return null;
                for (file.vertices, 0..) |vertex, i| {
                    vertices[i * 3 + 0] = vertex.position.x;
                    vertices[i * 3 + 1] = vertex.position.y;
                    vertices[i * 3 + 2] = vertex.position.z;
                }
                mesh_vertices = vertices;
                mesh_indices = file.indices;
            },
            .HeightField => |handle| {
                desc.shape_kind = .height_field;
                const store = commands.getResource(resources.HeightFieldStore) orelse return null;
                const asset = store.get(handle) orelse return null;
                desc.heightfield_offset = vec3ToArray(asset.offset);
                desc.heightfield_scale = vec3ToArray(asset.scale);
                desc.heightfield_sample_count = asset.sample_count;
                height_samples = asset.heights;
            },
            .Compound => return null,
        }

        var body_id: u32 = 0;
        if (!pj_body_create(
            self.native,
            &desc,
            if (mesh_vertices) |value| value.ptr else null,
            if (mesh_vertices) |value| @intCast(value.len / 3) else 0,
            if (mesh_indices) |value| value.ptr else null,
            if (mesh_indices) |value| @intCast(value.len) else 0,
            if (height_samples) |value| value.ptr else null,
            if (height_samples) |value| @intCast(value.len) else 0,
            &body_id,
        )) {
            std.log.warn(
                "jolt body create failed: entity={} shape={s} motion={s}",
                .{
                    entity_id,
                    switch (collider.shape) {
                        .Sphere => "sphere",
                        .Capsule => "capsule",
                        .Box => "box",
                        .Cylinder => "cylinder",
                        .TriangleMesh => "triangle_mesh",
                        .HeightField => "height_field",
                        .Compound => "compound",
                    },
                    switch (body.kind) {
                        .Static => "static",
                        .Dynamic => "dynamic",
                        .Kinematic => "kinematic",
                    },
                },
            );
            return null;
        }
        return body_id;
    }

    fn createCharacter(
        self: *State,
        entity_id: ecs.Entity.Id,
        transform: common.Transform,
        character: components.Character,
        collider: components.Collider,
        velocity: ?*components.CharacterVelocity,
    ) ?u32 {
        var desc = PjCharacterDesc{
            .user_data = entity_id,
            .shape_kind = undefined,
            .object_layer = collider.collision.layer,
            .collision_mask = collider.collision.mask,
            .position = vec3ToArray(transform.translation),
            .rotation = quatToArray(transform.rotation),
            .linear_velocity = vec3ToArray(if (velocity) |value| value.linear else .{}),
            .half_extents = .{ 0.0, 0.0, 0.0 },
            .radius = 0.0,
            .half_height = 0.0,
            .mass = character.mass,
            .max_strength = character.max_strength,
            .max_slope_angle_radians = character.max_slope_angle_radians,
            .padding = character.padding,
            .penetration_recovery_speed = character.penetration_recovery_speed,
            .predictive_contact_distance = character.predictive_contact_distance,
            .max_collision_iterations = character.max_collision_iterations,
            .max_constraint_iterations = character.max_constraint_iterations,
            .min_time_remaining = character.min_time_remaining,
            .collision_tolerance = character.collision_tolerance,
            .max_hits = character.max_hits,
            .hit_reduction_cos_max_angle = character.hit_reduction_cos_max_angle,
            .enhanced_internal_edge_removal = character.enhanced_internal_edge_removal,
            .stick_to_floor_distance = character.stick_to_floor_distance,
            .step_up_height = character.step_up_height,
            .step_forward_min_distance = character.step_forward_min_distance,
            .step_forward_test_distance = character.step_forward_test_distance,
            .step_down_extra_distance = character.step_down_extra_distance,
        };

        switch (collider.shape) {
            .Sphere => |shape| {
                desc.shape_kind = .sphere;
                desc.radius = shape.radius;
            },
            .Capsule => |shape| {
                desc.shape_kind = .capsule;
                desc.radius = shape.radius;
                desc.half_height = shape.half_height;
            },
            .Box => |shape| {
                desc.shape_kind = .box;
                desc.half_extents = vec3ToArray(shape.half_extents);
            },
            .Cylinder => |shape| {
                desc.shape_kind = .cylinder;
                desc.radius = shape.radius;
                desc.half_height = shape.half_height;
            },
            .TriangleMesh, .HeightField, .Compound => return null,
        }

        var character_id: u32 = 0;
        if (!pj_character_create(self.native, &desc, &character_id)) {
            std.log.warn(
                "jolt character create failed: entity={} shape={s}",
                .{ entity_id, shapeKindLabel(collider.shape) },
            );
            return null;
        }
        return character_id;
    }
};

fn vec3ToArray(value: common.Vec3) [3]f32 {
    return .{ value.x, value.y, value.z };
}

fn quatToArray(value: common.Quat) [4]f32 {
    return .{ value.x, value.y, value.z, value.w };
}

fn arrayToVec3(value: [3]f32) common.Vec3 {
    return .{ .x = value[0], .y = value[1], .z = value[2] };
}

fn arrayToQuat(value: [4]f32) common.Quat {
    return .{ .x = value[0], .y = value[1], .z = value[2], .w = value[3] };
}

fn characterGroundStateFromPj(value: PjCharacterGroundState) components.CharacterGroundState {
    return switch (value) {
        .on_ground => .OnGround,
        .on_steep_ground => .OnSteepGround,
        .not_supported => .NotSupported,
        .in_air => .InAir,
    };
}

fn motionType(kind: components.Body.Kind) PjMotionType {
    return switch (kind) {
        .Static => .static,
        .Dynamic => .dynamic,
        .Kinematic => .kinematic,
    };
}

fn lockAxesMask(lock_axes: ?*components.LockAxes) u32 {
    const value = lock_axes orelse return 0b11_1111;
    var mask: u32 = 0;
    if (!value.translation_x) mask |= 1 << 0;
    if (!value.translation_y) mask |= 1 << 1;
    if (!value.translation_z) mask |= 1 << 2;
    if (!value.rotation_x) mask |= 1 << 3;
    if (!value.rotation_y) mask |= 1 << 4;
    if (!value.rotation_z) mask |= 1 << 5;
    return if (mask == 0) 0b11_1111 else mask;
}

fn shapeKindLabel(shape: components.Shape) []const u8 {
    return switch (shape) {
        .Sphere => "sphere",
        .Capsule => "capsule",
        .Box => "box",
        .Cylinder => "cylinder",
        .TriangleMesh => "triangle_mesh",
        .HeightField => "height_field",
        .Compound => "compound",
    };
}

fn shapeCastDesc(cast: queries.ShapeCast) ?PjBodyDesc {
    var desc = PjBodyDesc{
        .user_data = 0,
        .motion_type = .dynamic,
        .shape_kind = undefined,
        .object_layer = cast.collision.layer,
        .collision_mask = cast.collision.mask,
        .allowed_dofs_mask = 0b11_1111,
        .is_sensor = false,
        .allow_sleep = true,
        .use_ccd = false,
        .collide_kinematic_vs_non_dynamic = false,
        .use_enhanced_internal_edge_removal = true,
        .override_mass = false,
        .friction = 0.0,
        .restitution = 0.0,
        .linear_damping = 0.0,
        .angular_damping = 0.0,
        .gravity_scale = 1.0,
        .density = 1.0,
        .mass = 1.0,
        .position = vec3ToArray(cast.start.translation),
        .rotation = quatToArray(cast.start.rotation),
        .linear_velocity = .{ 0.0, 0.0, 0.0 },
        .angular_velocity = .{ 0.0, 0.0, 0.0 },
        .half_extents = .{ 0.0, 0.0, 0.0 },
        .radius = 0.0,
        .half_height = 0.0,
        .heightfield_offset = .{ 0.0, 0.0, 0.0 },
        .heightfield_scale = .{ 1.0, 1.0, 1.0 },
        .heightfield_sample_count = 0,
    };

    switch (cast.shape) {
        .Sphere => |shape| {
            desc.shape_kind = .sphere;
            desc.radius = shape.radius;
        },
        .Capsule => |shape| {
            desc.shape_kind = .capsule;
            desc.radius = shape.radius;
            desc.half_height = shape.half_height;
        },
        .Box => |shape| {
            desc.shape_kind = .box;
            desc.half_extents = vec3ToArray(shape.half_extents);
        },
        .Cylinder => |shape| {
            desc.shape_kind = .cylinder;
            desc.radius = shape.radius;
            desc.half_height = shape.half_height;
        },
        .TriangleMesh, .HeightField, .Compound => return null,
    }

    return desc;
}

const NativeWorld = opaque {};

const PjMotionType = enum(c_int) {
    static = 0,
    dynamic = 1,
    kinematic = 2,
};

const PjShapeKind = enum(c_int) {
    sphere = 0,
    capsule = 1,
    box = 2,
    cylinder = 3,
    triangle_mesh = 4,
    height_field = 5,
};

const PjWorldConfig = extern struct {
    gravity: [3]f32,
    max_bodies: u32,
    max_body_pairs: u32,
    max_contact_constraints: u32,
    temp_allocator_bytes: u32,
    max_jobs: u32,
    max_barriers: u32,
};

const PjBodyDesc = extern struct {
    user_data: u64,
    motion_type: PjMotionType,
    shape_kind: PjShapeKind,
    object_layer: u32,
    collision_mask: u32,
    allowed_dofs_mask: u32,
    is_sensor: bool,
    allow_sleep: bool,
    use_ccd: bool,
    collide_kinematic_vs_non_dynamic: bool,
    use_enhanced_internal_edge_removal: bool,
    override_mass: bool,
    friction: f32,
    restitution: f32,
    linear_damping: f32,
    angular_damping: f32,
    gravity_scale: f32,
    density: f32,
    mass: f32,
    position: [3]f32,
    rotation: [4]f32,
    linear_velocity: [3]f32,
    angular_velocity: [3]f32,
    half_extents: [3]f32,
    radius: f32,
    half_height: f32,
    heightfield_offset: [3]f32,
    heightfield_scale: [3]f32,
    heightfield_sample_count: u32,
};

const PjBodyState = extern struct {
    position: [3]f32,
    rotation: [4]f32,
    linear_velocity: [3]f32,
    angular_velocity: [3]f32,
    user_data: u64,
};

const PjCharacterGroundState = enum(c_int) {
    on_ground = 0,
    on_steep_ground = 1,
    not_supported = 2,
    in_air = 3,
};

const PjCharacterDesc = extern struct {
    user_data: u64,
    shape_kind: PjShapeKind,
    object_layer: u32,
    collision_mask: u32,
    position: [3]f32,
    rotation: [4]f32,
    linear_velocity: [3]f32,
    half_extents: [3]f32,
    radius: f32,
    half_height: f32,
    mass: f32,
    max_strength: f32,
    max_slope_angle_radians: f32,
    padding: f32,
    penetration_recovery_speed: f32,
    predictive_contact_distance: f32,
    max_collision_iterations: u32,
    max_constraint_iterations: u32,
    min_time_remaining: f32,
    collision_tolerance: f32,
    max_hits: u32,
    hit_reduction_cos_max_angle: f32,
    enhanced_internal_edge_removal: bool,
    stick_to_floor_distance: f32,
    step_up_height: f32,
    step_forward_min_distance: f32,
    step_forward_test_distance: f32,
    step_down_extra_distance: f32,
};

const PjCharacterState = extern struct {
    position: [3]f32,
    rotation: [4]f32,
    linear_velocity: [3]f32,
    ground_state: PjCharacterGroundState,
    ground_normal: [3]f32,
    ground_velocity: [3]f32,
    ground_body_id: u32,
    ground_user_data: u64,
    max_hits_exceeded: bool,
};

const PjRayCastHit = extern struct {
    hit: bool = false,
    body_id: u32 = 0,
    user_data: u64 = 0,
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    normal: [3]f32 = .{ 0.0, 0.0, 0.0 },
    distance: f32 = 0.0,
};

const PjShapeCastHit = extern struct {
    hit: bool = false,
    body_id: u32 = 0,
    user_data: u64 = 0,
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    normal: [3]f32 = .{ 0.0, 0.0, 0.0 },
    fraction: f32 = 0.0,
};

extern fn pj_world_create(config: *const PjWorldConfig, out_world: *?*NativeWorld) bool;
extern fn pj_world_destroy(world: *NativeWorld) void;
extern fn pj_world_step(world: *NativeWorld, dt: f32, collision_steps: c_int, out_step_ms: *f32, out_body_count: *u32, out_active_body_count: *u32) bool;
extern fn pj_body_create(
    world: *NativeWorld,
    desc: *const PjBodyDesc,
    mesh_vertices_xyz: ?[*]const f32,
    mesh_vertex_count: u32,
    mesh_indices: ?[*]const u32,
    mesh_index_count: u32,
    height_samples: ?[*]const f32,
    height_sample_count: u32,
    out_body_id: *u32,
) bool;
extern fn pj_body_remove_destroy(world: *NativeWorld, body_id: u32) bool;
extern fn pj_body_set_transform(world: *NativeWorld, body_id: u32, position: *const [3]f32, rotation: *const [4]f32, activate: bool) bool;
extern fn pj_body_set_velocities(world: *NativeWorld, body_id: u32, linear_velocity: *const [3]f32, angular_velocity: *const [3]f32) bool;
extern fn pj_body_move_kinematic(world: *NativeWorld, body_id: u32, position: *const [3]f32, rotation: *const [4]f32, dt: f32) bool;
extern fn pj_body_get_state(world: *NativeWorld, body_id: u32, out_state: *PjBodyState) bool;
extern fn pj_character_create(world: *NativeWorld, desc: *const PjCharacterDesc, out_character_id: *u32) bool;
extern fn pj_character_remove_destroy(world: *NativeWorld, character_id: u32) bool;
extern fn pj_character_set_transform(world: *NativeWorld, character_id: u32, position: *const [3]f32, rotation: *const [4]f32) bool;
extern fn pj_character_set_linear_velocity(world: *NativeWorld, character_id: u32, linear_velocity: *const [3]f32) bool;
extern fn pj_character_extended_update(world: *NativeWorld, character_id: u32, dt: f32, gravity: *const [3]f32) bool;
extern fn pj_character_get_state(world: *NativeWorld, character_id: u32, out_state: *PjCharacterState) bool;
extern fn pj_world_cast_ray(world: *NativeWorld, origin: *const [3]f32, direction: *const [3]f32, max_distance: f32, source_layer: u32, collision_mask: u32, out_hit: *PjRayCastHit) bool;
extern fn pj_world_cast_shape(world: *NativeWorld, desc: *const PjBodyDesc, translation: *const [3]f32, source_layer: u32, collision_mask: u32, out_hit: *PjShapeCastHit) bool;
