/// Comptime analysis of system function signatures to determine data access patterns.
/// Used by the parallel executor to identify which systems can safely run concurrently.
///
/// Access rules:
/// - `*Commands` or `WorldRef` → exclusive world access (conflicts with everything)
/// - `Res(T)` / `ResOpt(T)` / `HasResource(T)` → reads resource T
/// - `ResMut(T)` / `ResMutOpt(T)` → writes resource T
/// - `Query(...)` → component access (treated as shared read for now)
/// A unique identifier for a resource type, derived from its type name pointer.
/// Since Zig deduplicates `@typeName` string literals, pointer equality is valid.
pub const ResourceId = [*]const u8;

pub fn resourceId(comptime T: type) ResourceId {
    const name = @typeName(T);
    return name.ptr;
}

/// Describes a single resource access: which resource and whether it's mutable.
pub const ResourceAccess = struct {
    id: ResourceId,
    mutable: bool,
};

/// Describes the full data access pattern of a system.
pub const AccessDescriptor = struct {
    /// True if the system requires exclusive world access (uses *Commands or WorldRef).
    exclusive: bool,
    /// True if the system accesses components via Query/GroupBy.
    reads_components: bool,
    /// Resource accesses (reads and writes).
    resources: []const ResourceAccess,

    pub fn conflictsWith(self: *const AccessDescriptor, other: *const AccessDescriptor) bool {
        // Exclusive systems conflict with everything.
        if (self.exclusive or other.exclusive) return true;

        // Check resource conflicts: write/write or read/write on the same resource.
        for (self.resources) |a| {
            for (other.resources) |b| {
                if (a.id == b.id) {
                    if (a.mutable or b.mutable) return true;
                }
            }
        }

        if (self.reads_components and other.reads_components) return true;

        return false;
    }
};

/// Analyzes a system function's parameters at comptime and returns an AccessDescriptor.
pub fn analyzeAccess(comptime system_fn: anytype) AccessDescriptor {
    const fn_type = @TypeOf(system_fn);
    const ArgsTupleType = std.meta.ArgsTuple(fn_type);
    const fields = std.meta.fields(ArgsTupleType);

    var exclusive = false;
    var reads_components = false;
    var resource_accesses: [fields.len]ResourceAccess = undefined;
    var resource_count: usize = 0;

    inline for (fields) |field| {
        const ParamType = field.type;

        if (ParamType == *Commands) {
            exclusive = true;
        } else if (ParamType == system_params.WorldRef) {
            exclusive = true;
        } else if (isResType(ParamType)) {
            resource_accesses[resource_count] = .{
                .id = resourceId(extractInnerType(ParamType)),
                .mutable = false,
            };
            resource_count += 1;
        } else if (isResMutType(ParamType)) {
            resource_accesses[resource_count] = .{
                .id = resourceId(extractInnerType(ParamType)),
                .mutable = true,
            };
            resource_count += 1;
        } else if (isResOptType(ParamType)) {
            resource_accesses[resource_count] = .{
                .id = resourceId(extractInnerType(ParamType)),
                .mutable = false,
            };
            resource_count += 1;
        } else if (isResMutOptType(ParamType)) {
            resource_accesses[resource_count] = .{
                .id = resourceId(extractInnerType(ParamType)),
                .mutable = true,
            };
            resource_count += 1;
        } else if (isHasResourceType(ParamType)) {
            resource_accesses[resource_count] = .{
                .id = resourceId(extractInnerType(ParamType)),
                .mutable = false,
            };
            resource_count += 1;
        } else if (isQueryType(ParamType) or isGroupByType(ParamType)) {
            reads_components = true;
        }
    }

    const frozen = resource_accesses[0..resource_count].*;
    return .{
        .exclusive = exclusive,
        .reads_components = reads_components,
        .resources = &frozen,
    };
}

// --- Type detection helpers ---
// Each system_params generic type has a distinctive shape we can detect.

fn isResType(comptime T: type) bool {
    return @hasDecl(T, "init_system_param") and @hasDecl(T, "deref") and
        hasFieldOfType(T, "ptr", true) and !hasFieldOfType(T, "ptr", false);
}

fn isResMutType(comptime T: type) bool {
    return @hasDecl(T, "init_system_param") and @hasDecl(T, "deref") and
        hasFieldOfType(T, "ptr", false) and !isOptionalPtr(T, "ptr");
}

fn isResOptType(comptime T: type) bool {
    return @hasDecl(T, "init_system_param") and @hasDecl(T, "deref") and
        isOptionalConstPtr(T, "ptr");
}

fn isResMutOptType(comptime T: type) bool {
    return @hasDecl(T, "init_system_param") and @hasDecl(T, "deref") and
        isOptionalMutPtr(T, "ptr");
}

fn isHasResourceType(comptime T: type) bool {
    return @hasDecl(T, "init_system_param") and @typeInfo(T) == .@"struct" and
        hasNamedField(T, "value") and !@hasDecl(T, "deref");
}

fn isQueryType(comptime T: type) bool {
    return @hasDecl(T, "init_system_param") and @hasDecl(T, "iterator") and
        hasNamedField(T, "result");
}

fn isGroupByType(comptime T: type) bool {
    return @hasDecl(T, "init_system_param") and @hasDecl(T, "iterator") and
        hasNamedField(T, "result") and !@hasDecl(T, "first");
}

fn hasNamedField(comptime T: type, comptime name: []const u8) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    for (info.@"struct".fields) |f| {
        if (std.mem.eql(u8, f.name, name)) return true;
    }
    return false;
}

