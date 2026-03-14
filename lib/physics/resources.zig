const common = @import("common");

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
    format: Format = .JoltBaked,

    pub const Format = enum {
        JoltBaked,
        TriangleSoup,
    };
};

pub const CollisionMeshAsset = struct {
    blob: CollisionMeshBlob,
};
