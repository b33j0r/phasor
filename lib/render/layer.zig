pub fn Layer(comptime N: i32) type {
    return struct {
        pub const __traits__ = .{
            struct {
                pub const __trait__ = common.Group(LayerN);
                pub const key: i32 = N;
            },
        };
    };
}

pub const LayerN = struct {};

pub fn CameraLayer(comptime N: i32) type {
    return struct {
        pub const __traits__ = .{
            struct {
                pub const __trait__ = common.Group(CameraLayerN);
                pub const key: i32 = N;
            },
        };
    };
}

pub const CameraLayerN = struct {};

const common = @import("common");
