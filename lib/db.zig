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
pub const meta = @import("db/meta.zig");
pub const Entity = @import("db/Entity.zig");
pub const column = @import("db/column.zig");
pub const table = @import("db/table.zig");
pub const hooks = @import("db/hooks.zig");
pub const Database = @import("db/Database.zig");
pub const QuerySpec = @import("db/QuerySpec.zig");
pub const QueryResult = @import("db/QueryResult.zig");
