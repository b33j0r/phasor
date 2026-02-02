//! GLFW-backed input module implementation.

const core = @import("InputModule_core.zig");
const glfw = @import("glfw").c;
const ecs = @import("ecs");
const schedule = ecs.schedule;
const window = @import("window");

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const ResOpt = ecs.system_params.ResOpt;
const EventWriter = ecs.events.EventWriter;
const Window = window.Window;

pub fn install(app: *AppCommands, commands: *Commands) !void {
    try commands.registerEvent(core.KeyPressed, 256);
    try commands.registerEvent(core.KeyReleased, 32);
    try commands.registerEvent(core.KeyDown, 32);

    if (!commands.hasResource(core.Keyboard)) {
        try commands.insertResource(core.Keyboard{});
    }

    try app.insertScheduleBetween(schedule.DefaultSchedule.BeforeFrame, "InputUpdate", schedule.DefaultSchedule.Update);
    try app.addSystem("InputUpdate", pollKeyboard);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(pollKeyboard);
}

fn pollKeyboard(
    r_window: ResOpt(Window),
    keyboard_opt: ResOpt(core.Keyboard),
    pressed_writer: EventWriter(core.KeyPressed),
    released_writer: EventWriter(core.KeyReleased),
    down_writer: EventWriter(core.KeyDown),
    commands: *Commands,
) !void {
    const window_res = r_window.ptr orelse return;
    const handle = window_res.handle orelse return;

    const prev_state = if (keyboard_opt.ptr) |kb| kb.* else core.Keyboard{};
    var next_state = core.Keyboard{ .previous = prev_state.current };

    for (core.keys_to_poll) |key| {
        const state = glfw.glfwGetKey(handle, key.toGlfwKey());
        const is_down = (state == glfw.GLFW_PRESS or state == glfw.GLFW_REPEAT);
        const was_down = prev_state.isKeyDown(key);

        if (is_down) {
            next_state.setKeyDown(key);
            try pressed_writer.send(.{ .key = key });
            if (!was_down) {
                try down_writer.send(.{ .key = key });
            }
        } else if (was_down) {
            try released_writer.send(.{ .key = key });
        }
    }

    try commands.insertResource(next_state);
}
