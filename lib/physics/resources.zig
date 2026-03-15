const std = @import("std");
const common = @import("common");
const components = @import("components.zig");

pub const Config = struct {
    backend: Backend = .Null,
    fixed_dt: f32 = 1.0 / 60.0,
    max_substeps: u8 = 4,
    max_frame_dt: f32 = 0.25,
    gravity: common.Vec3 = .{ .x = 0.0, .y = -9.81, .z = 0.0 },
    writeback_mode: WritebackMode = .AuthoritativeToTransform,
    execution: Execution = .MainThread,

    pub const Backend = enum {
        Jolt,
        Null,
        Simple,
    };

    pub const WritebackMode = enum {
        AuthoritativeToTransform,
        InterpolatedToTransform,
    };

    pub const Execution = enum {
        MainThread,
        WorkerThread,
    };
};

pub const StepState = struct {
    accumulator: f32 = 0.0,
    alpha: f32 = 0.0,
    steps_last_frame: u8 = 0,
};

pub const Stats = struct {
    body_count: u32 = 0,
    active_body_count: u32 = 0,
    contact_count: u32 = 0,
    broadphase_pairs: u32 = 0,
    step_ms: f32 = 0.0,
    last_substeps: u8 = 0,
};

pub const CollisionMeshBlob = struct {
    bytes: []const u8,
    format: Format = .PhysicsMeshV1,

    pub const Format = enum {
        PhysicsMeshV1,
        JoltBaked,
        TriangleSoup,
    };
};

pub const CollisionMeshAsset = struct {
    blob: CollisionMeshBlob,
};

pub const CollisionMeshStore = struct {
    allocator: std.mem.Allocator,
    next_handle: u32 = 1,
    assets: std.AutoArrayHashMapUnmanaged(u32, CollisionMeshAsset) = .empty,

    pub fn init(allocator: std.mem.Allocator) CollisionMeshStore {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CollisionMeshStore) void {
        var it = self.assets.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.blob.bytes);
        }
        self.assets.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn add(self: *CollisionMeshStore, blob: CollisionMeshBlob) !components.CollisionMeshHandle {
        const handle_value = self.next_handle;
        self.next_handle += 1;
        const owned = try self.allocator.dupe(u8, blob.bytes);
        errdefer self.allocator.free(owned);
        try self.assets.put(self.allocator, handle_value, .{
            .blob = .{
                .bytes = owned,
                .format = blob.format,
            },
        });
        return @enumFromInt(handle_value);
    }

    pub fn get(self: *const CollisionMeshStore, handle: components.CollisionMeshHandle) ?CollisionMeshAsset {
        return self.assets.get(@intFromEnum(handle));
    }
};

pub const HeightFieldAsset = struct {
    sample_count: u32,
    offset: common.Vec3 = .{},
    scale: common.Vec3 = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    heights: []const f32,
};

pub const HeightFieldStore = struct {
    allocator: std.mem.Allocator,
    next_handle: u32 = 1,
    assets: std.AutoArrayHashMapUnmanaged(u32, HeightFieldAsset) = .empty,

    pub fn init(allocator: std.mem.Allocator) HeightFieldStore {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *HeightFieldStore) void {
        var it = self.assets.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.heights);
        }
        self.assets.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn add(self: *HeightFieldStore, asset: HeightFieldAsset) !components.HeightFieldHandle {
        const sample_count_usize: usize = asset.sample_count;
        const expected_count = sample_count_usize * sample_count_usize;
        if (asset.heights.len != expected_count) return error.InvalidHeightFieldSampleCount;

        const handle_value = self.next_handle;
        self.next_handle += 1;
        const owned_heights = try self.allocator.dupe(f32, asset.heights);
        errdefer self.allocator.free(owned_heights);

        try self.assets.put(self.allocator, handle_value, .{
            .sample_count = asset.sample_count,
            .offset = asset.offset,
            .scale = asset.scale,
            .heights = owned_heights,
        });
        return @enumFromInt(handle_value);
    }

    pub fn get(self: *const HeightFieldStore, handle: components.HeightFieldHandle) ?HeightFieldAsset {
        return self.assets.get(@intFromEnum(handle));
    }
};
