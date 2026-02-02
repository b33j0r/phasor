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
    keyboard_opt: ResOpt(core.Keyboard),
    pressed_writer: EventWriter(core.KeyPressed),
    released_writer: EventWriter(core.KeyReleased),
    down_writer: EventWriter(core.KeyDown),
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

    try commands.insertResource(next_state);
}
