test "import tests" {
    _ = PhasesModule;
    _ = MetricsModule;
    _ = TimeModule;
    _ = TimerModule;
    _ = RenderModule;
    _ = ParentModule;
    _ = AssetsModule;
    _ = AudioModule;
    _ = InputModule;
}

// Imports
pub const PhasesModule = @import("PhasesModule.zig");
pub const MetricsModule = @import("MetricsModule.zig").MetricsModule(null);
pub const MetricsModuleLayered = @import("MetricsModule.zig").MetricsModule;
pub const TimeModule = @import("TimeModule.zig");
pub const TimerModule = @import("TimerModule.zig");
pub const RenderModule = @import("RenderModule.zig");
pub const ParentModule = @import("ParentModule.zig");
pub const AssetsModule = @import("AssetsModule.zig").AssetsModule;
pub const AudioModule = @import("AudioModule.zig");
pub const InputModule = @import("InputModule.zig");
