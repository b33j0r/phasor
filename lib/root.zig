test "import tests" {
    _ = db;
    _ = ecs;
    _ = metrics;
}

// Imports
pub const db = @import("db.zig");
pub const ecs = @import("ecs.zig");
pub const metrics = @import("metrics.zig");
