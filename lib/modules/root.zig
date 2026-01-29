test "import tests" {
    _ = PhasesModule;
    _ = MetricsModule;
    _ = TimeModule;
    _ = TimerModule;
}

// Imports
pub const PhasesModule = @import("PhasesModule.zig");
pub const MetricsModule = @import("MetricsModule.zig");
pub const TimeModule = @import("TimeModule.zig");
pub const TimerModule = @import("TimerModule.zig");
