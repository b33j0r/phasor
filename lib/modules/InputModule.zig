const builtin = @import("builtin");

const core = @import("InputModule_core.zig");
const backend = if (builtin.target.cpu.arch.isWasm())
    @import("InputModule_wasm.zig")
else
    @import("InputModule_glfw.zig");

pub const Key = core.Key;
pub const KeyPressed = core.KeyPressed;
pub const KeyReleased = core.KeyReleased;
pub const KeyDown = core.KeyDown;
pub const Keyboard = core.Keyboard;
pub const keyFromInt = core.keyFromInt;
pub const keys_to_poll = core.keys_to_poll;

pub const install = backend.install;
pub const uninstall = backend.uninstall;
