test "import tests" {
    _ = TimeModule;
    _ = TimerModule;
}

// Imports
pub const TimeModule = @import("modules/TimeModule.zig");
pub const TimerModule = @import("modules/TimerModule.zig");
