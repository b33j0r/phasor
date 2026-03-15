pub fn FpsPhysicsModule(comptime ControlledTag: type) type {
    return struct {
        pub const FpsController = struct {
            yaw: f32 = 0.0,
            pitch: f32 = 0.0,
            move_speed: f32 = 8.0,
            look_sensitivity: f32 = 0.003,
            jump_speed: f32 = 6.5,
            radius: f32 = 0.35,
            height: f32 = 1.8,
            eye_offset_y: f32 = 0.5,
            grounded: bool = false,
            coyote_time: f32 = 0.1,
            coyote_timer: f32 = 0.0,
            jump_buffer_time: f32 = 0.12,
            jump_buffer_timer: f32 = 0.0,
        };

        pub const intent_schedule_default = "FpsControllerIntent";
        pub const input_schedule_default = "InputUpdate";

        intent_schedule: []const u8 = intent_schedule_default,
        input_schedule: []const u8 = input_schedule_default,
        max_intent_dt: f32 = 1.0 / 30.0,

        pub fn install(self: *const @This(), app: *AppCommands, cmds: *Commands) !void {
            if (!cmds.hasResource(TimeModule.DeltaTime)) return error.MissingTimeModule;
            if (!cmds.hasResource(InputModule.Keyboard)) return error.MissingInputModule;
            if (!cmds.hasResource(physics.Config)) return error.MissingPhysicsModule;
            if (!cmds.hasResource(physics.BackendWorld)) return error.MissingPhysicsModule;

            try ensureScheduleBetween(app, self.input_schedule, self.intent_schedule, physics.PhysicsSchedules.SyncIn);
            try cmds.insertResource(FpsPhysicsSettings{
                .max_intent_dt = self.max_intent_dt,
            });

            try app.addSystem(self.intent_schedule, updateFpsControllerIntent);
        }

        pub fn uninstall(_: *const @This(), app: *AppCommands, cmds: *Commands) void {
            app.removeSystem(updateFpsControllerIntent);
            _ = cmds.removeResource(FpsPhysicsSettings);
        }

        pub fn capsuleHalfHeight(controller: FpsController) f32 {
            return @max(0.0, controller.height * 0.5 - controller.radius);
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
            dt: Res(TimeModule.DeltaTime),
            physics_config: Res(physics.Config),
            keyboard_opt: ResOpt(InputModule.Keyboard),
            mouse_opt: ResOpt(InputModule.Mouse),
            settings: Res(FpsPhysicsSettings),
            query: Query(.{ common.Transform, FpsController, physics.CharacterVelocity, physics.CharacterState, ControlledTag }),
        ) void {
            const keyboard = keyboard_opt.ptr;
            const mouse = mouse_opt.ptr;
            const raw_step: f32 = @floatCast(dt.deref().seconds);
            const step: f32 = @min(raw_step, settings.ptr.max_intent_dt);
            if (!(step > 0.0)) return;

            var it = query.iterator();
            while (it.next()) |row| {
                const transform = row.get(common.Transform) orelse continue;
                const controller = row.get(FpsController) orelse continue;
                const velocity = row.get(physics.CharacterVelocity) orelse continue;
                const character_state = row.get(physics.CharacterState) orelse continue;

                var yaw_delta: f32 = 0.0;
                var pitch_delta: f32 = 0.0;

                if (mouse) |m| {
                    yaw_delta -= m.delta_x * controller.look_sensitivity;
                    pitch_delta -= m.delta_y * controller.look_sensitivity;
                }

                if (keyboard) |keys| {
                    if (keys.isKeyDown(.left)) yaw_delta += 1.6 * step;
                    if (keys.isKeyDown(.right)) yaw_delta -= 1.6 * step;
                    if (keys.isKeyDown(.up)) pitch_delta += 1.2 * step;
                    if (keys.isKeyDown(.down)) pitch_delta -= 1.2 * step;
                }

                controller.yaw += yaw_delta;
                controller.pitch = std.math.clamp(controller.pitch + pitch_delta, -1.45, 1.45);
                transform.rotation = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, controller.yaw);

                const yaw_rot = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, controller.yaw);
                const forward_world = yaw_rot.rotateVec3(.{ .x = 0.0, .y = 0.0, .z = -1.0 });
                const right_world = yaw_rot.rotateVec3(.{ .x = 1.0, .y = 0.0, .z = 0.0 });

                var desired = Vec3{};
                if (keyboard) |keys| {
                    if (keys.isKeyDown(.w)) desired = desired.add(forward_world);
                    if (keys.isKeyDown(.s)) desired = desired.sub(forward_world);
                    if (keys.isKeyDown(.d)) desired = desired.add(right_world);
                    if (keys.isKeyDown(.a)) desired = desired.sub(right_world);
                    if (keys.isKeyDown(.space)) controller.jump_buffer_timer = controller.jump_buffer_time;
                }

                desired.y = 0.0;
                var desired_horizontal = Vec3{};
                if (desired.length_squared() > 0.0001) {
                    const normalized = desired.normalize();
                    desired_horizontal = normalized.scale(controller.move_speed);
                }

                const supported = character_state.isSupported();
                controller.grounded = character_state.isGrounded();

                if (supported) {
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
            }
        }
    };
}

const std = @import("std");
const ecs = @import("ecs");
const common = @import("common");
const physics = @import("physics");
const modules = @import("root.zig");

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;
const Vec3 = common.Vec3;
const Quat = common.Quat;
const TimeModule = modules.TimeModule;
const InputModule = modules.InputModule;
