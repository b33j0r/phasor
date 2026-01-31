test "import tests" {
    _ = meta;
    _ = Entity;
    _ = column;
    _ = table;
    _ = hooks;
    _ = Database;
    _ = QuerySpec;
    _ = QueryResult;
    _ = GroupByResult;
    _ = Trait;
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
pub const GroupByResult = @import("GroupByResult.zig");
pub const Trait = @import("Trait.zig");
pub const Deinit = Trait.Deinit;
pub const Group = Trait.Group;
pub const GroupTrait = Trait.GroupTrait;
