const std = @import("std");

pub const FrameNum = struct { value: u64 = 0 };
pub const DeltaTime = struct { seconds: f32 = 0 };
pub const ElapsedTime = struct { seconds: f64 = 0 };

pub const Metrics = struct {
    frame: u64 = 0,
    spawned: u64 = 0,
    removed: u64 = 0,
    moved: u64 = 0,
    update_ns: u64 = 0,
    frame_ns: u64 = 0,

    pub fn resetFrame(self: *Metrics) void {
        self.spawned = 0;
        self.removed = 0;
        self.moved = 0;
        self.update_ns = 0;
        self.frame_ns = 0;
    }
};
