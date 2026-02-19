//! GLFW-backed input module implementation.

const core = @import("input_core.zig");
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
    try commands.registerEvent(core.MouseDelta, 128);

    if (!commands.hasResource(core.Keyboard)) {
        try commands.insertResource(core.Keyboard{});
    }
    if (!commands.hasResource(core.Mouse)) {
        try commands.insertResource(core.Mouse{});
    }
    if (!commands.hasResource(core.MouseCapture)) {
        try commands.insertResource(core.MouseCapture{});
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
    mouse_opt: ResOpt(core.Mouse),
    capture_opt: ResOpt(core.MouseCapture),
    pressed_writer: EventWriter(core.KeyPressed),
    released_writer: EventWriter(core.KeyReleased),
    down_writer: EventWriter(core.KeyDown),
    mouse_delta_writer: EventWriter(core.MouseDelta),
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

    const prev_mouse = if (mouse_opt.ptr) |m| m.* else core.Mouse{};
    var next_mouse = prev_mouse;
    next_mouse.delta_x = 0.0;
    next_mouse.delta_y = 0.0;

    const wants_capture = if (capture_opt.ptr) |capture| capture.enabled else false;
    if (wants_capture != prev_mouse.captured) {
        glfw.glfwSetInputMode(
            handle,
            glfw.GLFW_CURSOR,
            if (wants_capture) glfw.GLFW_CURSOR_DISABLED else glfw.GLFW_CURSOR_NORMAL,
        );
        next_mouse.captured = wants_capture;
        next_mouse.has_last = false;
    }

    if (wants_capture) {
        var x: f64 = 0.0;
        var y: f64 = 0.0;
        glfw.glfwGetCursorPos(handle, &x, &y);
        if (next_mouse.has_last) {
            next_mouse.delta_x = @floatCast(x - next_mouse.last_x);
            next_mouse.delta_y = @floatCast(y - next_mouse.last_y);
            if (next_mouse.delta_x != 0.0 or next_mouse.delta_y != 0.0) {
                try mouse_delta_writer.send(.{
                    .dx = next_mouse.delta_x,
                    .dy = next_mouse.delta_y,
                });
            }
        }
        next_mouse.last_x = x;
        next_mouse.last_y = y;
        next_mouse.has_last = true;
    } else {
        next_mouse.has_last = false;
    }

    try commands.insertResource(next_state);
    try commands.insertResource(next_mouse);
}
