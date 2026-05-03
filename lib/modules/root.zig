pub const std_options = @import("common").logging.moduleStdOptions();

test "import tests" {
    _ = PhasesModule;
    _ = TimeModule;
    _ = TimerModule;
    _ = ParentModule;
    _ = InputModule;
    _ = NoiseModule;
}

// Imports
pub const PhasesModule = @import("PhasesModule.zig");
pub const TimeModule = @import("TimeModule.zig");
pub const TimerModule = @import("TimerModule.zig");
pub const ParentModule = @import("ParentModule.zig");
pub const InputModule = @import("InputModule.zig");
pub const NoiseModule = @import("NoiseModule.zig").NoiseModule;
pub const NoiseResource = @import("NoiseModule.zig").NoiseResource;
pub const FastNoise = @import("NoiseModule.zig").FastNoise;
