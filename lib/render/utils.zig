const std = @import("std");

pub const Size = struct {
    width: u32,
    height: u32,
};

pub const SurfaceTarget = union(enum) {
    native: NativeSurface,
    web: WebSurface,

    pub fn size(self: SurfaceTarget) Size {
        return switch (self) {
            .native => |native| native.size,
            .web => |web| web.size,
        };
    }
};

pub const NativeSurface = struct {
    kind: NativeKind,
    handle: NativeHandle,
    size: Size,
};

pub const NativeKind = enum {
    metal,
    win32,
    x11,
};

pub const NativeHandle = union(NativeKind) {
    metal: struct {
        layer: *anyopaque,
    },
    win32: struct {
        hwnd: *anyopaque,
        hinstance: *anyopaque,
    },
    x11: struct {
        display: *anyopaque,
        window: u64,
    },
};

pub const WebSurface = struct {
    canvas_id: []const u8,
    size: Size,
};

pub const CacheKey = struct {
    a: u64,
    b: u64,
    c: u64,
};

pub fn hashCacheKey(key: CacheKey) u64 {
    var hasher = std.hash.Fnv1a_64.init();
    hasher.update(std.mem.asBytes(&key.a));
    hasher.update(std.mem.asBytes(&key.b));
    hasher.update(std.mem.asBytes(&key.c));
    return hasher.final();
}

pub const RingBuffer = struct {
    size: u64,
    head: u64 = 0,

    pub fn init(size: u64) RingBuffer {
        return .{ .size = size, .head = 0 };
    }

    pub fn reset(self: *RingBuffer) void {
        self.head = 0;
    }

    pub fn allocate(self: *RingBuffer, size: u64, alignment: u64) u64 {
        const aligned = std.mem.alignForward(u64, self.head, alignment);
        if (aligned + size > self.size) {
            self.head = size;
            return 0;
        }
        self.head = aligned + size;
        return aligned;
    }
};

test "hashCacheKey stable" {
    const key = CacheKey{ .a = 1, .b = 2, .c = 3 };
    const h1 = hashCacheKey(key);
    const h2 = hashCacheKey(key);
    try std.testing.expectEqual(h1, h2);
}

test "RingBuffer wrap" {
    var ring = RingBuffer.init(64);
    const a0 = ring.allocate(32, 16);
    try std.testing.expectEqual(@as(u64, 0), a0);
    const a1 = ring.allocate(32, 16);
    try std.testing.expectEqual(@as(u64, 32), a1);
    const a2 = ring.allocate(32, 16);
    try std.testing.expectEqual(@as(u64, 0), a2);
}
