test "import tests" {
    _ = PhasesModule;
    _ = MetricsModule;
    _ = TimeModule;
    _ = TimerModule;
}

// Imports
pub const PhasesModule = @import("modules/PhasesModule.zig");
pub const MetricsModule = @import("modules/MetricsModule.zig");
pub const TimeModule = @import("modules/TimeModule.zig");
pub const TimerModule = @import("modules/TimerModule.zig");
