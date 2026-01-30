test "import tests" {
    _ = PhasesModule;
    _ = MetricsModule;
    _ = TimeModule;
    _ = TimerModule;
    _ = RenderModule;
}

// Imports
pub const PhasesModule = @import("PhasesModule.zig");
pub const MetricsModule = @import("MetricsModule.zig").MetricsModule;
pub const TimeModule = @import("TimeModule.zig");
pub const TimerModule = @import("TimerModule.zig");
pub const RenderModule = @import("RenderModule.zig");
