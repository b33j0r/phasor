pub fn FpsPhysicsModule(comptime ControlledTag: type) type {
    return struct {
        pub const FpsController = struct {
            yaw: f32 = 0.0,
            pitch: f32 = 0.0,
            move_speed: f32 = 8.0,
            look_sensitivity: f32 = 0.003,
            jump_speed: f32 = 6.5,
            gravity: f32 = -18.0,
            velocity_y: f32 = 0.0,
            move_x: f32 = 0.0,
            move_z: f32 = 0.0,
            radius: f32 = 0.35,
            height: f32 = 1.8,
            grounded: bool = false,
            coyote_time: f32 = 0.1,
            coyote_timer: f32 = 0.0,
            jump_buffer_time: f32 = 0.12,
            jump_buffer_timer: f32 = 0.0,
        };

        pub const StaticAabb = struct {
            min: Vec3,
            max: Vec3,
        };

        pub const intent_schedule_default = "FpsControllerIntent";
        pub const physics_schedule_default = "FpsPhysics";
        pub const input_schedule_default = "InputUpdate";

        intent_schedule: []const u8 = intent_schedule_default,
        physics_schedule: []const u8 = physics_schedule_default,
        input_schedule: []const u8 = input_schedule_default,
        update_schedule: []const u8 = schedule.DefaultSchedule.Update,
        max_intent_dt: f32 = 1.0 / 30.0,
        max_physics_dt: f32 = 1.0 / 15.0,
        max_substep_dt: f32 = 1.0 / 120.0,
        max_substeps: usize = 8,
        collision_skin: f32 = 0.001,

        pub fn install(self: *const @This(), app: *AppCommands, cmds: *Commands) !void {
            if (!cmds.hasResource(TimeModule.DeltaTime)) return error.MissingTimeModule;
            if (!cmds.hasResource(InputModule.Keyboard)) return error.MissingInputModule;

            try ensureScheduleBetween(app, self.input_schedule, self.intent_schedule, self.update_schedule);
            try ensureScheduleBetween(app, self.intent_schedule, self.physics_schedule, self.update_schedule);

            try cmds.insertResource(FpsPhysicsSettings{
                .intent_schedule = self.intent_schedule,
                .physics_schedule = self.physics_schedule,
                .max_intent_dt = self.max_intent_dt,
                .max_physics_dt = self.max_physics_dt,
                .max_substep_dt = self.max_substep_dt,
                .max_substeps = self.max_substeps,
                .collision_skin = self.collision_skin,
            });

            try app.addSystem(self.intent_schedule, updateFpsControllerIntent);
            try app.addSystem(self.physics_schedule, movePlayerAndCollide);
        }

        pub fn uninstall(self: *const @This(), app: *AppCommands, cmds: *Commands) void {
            _ = self;
            app.removeSystem(updateFpsControllerIntent);
            app.removeSystem(movePlayerAndCollide);
            _ = cmds.removeResource(FpsPhysicsSettings);
        }

        pub fn addStaticCollider(commands: *Commands, center: Vec3, half: Vec3) !void {
            _ = try commands.createEntity(.{aabbFromCenter(center, half)});
        }

        pub fn aabbFromCenter(center: Vec3, half: Vec3) StaticAabb {
            return .{
                .min = .{ .x = center.x - half.x, .y = center.y - half.y, .z = center.z - half.z },
                .max = .{ .x = center.x + half.x, .y = center.y + half.y, .z = center.z + half.z },
            };
        }

        pub fn aabbIntersects(a: StaticAabb, b: StaticAabb) bool {
            return a.min.x <= b.max.x and a.max.x >= b.min.x and
                a.min.y <= b.max.y and a.max.y >= b.min.y and
                a.min.z <= b.max.z and a.max.z >= b.min.z;
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
            intent_schedule: []const u8,
            physics_schedule: []const u8,
            max_intent_dt: f32,
            max_physics_dt: f32,
            max_substep_dt: f32,
            max_substeps: usize,
            collision_skin: f32,
        };

        fn updateFpsControllerIntent(
            dt: Res(TimeModule.DeltaTime),
            keyboard_opt: ResOpt(InputModule.Keyboard),
            mouse_opt: ResOpt(InputModule.Mouse),
            settings: Res(FpsPhysicsSettings),
            query: Query(.{ common.Transform, FpsController, ControlledTag }),
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

                const yaw_rot = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, controller.yaw);
                const pitch_rot = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, controller.pitch);
                transform.rotation = yaw_rot.mul(pitch_rot).normalize();

                const forward_world = yaw_rot.rotateVec3(.{ .x = 0.0, .y = 0.0, .z = -1.0 });
                const right_world = yaw_rot.rotateVec3(.{ .x = 1.0, .y = 0.0, .z = 0.0 });

                var desired = Vec3{};
                if (keyboard) |keys| {
                    if (keys.isKeyDown(.w)) desired = desired.add(forward_world);
                    if (keys.isKeyDown(.s)) desired = desired.sub(forward_world);
                    if (keys.isKeyDown(.d)) desired = desired.add(right_world);
                    if (keys.isKeyDown(.a)) desired = desired.sub(right_world);
                    if (keys.isKeyPressed(.space)) controller.jump_buffer_timer = controller.jump_buffer_time;
                }

                desired.y = 0.0;
                if (desired.length_squared() > 0.0001) {
                    const normalized = desired.normalize();
                    controller.move_x = normalized.x * controller.move_speed;
                    controller.move_z = normalized.z * controller.move_speed;
                } else {
                    controller.move_x = 0.0;
                    controller.move_z = 0.0;
                }

                controller.velocity_y += controller.gravity * step;
                controller.jump_buffer_timer = @max(controller.jump_buffer_timer - step, 0.0);
                controller.coyote_timer = @max(controller.coyote_timer - step, 0.0);
            }
        }

        fn movePlayerAndCollide(
            dt: Res(TimeModule.DeltaTime),
            settings: Res(FpsPhysicsSettings),
            players: Query(.{ common.Transform, FpsController, ControlledTag }),
            colliders: Query(.{StaticAabb}),
        ) void {
            const raw_step: f32 = @floatCast(dt.deref().seconds);
            const step: f32 = @min(raw_step, settings.ptr.max_physics_dt);
            if (!(step > 0.0)) return;

            const max_substeps = @max(@as(usize, 1), settings.ptr.max_substeps);
            const max_substep_dt = @max(0.00001, settings.ptr.max_substep_dt);
            const skin = settings.ptr.collision_skin;

            var pit = players.iterator();
            while (pit.next()) |prow| {
                const transform = prow.get(common.Transform) orelse continue;
                const controller = prow.get(FpsController) orelse continue;

                const half = Vec3{
                    .x = controller.radius,
                    .y = controller.height * 0.5,
                    .z = controller.radius,
                };

                var pos = transform.translation;
                var vel = Vec3{
                    .x = controller.move_x,
                    .y = controller.velocity_y,
                    .z = controller.move_z,
                };

                if (controller.grounded) controller.coyote_timer = controller.coyote_time;

                if (controller.jump_buffer_timer > 0.0 and controller.coyote_timer > 0.0) {
                    vel.y = controller.jump_speed;
                    controller.velocity_y = controller.jump_speed;
                    controller.grounded = false;
                    controller.coyote_timer = 0.0;
                    controller.jump_buffer_timer = 0.0;
                }

                controller.grounded = false;

                var remaining = step;
                var substeps: usize = 0;
                while (remaining > 0.0 and substeps < max_substeps) : (substeps += 1) {
                    const sub_dt = @min(remaining, max_substep_dt);
                    resolveAxis(&pos, half, vel.x * sub_dt, .x, &vel, skin, colliders, &controller.grounded);
                    resolveAxis(&pos, half, vel.z * sub_dt, .z, &vel, skin, colliders, &controller.grounded);
                    resolveAxis(&pos, half, vel.y * sub_dt, .y, &vel, skin, colliders, &controller.grounded);
                    remaining -= sub_dt;
                }

                transform.translation = pos;
                controller.velocity_y = vel.y;
            }
        }

        const Axis = enum { x, y, z };

        fn resolveAxis(
            pos: *Vec3,
            half: Vec3,
            delta: f32,
            comptime axis: Axis,
            velocity: *Vec3,
            skin: f32,
            colliders: Query(.{StaticAabb}),
            grounded_out: *bool,
        ) void {
            if (!(delta != 0.0)) return;

            switch (axis) {
                .x => pos.x += delta,
                .y => pos.y += delta,
                .z => pos.z += delta,
            }

            var player_box = aabbFromCenter(pos.*, half);

            var it = colliders.iterator();
            while (it.next()) |row| {
                const blocker = row.get(StaticAabb) orelse continue;
                if (!aabbIntersects(player_box, blocker.*)) continue;

                if (delta > 0.0) {
                    switch (axis) {
                        .x => pos.x = blocker.min.x - half.x - skin,
                        .y => {
                            pos.y = blocker.min.y - half.y - skin;
                            velocity.y = 0.0;
                        },
                        .z => pos.z = blocker.min.z - half.z - skin,
                    }
                } else {
                    switch (axis) {
                        .x => pos.x = blocker.max.x + half.x + skin,
                        .y => {
                            pos.y = blocker.max.y + half.y + skin;
                            velocity.y = 0.0;
                            grounded_out.* = true;
                        },
                        .z => pos.z = blocker.max.z + half.z + skin,
                    }
                }

                player_box = aabbFromCenter(pos.*, half);

                switch (axis) {
                    .x => velocity.x = 0.0,
                    .z => velocity.z = 0.0,
                    .y => {},
                }
            }
        }
    };
}

const std = @import("std");
const ecs = @import("ecs");
const common = @import("common");
const modules = @import("root.zig");

const schedule = ecs.schedule;
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResOpt = ecs.system_params.ResOpt;
const Vec3 = common.Vec3;
const Quat = common.Quat;
const TimeModule = modules.TimeModule;
const InputModule = modules.InputModule;

