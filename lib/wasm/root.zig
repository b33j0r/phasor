const std = @import("std");

pub fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.ioBasic();
}

pub const InputEvent = struct {
    key: u32,
    is_down: bool,
};

const max_input_events = 256;
var input_events: [max_input_events]InputEvent = undefined;
var input_event_count: u32 = 0;

pub export fn wasmInputKey(key: u32, is_down: bool) void {
    if (input_event_count >= max_input_events) return;
    input_events[input_event_count] = .{ .key = key, .is_down = is_down };
    input_event_count += 1;
}

pub fn drainInputEvents(out: []InputEvent) usize {
    const count = @min(out.len, @as(usize, input_event_count));
    if (count == 0) return 0;
    @memcpy(out[0..count], input_events[0..count]);
    input_event_count = 0;
    return count;
}
