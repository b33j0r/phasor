test "import tests" {
    _ = meta;
    _ = Entity;
    _ = column;
    _ = table;
    _ = hooks;
    _ = Database;
    _ = QuerySpec;
    _ = QueryResult;
}

// Imports
pub const meta = @import("meta.zig");
pub const Entity = @import("Entity.zig");
pub const column = @import("column.zig");
pub const table = @import("table.zig");
pub const hooks = @import("hooks.zig");
pub const Database = @import("Database.zig");
pub const QuerySpec = @import("QuerySpec.zig");
pub const QueryResult = @import("QueryResult.zig");
