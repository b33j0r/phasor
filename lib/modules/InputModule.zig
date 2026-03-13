const builtin = @import("builtin");

const core = @import("input/input_core.zig");
const backend = if (builtin.target.cpu.arch.isWasm())
    @import("input/input_wasm.zig")
else
    @import("input/input_glfw.zig");

pub const Key = core.Key;
pub const KeyPressed = core.KeyPressed;
pub const KeyReleased = core.KeyReleased;
pub const KeyDown = core.KeyDown;
pub const Keyboard = core.Keyboard;
pub const MouseDelta = core.MouseDelta;
pub const MouseMoved = core.MouseMoved;
pub const MouseButtonPressed = core.MouseButtonPressed;
pub const MouseButtonReleased = core.MouseButtonReleased;
pub const MouseCapture = core.MouseCapture;
pub const MouseButton = core.MouseButton;
pub const Mouse = core.Mouse;
pub const keyFromInt = core.keyFromInt;
pub const keys_to_poll = core.keys_to_poll;

pub const install = backend.install;
pub const uninstall = backend.uninstall;
