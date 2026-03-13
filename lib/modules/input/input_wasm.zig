//! Browser-backed input module implementation.

const core = @import("input_core.zig");
const wasm = @import("wasm");
const ecs = @import("ecs");
const schedule = ecs.schedule;

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const ResOpt = ecs.system_params.ResOpt;
const EventWriter = ecs.events.EventWriter;

pub fn install(app: *AppCommands, commands: *Commands) !void {
    try commands.registerEvent(core.KeyPressed, 256);
    try commands.registerEvent(core.KeyReleased, 32);
    try commands.registerEvent(core.KeyDown, 32);
    try commands.registerEvent(core.MouseDelta, 128);
    try commands.registerEvent(core.MouseMoved, 128);
    try commands.registerEvent(core.MouseButtonPressed, 32);
    try commands.registerEvent(core.MouseButtonReleased, 32);

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
    keyboard_opt: ResOpt(core.Keyboard),
    mouse_opt: ResOpt(core.Mouse),
    capture_opt: ResOpt(core.MouseCapture),
    pressed_writer: EventWriter(core.KeyPressed),
    released_writer: EventWriter(core.KeyReleased),
    down_writer: EventWriter(core.KeyDown),
    mouse_delta_writer: EventWriter(core.MouseDelta),
    mouse_moved_writer: EventWriter(core.MouseMoved),
    mouse_pressed_writer: EventWriter(core.MouseButtonPressed),
    mouse_released_writer: EventWriter(core.MouseButtonReleased),
    commands: *Commands,
) !void {
    const prev_state = if (keyboard_opt.ptr) |kb| kb.* else core.Keyboard{};
    var next_state = core.Keyboard{
        .current = prev_state.current,
        .previous = prev_state.current,
    };

    var events: [128]wasm.InputEvent = undefined;
    const event_count = wasm.drainInputEvents(events[0..]);

    for (events[0..event_count]) |event| {
        const key = core.keyFromInt(event.key) orelse continue;
        const was_down = prev_state.isKeyDown(key);

        if (event.is_down) {
            next_state.setKeyDown(key);
            if (!was_down) {
                try down_writer.send(.{ .key = key });
            }
        } else {
            next_state.setKeyUp(key);
            if (was_down) {
                try released_writer.send(.{ .key = key });
            }
        }
    }

    for (core.keys_to_poll) |key| {
        if (next_state.isKeyDown(key)) {
            try pressed_writer.send(.{ .key = key });
        }
    }

    const prev_mouse = if (mouse_opt.ptr) |m| m.* else core.Mouse{};
    var next_mouse = prev_mouse;
    next_mouse.delta_x = 0.0;
    next_mouse.delta_y = 0.0;
    next_mouse.previous_x = prev_mouse.x;
    next_mouse.previous_y = prev_mouse.y;
    next_mouse.previous_buttons = prev_mouse.current_buttons;

    const wants_capture = if (capture_opt.ptr) |capture| capture.enabled else false;
    if (wants_capture != prev_mouse.captured) {
        wasm.setMouseCapture(wants_capture);
        next_mouse.captured = wants_capture;
    }

    const delta = wasm.drainMouseDelta();
    const position = wasm.mousePosition();
    next_mouse.x = position.x;
    next_mouse.y = position.y;
    next_mouse.has_position = true;
    const buttons = wasm.mouseButtons();
    next_mouse.current_buttons = buttons;
    next_mouse.delta_x = delta.dx;
    next_mouse.delta_y = delta.dy;
    const pointer_dx = next_mouse.x - next_mouse.previous_x;
    const pointer_dy = next_mouse.y - next_mouse.previous_y;
    if (pointer_dx != 0.0 or pointer_dy != 0.0) {
        try mouse_moved_writer.send(.{
            .x = next_mouse.x,
            .y = next_mouse.y,
            .dx = pointer_dx,
            .dy = pointer_dy,
        });
    }
    inline for ([_]core.MouseButton{ .left, .right, .middle }) |button| {
        const is_down = next_mouse.isButtonDown(button);
        const was_down = prev_mouse.isButtonDown(button);
        if (is_down and !was_down) {
            try mouse_pressed_writer.send(.{
                .button = button,
                .x = next_mouse.x,
                .y = next_mouse.y,
            });
        } else if (!is_down and was_down) {
            try mouse_released_writer.send(.{
                .button = button,
                .x = next_mouse.x,
                .y = next_mouse.y,
            });
        }
    }
    if (delta.dx != 0.0 or delta.dy != 0.0) {
        try mouse_delta_writer.send(.{
            .dx = delta.dx,
            .dy = delta.dy,
        });
    }

    try commands.insertResource(next_state);
    try commands.insertResource(next_mouse);
}
