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

pub const LayerN = struct {
    pub const __query_group_trait__ = true;
};

pub const LayerOverride = struct {
    value: i32 = 0,
};

pub const LayerSortKey = struct {
    value: i32 = 0,
};

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

pub const CameraLayerN = struct {
    pub const __query_group_trait__ = true;
};

const common = @import("common");
