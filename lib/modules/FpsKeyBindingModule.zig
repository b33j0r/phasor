pub const FpsKeyBindings = struct {
    forward: InputModule.Key = .w,
    backward: InputModule.Key = .s,
    right: InputModule.Key = .d,
    left: InputModule.Key = .a,
    jump: InputModule.Key = .space,
    crouch: InputModule.Key = .left_control,
    sprint: InputModule.Key = .left_shift,
    look_left: InputModule.Key = .left,
    look_right: InputModule.Key = .right,
    look_up: InputModule.Key = .up,
    look_down: InputModule.Key = .down,
};

pub const FpsKeyBindingModule = struct {
    input_schedule: []const u8 = "InputUpdate",
    look_key_yaw_speed: f32 = 1.6,
    look_key_pitch_speed: f32 = 1.2,
    bindings: FpsKeyBindings = .{},

    pub fn install(self: *const FpsKeyBindingModule, app: *AppCommands, cmds: *Commands) !void {
        if (!cmds.hasResource(TimeModule.DeltaTime)) return error.MissingTimeModule;
        if (!cmds.hasResource(InputModule.Keyboard)) return error.MissingInputModule;
        if (!cmds.hasResource(FpsControlInput)) {
            try cmds.insertResource(FpsControlInput{});
        }
        try cmds.insertResource(FpsKeyBindingSettings{
            .look_key_yaw_speed = self.look_key_yaw_speed,
            .look_key_pitch_speed = self.look_key_pitch_speed,
            .bindings = self.bindings,
        });
        try app.addSystem(self.input_schedule, updateFpsControlInputFromBindings);
    }

    pub fn uninstall(self: *const FpsKeyBindingModule, app: *AppCommands, cmds: *Commands) void {
        _ = self;
        app.removeSystem(updateFpsControlInputFromBindings);
        _ = cmds.removeResource(FpsKeyBindingSettings);
    }
};

const FpsKeyBindingSettings = struct {
    look_key_yaw_speed: f32,
    look_key_pitch_speed: f32,
    bindings: FpsKeyBindings,
};

fn updateFpsControlInputFromBindings(
    dt: Res(TimeModule.DeltaTime),
    keyboard_opt: ResOpt(InputModule.Keyboard),
    mouse_opt: ResOpt(InputModule.Mouse),
    settings: Res(FpsKeyBindingSettings),
    control_input: ResMut(FpsControlInput),
) void {
    const input = control_input.ptr;
    input.move_forward = 0.0;
    input.move_right = 0.0;
    input.look_key_yaw = 0.0;
    input.look_key_pitch = 0.0;
    input.jump_pressed = false;
    input.crouch_held = false;
    input.sprint_held = false;
    input.look_delta_x = 0.0;
    input.look_delta_y = 0.0;

    const keyboard = keyboard_opt.ptr;
    if (keyboard) |keys| {
        if (keys.isKeyDown(settings.ptr.bindings.forward)) input.move_forward += 1.0;
        if (keys.isKeyDown(settings.ptr.bindings.backward)) input.move_forward -= 1.0;
        if (keys.isKeyDown(settings.ptr.bindings.right)) input.move_right += 1.0;
        if (keys.isKeyDown(settings.ptr.bindings.left)) input.move_right -= 1.0;

        input.jump_pressed = keys.isKeyPressed(settings.ptr.bindings.jump);
        input.crouch_held = keys.isKeyDown(settings.ptr.bindings.crouch);
        input.sprint_held = isKeyBindingDown(keys, settings.ptr.bindings.sprint);

        const step: f32 = @floatCast(dt.ptr.seconds);
        if (keys.isKeyDown(settings.ptr.bindings.look_left)) input.look_key_yaw += settings.ptr.look_key_yaw_speed * step;
        if (keys.isKeyDown(settings.ptr.bindings.look_right)) input.look_key_yaw -= settings.ptr.look_key_yaw_speed * step;
        if (keys.isKeyDown(settings.ptr.bindings.look_up)) input.look_key_pitch += settings.ptr.look_key_pitch_speed * step;
        if (keys.isKeyDown(settings.ptr.bindings.look_down)) input.look_key_pitch -= settings.ptr.look_key_pitch_speed * step;
    }

    if (mouse_opt.ptr) |mouse| {
        input.look_delta_x = mouse.delta_x;
        input.look_delta_y = mouse.delta_y;
    }
}

fn isKeyBindingDown(keys: *const InputModule.Keyboard, key: InputModule.Key) bool {
    return switch (key) {
        .left_shift, .right_shift => keys.isKeyDown(.left_shift) or keys.isKeyDown(.right_shift),
        .left_control, .right_control => keys.isKeyDown(.left_control) or keys.isKeyDown(.right_control),
        .left_alt, .right_alt => keys.isKeyDown(.left_alt) or keys.isKeyDown(.right_alt),
        else => keys.isKeyDown(key),
    };
}

// Imports
const ecs = @import("ecs");
const modules = @import("root.zig");

const FpsControlInput = @import("FpsPhysicsModule.zig").FpsControlInput;

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;
const InputModule = modules.InputModule;
const TimeModule = modules.TimeModule;
