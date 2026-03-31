pub const FpsControlInput = struct {
    move_forward: f32 = 0.0,
    move_right: f32 = 0.0,
    look_delta_x: f32 = 0.0,
    look_delta_y: f32 = 0.0,
    look_key_yaw: f32 = 0.0,
    look_key_pitch: f32 = 0.0,
    jump_pressed: bool = false,
    crouch_held: bool = false,
    sprint_held: bool = false,
    toggle_fly_pressed: bool = false,

    pub fn clearTransient(self: *FpsControlInput) void {
        self.look_delta_x = 0.0;
        self.look_delta_y = 0.0;
        self.look_key_yaw = 0.0;
        self.look_key_pitch = 0.0;
        self.jump_pressed = false;
        self.toggle_fly_pressed = false;
    }
};

pub fn FpsPhysicsModule(comptime ControlledTag: type) type {
    return struct {
        pub const FpsController = struct {
            yaw: f32 = 0.0,
            pitch: f32 = 0.0,
            move_speed: f32 = 5.0,
            look_sensitivity: f32 = 0.003,
            jump_speed: f32 = 5.0,
            radius: f32 = 0.35,
            height: f32 = 1.8,
            eye_offset_y: f32 = 0.5,
            sprint_enabled: bool = true,
            sprint_multiplier: f32 = 1.7,
            crouch_enabled: bool = true,
            crouch_speed_multiplier: f32 = 0.45,
            crouch_height: f32 = 1.2,
            crouch_eye_offset_y: f32 = 0.4,
            crouch_transition_rate: f32 = 10.0,
            fly_toggle_enabled: bool = false,
            fly_enabled: bool = false,
            fly_speed_multiplier: f32 = 1.0,
            headbob_enabled: bool = true,
            headbob_frequency_hz: f32 = 1.45,
            headbob_vertical_amplitude: f32 = 0.008,
            headbob_horizontal_amplitude: f32 = 0.0035,
            headbob_sprint_multiplier: f32 = 1.12,
            headbob_crouch_multiplier: f32 = 0.7,
            headbob_min_speed: f32 = 0.85,
            headbob_return_rate: f32 = 10.0,
            grounded: bool = false,
            sprinting: bool = false,
            crouching: bool = false,
            coyote_time: f32 = 0.1,
            coyote_timer: f32 = 0.0,
            jump_buffer_time: f32 = 0.12,
            jump_buffer_timer: f32 = 0.0,
            headbob_phase: f32 = 0.0,
            headbob_offset: Vec3 = .{},
            current_eye_offset_y: f32 = 0.0,
            view_initialized: bool = false,
        };

        pub const intent_schedule_default = "FpsControllerIntent";
        pub const input_schedule_default = "InputUpdate";

        intent_schedule: []const u8 = intent_schedule_default,
        input_schedule: []const u8 = input_schedule_default,
        max_intent_dt: f32 = 1.0 / 30.0,

        pub fn install(self: *const @This(), app: *AppCommands, cmds: *Commands) !void {
            if (!cmds.hasResource(TimeModule.SimulationDeltaTime)) return error.MissingTimeModule;
            if (!cmds.hasResource(physics.Config)) return error.MissingPhysicsModule;
            if (!cmds.hasResource(physics.BackendWorld)) return error.MissingPhysicsModule;

            try ensureScheduleBetween(app, self.input_schedule, self.intent_schedule, physics.PhysicsSchedules.SyncIn);
            try cmds.insertResource(FpsPhysicsSettings{
                .max_intent_dt = self.max_intent_dt,
            });
            if (!cmds.hasResource(FpsControlInput)) {
                try cmds.insertResource(FpsControlInput{});
            }

            try app.addSystem(self.intent_schedule, updateFpsControllerIntent);
        }

        pub fn uninstall(_: *const @This(), app: *AppCommands, cmds: *Commands) void {
            app.removeSystem(updateFpsControllerIntent);
            _ = cmds.removeResource(FpsPhysicsSettings);
            _ = cmds.removeResource(FpsControlInput);
        }

        pub fn capsuleHalfHeight(controller: FpsController) f32 {
            return @max(0.0, controller.height * 0.5 - controller.radius);
        }

        pub fn activeHeight(controller: FpsController) f32 {
            if (controller.crouching and controller.crouch_enabled) return controller.crouch_height;
            return controller.height;
        }

        pub fn activeEyeOffsetY(controller: FpsController) f32 {
            if (controller.view_initialized) return controller.current_eye_offset_y;
            return targetEyeOffsetY(controller);
        }

        pub fn cameraOffset(controller: FpsController) Vec3 {
            return .{
                .x = controller.headbob_offset.x,
                .y = activeEyeOffsetY(controller) + controller.headbob_offset.y,
                .z = controller.headbob_offset.z,
            };
        }

        fn ensureScheduleBetween(
            app: *AppCommands,
            before_label: []const u8,
            label: []const u8,
            after_label: []const u8,
        ) !void {
            app.insertScheduleBetween(before_label, label, after_label) catch |err| switch (err) {
                error.ScheduleAlreadyExists => {},
                else => return err,
            };
        }

        const FpsPhysicsSettings = struct {
            max_intent_dt: f32,
        };

        fn updateFpsControllerIntent(
            commands: *Commands,
            dt: Res(TimeModule.SimulationDeltaTime),
            physics_config: Res(physics.Config),
            world: ResMut(physics.BackendWorld),
            control_input: ResMut(FpsControlInput),
            settings: Res(FpsPhysicsSettings),
            query: Query(.{
                common.Transform,
                FpsController,
                physics.Collider,
                physics.CharacterVelocity,
                physics.CharacterState,
                ControlledTag,
            }),
        ) void {
            const input = control_input.ptr;
            const raw_step: f32 = @floatCast(dt.deref().seconds);
            const step: f32 = @min(raw_step, settings.ptr.max_intent_dt);
            if (!(step > 0.0)) return;

            var it = query.iterator();
            while (it.next()) |row| {
                const transform = row.get(common.Transform) orelse continue;
                const controller = row.get(FpsController) orelse continue;
                const collider = row.get(physics.Collider) orelse continue;
                const velocity = row.get(physics.CharacterVelocity) orelse continue;
                const character_state = row.get(physics.CharacterState) orelse continue;

                var yaw_delta: f32 = 0.0;
                var pitch_delta: f32 = 0.0;

                yaw_delta += input.look_key_yaw - (input.look_delta_x * controller.look_sensitivity);
                pitch_delta += input.look_key_pitch - (input.look_delta_y * controller.look_sensitivity);

                controller.yaw += yaw_delta;
                controller.pitch = std.math.clamp(controller.pitch + pitch_delta, -1.45, 1.45);
                transform.rotation = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, controller.yaw);

                if (input.toggle_fly_pressed and controller.fly_toggle_enabled) {
                    controller.fly_enabled = !controller.fly_enabled;
                    velocity.linear = .{};
                    if (controller.fly_enabled) {
                        commands.addComponent(row.entity_id, physics.PhysicsDisabled{}) catch {};
                    } else {
                        commands.removeComponent(row.entity_id, physics.PhysicsDisabled) catch {};
                    }
                }

                const yaw_rot = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, controller.yaw);
                const forward_world = yaw_rot.rotateVec3(.{ .x = 0.0, .y = 0.0, .z = -1.0 });
                const right_world = yaw_rot.rotateVec3(.{ .x = 1.0, .y = 0.0, .z = 0.0 });

                if (controller.fly_enabled) {
                    const view_rotation = quatFromEuler(controller.pitch, controller.yaw, 0.0);
                    const forward = view_rotation.rotateVec3(.{ .x = 0.0, .y = 0.0, .z = -1.0 }).normalize();
                    const right = view_rotation.rotateVec3(.{ .x = 1.0, .y = 0.0, .z = 0.0 }).normalize();
                    const input_forward = std.math.clamp(input.move_forward, -1.0, 1.0);
                    const input_right = std.math.clamp(input.move_right, -1.0, 1.0);
                    var desired = forward.scale(input_forward).add(right.scale(input_right));
                    var speed = controller.move_speed * controller.fly_speed_multiplier;
                    if (input.sprint_held and controller.sprint_enabled) {
                        speed *= controller.sprint_multiplier;
                    }
                    if (desired.length_squared() > 0.0001) {
                        desired = desired.normalize();
                        transform.translation = transform.translation.add(desired.scale(speed * step));
                    }

                    controller.grounded = false;
                    controller.sprinting = input.sprint_held and desired.length_squared() > 0.0001;
                    controller.jump_buffer_timer = 0.0;
                    controller.coyote_timer = 0.0;
                    updateViewState(controller, step, Vec3{});
                    continue;
                }

                const was_crouching = controller.crouching;
                var wants_crouch = was_crouching;
                var wants_sprint = false;

                if (input.jump_pressed) {
                    controller.jump_buffer_timer = controller.jump_buffer_time;
                }
                if (controller.crouch_enabled) {
                    wants_crouch = input.crouch_held;
                }
                if (controller.sprint_enabled and !wants_crouch) {
                    wants_sprint = input.sprint_held;
                }

                if (was_crouching and !wants_crouch) {
                    wants_crouch = !canStandUp(world.ptr, transform.*, controller.*, collider.*);
                }

                if (wants_crouch != was_crouching) {
                    applyCrouchState(commands, row.entity_id, transform, controller, collider, wants_crouch);
                }

                const input_forward = std.math.clamp(input.move_forward, -1.0, 1.0);
                const input_right = std.math.clamp(input.move_right, -1.0, 1.0);
                var desired = forward_world.scale(input_forward).add(right_world.scale(input_right));
                desired.y = 0.0;
                var desired_horizontal = Vec3{};
                var speed = controller.move_speed;
                if (wants_crouch) {
                    speed *= controller.crouch_speed_multiplier;
                } else if (wants_sprint) {
                    speed *= controller.sprint_multiplier;
                }
                if (desired.length_squared() > 0.0001) {
                    const normalized = desired.normalize();
                    desired_horizontal = normalized.scale(speed);
                }

                const grounded = character_state.isGrounded();
                controller.grounded = grounded;
                controller.crouching = wants_crouch;
                controller.sprinting = wants_sprint and desired_horizontal.length_squared() > 0.0001;

                if (grounded) {
                    controller.coyote_timer = controller.coyote_time;
                    velocity.linear.x = character_state.ground_velocity.x + desired_horizontal.x;
                    velocity.linear.z = character_state.ground_velocity.z + desired_horizontal.z;
                    if (velocity.linear.y < character_state.ground_velocity.y) {
                        velocity.linear.y = character_state.ground_velocity.y;
                    }
                } else {
                    controller.coyote_timer = @max(controller.coyote_timer - step, 0.0);
                    velocity.linear.x = desired_horizontal.x;
                    velocity.linear.z = desired_horizontal.z;
                    velocity.linear = velocity.linear.add(physics_config.ptr.gravity.scale(step));
                }

                controller.jump_buffer_timer = @max(controller.jump_buffer_timer - step, 0.0);
                if (controller.jump_buffer_timer > 0.0 and controller.coyote_timer > 0.0) {
                    velocity.linear.y = controller.jump_speed;
                    controller.grounded = false;
                    controller.coyote_timer = 0.0;
                    controller.jump_buffer_timer = 0.0;
                }

                updateViewState(controller, step, desired_horizontal);
            }
            input.clearTransient();
        }

        fn targetEyeOffsetY(controller: FpsController) f32 {
            if (controller.crouching and controller.crouch_enabled) return controller.crouch_eye_offset_y;
            return controller.eye_offset_y;
        }

        fn applyCrouchState(
            commands: *Commands,
            entity_id: ecs.Entity.Id,
            transform: *common.Transform,
            controller: *FpsController,
            collider: *physics.Collider,
            crouching: bool,
        ) void {
            const previous_half_height = colliderHalfHeight(collider.shape);
            controller.crouching = crouching;
            const target_half_height = capsuleHalfHeight(controller.*);
            transform.translation.y += target_half_height - previous_half_height;

            switch (collider.shape) {
                .Capsule => |*capsule| {
                    capsule.half_height = target_half_height;
                    capsule.radius = controller.radius;
                },
                else => return,
            }

            commands.addComponent(entity_id, physics.PhysicsDirty{}) catch {};
        }

        fn updateViewState(controller: *FpsController, step: f32, desired_horizontal: Vec3) void {
            const eye_target = targetEyeOffsetY(controller.*);
            if (!controller.view_initialized) {
                controller.current_eye_offset_y = eye_target;
                controller.view_initialized = true;
            } else {
                controller.current_eye_offset_y = approach(
                    controller.current_eye_offset_y,
                    eye_target,
                    controller.crouch_transition_rate * step,
                );
            }

            const horizontal_speed = desired_horizontal.length();
            const moving = controller.grounded and horizontal_speed >= controller.headbob_min_speed;
            if (controller.headbob_enabled and moving) {
                var bob_scale: f32 = horizontal_speed / @max(controller.move_speed, 0.001);
                if (controller.sprinting) bob_scale *= controller.headbob_sprint_multiplier;
                if (controller.crouching) bob_scale *= controller.headbob_crouch_multiplier;
                bob_scale = std.math.clamp(bob_scale, 0.0, 1.15);

                controller.headbob_phase += step * std.math.tau * controller.headbob_frequency_hz * bob_scale;
                const lateral = std.math.sin(controller.headbob_phase);
                const step_wave = 0.5 - 0.5 * std.math.cos(controller.headbob_phase * 2.0);
                controller.headbob_offset.x = lateral * controller.headbob_horizontal_amplitude * bob_scale;
                controller.headbob_offset.y = -step_wave * controller.headbob_vertical_amplitude * bob_scale;
            } else {
                controller.headbob_offset.x = approach(controller.headbob_offset.x, 0.0, controller.headbob_return_rate * step);
                controller.headbob_offset.y = approach(controller.headbob_offset.y, 0.0, controller.headbob_return_rate * step);
                controller.headbob_offset.z = 0.0;
            }
        }

        fn canStandUp(
            world: *physics.BackendWorld,
            transform: common.Transform,
            controller: FpsController,
            collider: physics.Collider,
        ) bool {
            if (!controller.crouch_enabled or !controller.crouching) return true;
            const current_half_height = colliderHalfHeight(collider.shape);
            var standing = controller;
            standing.crouching = false;
            const standing_half_height = capsuleHalfHeight(standing);
            const extra_height = standing_half_height - current_half_height;
            if (!(extra_height > 0.0)) return true;

            const top_center = transform.translation.add(.{ .x = 0.0, .y = current_half_height, .z = 0.0 });
            const hit = world.castShape(.{
                .shape = .{ .Sphere = .{ .radius = controller.radius } },
                .start = .{
                    .translation = top_center,
                },
                .translation = .{ .x = 0.0, .y = extra_height, .z = 0.0 },
                .collision = collider.collision,
            });
            return hit == null;
        }

        fn colliderHalfHeight(shape: physics.Shape) f32 {
            return switch (shape) {
                .Capsule => |capsule| capsule.half_height,
                else => 0.0,
            };
        }

        fn approach(current: f32, target: f32, max_delta: f32) f32 {
            if (!(max_delta > 0.0)) return target;
            if (current < target) return @min(current + max_delta, target);
            if (current > target) return @max(current - max_delta, target);
            return target;
        }

        fn quatFromEuler(pitch: f32, yaw: f32, roll: f32) Quat {
            const qx = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, pitch);
            const qy = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, yaw);
            const qz = Quat.fromAxisAngle(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, roll);
            return qy.mul(qx).mul(qz).normalize();
        }
    };
}

const std = @import("std");
const phasor = @import("phasor");
const ecs = phasor.ecs;
const common = phasor.common;
const physics = @import("physics");

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const Vec3 = common.Vec3;
const Quat = common.Quat;
const TimeModule = phasor.modules.TimeModule;
