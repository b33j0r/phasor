const std = @import("std");

pub fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

pub const InputEvent = struct {
    key: u32,
    is_down: bool,
};

const max_input_events = 256;
var input_events: [max_input_events]InputEvent = undefined;
var input_event_count: u32 = 0;
var mouse_delta_x: f32 = 0.0;
var mouse_delta_y: f32 = 0.0;

pub export fn wasmInputKey(key: u32, is_down: bool) void {
    if (input_event_count >= max_input_events) return;
    input_events[input_event_count] = .{ .key = key, .is_down = is_down };
    input_event_count += 1;
}

pub export fn wasmInputMouseDelta(dx: f32, dy: f32) void {
    mouse_delta_x += dx;
    mouse_delta_y += dy;
}

pub fn drainInputEvents(out: []InputEvent) usize {
    const count = @min(out.len, @as(usize, input_event_count));
    if (count == 0) return 0;
    @memcpy(out[0..count], input_events[0..count]);
    input_event_count = 0;
    return count;
}

pub const MouseDelta = struct {
    dx: f32,
    dy: f32,
};

pub fn drainMouseDelta() MouseDelta {
    const delta = MouseDelta{
        .dx = mouse_delta_x,
        .dy = mouse_delta_y,
    };
    mouse_delta_x = 0.0;
    mouse_delta_y = 0.0;
    return delta;
}

pub fn setMouseCapture(enabled: bool) void {
    wasmSetMouseCapture(enabled);
}

extern "env" fn wasmSetMouseCapture(enabled: bool) void;