fn hasFieldOfType(comptime T: type, comptime name: []const u8, comptime is_const: bool) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    for (info.@"struct".fields) |f| {
        if (std.mem.eql(u8, f.name, name)) {
            const ptr_info = @typeInfo(f.type);
            if (ptr_info == .pointer) {
                if (is_const) return ptr_info.pointer.is_const;
                return !ptr_info.pointer.is_const;
            }
        }
    }
    return false;
}

fn isOptionalPtr(comptime T: type, comptime name: []const u8) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    for (info.@"struct".fields) |f| {
        if (std.mem.eql(u8, f.name, name)) {
            return @typeInfo(f.type) == .optional;
        }
    }
    return false;
}

fn isOptionalConstPtr(comptime T: type, comptime name: []const u8) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    for (info.@"struct".fields) |f| {
        if (std.mem.eql(u8, f.name, name)) {
            const f_info = @typeInfo(f.type);
            if (f_info != .optional) return false;
            const child_info = @typeInfo(f_info.optional.child);
            if (child_info == .pointer) return child_info.pointer.is_const;
        }
    }
    return false;
}

fn isOptionalMutPtr(comptime T: type, comptime name: []const u8) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    for (info.@"struct".fields) |f| {
        if (std.mem.eql(u8, f.name, name)) {
            const f_info = @typeInfo(f.type);
            if (f_info != .optional) return false;
            const child_info = @typeInfo(f_info.optional.child);
            if (child_info == .pointer) return !child_info.pointer.is_const;
        }
    }
    return false;
}

/// Extract the inner resource type T from Res(T), ResMut(T), etc.
/// Works by inspecting the `ptr` field's pointee type for pointer-based params,
/// or falls back to the `value` field for HasResource.
fn extractInnerType(comptime T: type) type {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("Expected struct type");
    for (info.@"struct".fields) |f| {
        if (std.mem.eql(u8, f.name, "ptr")) {
            const f_info = @typeInfo(f.type);
            if (f_info == .optional) {
                // Optional pointer: ?*T or ?*const T
                const child_info = @typeInfo(f_info.optional.child);
                if (child_info == .pointer) return child_info.pointer.child;
            } else if (f_info == .pointer) {
                return f_info.pointer.child;
            }
        }
        if (std.mem.eql(u8, f.name, "value")) {
            // HasResource stores a bool, but we need the resource type.
            // We detect it from the init_system_param signature instead.
            // For now, use a sentinel approach: the HasResource struct itself is the key.
            return T;
        }
    }
    @compileError("Cannot extract inner type from " ++ @typeName(T));
}

// Imports
const std = @import("std");
const system_params = @import("system_params.zig");
const Commands = @import("Commands.zig");

// Tests
const testing = std.testing;

const Health = struct { hp: u32 = 100 };
const Mana = struct { mp: u32 = 50 };
const Position = struct { x: f32 = 0, y: f32 = 0 };
const Velocity = struct { dx: f32 = 0, dy: f32 = 0 };

fn readHealthSystem(_: system_params.Res(Health)) void {}
fn writeHealthSystem(_: system_params.ResMut(Health)) void {}
fn readHealthAndMana(_: system_params.Res(Health), _: system_params.Res(Mana)) void {}
fn writeHealthReadMana(_: system_params.ResMut(Health), _: system_params.Res(Mana)) void {}
fn commandsSystem(_: *Commands) void {}
fn querySystem(_: system_params.Query(.{Position})) void {}
fn mixedSystem(_: system_params.Res(Health), _: system_params.Query(.{Position})) void {}

test "analyzeAccess detects read-only resource" {
    const access = comptime analyzeAccess(readHealthSystem);
    try testing.expect(!access.exclusive);
    try testing.expect(!access.reads_components);
    try testing.expectEqual(@as(usize, 1), access.resources.len);
    try testing.expect(!access.resources[0].mutable);
}

test "analyzeAccess detects mutable resource" {
    const access = comptime analyzeAccess(writeHealthSystem);
    try testing.expect(!access.exclusive);
    try testing.expectEqual(@as(usize, 1), access.resources.len);
    try testing.expect(access.resources[0].mutable);
}

test "analyzeAccess detects exclusive access from Commands" {
    const access = comptime analyzeAccess(commandsSystem);
    try testing.expect(access.exclusive);
}

test "analyzeAccess detects query as component read" {
    const access = comptime analyzeAccess(querySystem);
    try testing.expect(!access.exclusive);
    try testing.expect(access.reads_components);
}

test "conflictsWith: two readers do not conflict" {
    const a = comptime analyzeAccess(readHealthSystem);
    const b = comptime analyzeAccess(readHealthAndMana);
    try testing.expect(!a.conflictsWith(&b));
}

test "conflictsWith: writer conflicts with reader on same resource" {
    const a = comptime analyzeAccess(writeHealthSystem);
    const b = comptime analyzeAccess(readHealthSystem);
    try testing.expect(a.conflictsWith(&b));
}

test "conflictsWith: exclusive conflicts with everything" {
    const a = comptime analyzeAccess(commandsSystem);
    const b = comptime analyzeAccess(readHealthSystem);
    try testing.expect(a.conflictsWith(&b));
}

test "conflictsWith: disjoint resources do not conflict" {
    const a = comptime analyzeAccess(writeHealthReadMana);
    const sys_b = struct {
        fn run(_: system_params.Query(.{Position})) void {}
    }.run;
    const b = comptime analyzeAccess(sys_b);
    try testing.expect(!a.conflictsWith(&b));
}

test "conflictsWith: mixed system with shared read resource no conflict" {
    const a = comptime analyzeAccess(mixedSystem);
    const b = comptime analyzeAccess(readHealthSystem);
    try testing.expect(!a.conflictsWith(&b));
}
