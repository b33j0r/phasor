pub fn Layer(comptime N: i32) type {
    return struct {
        pub const __group_key__ = N;
        pub const __trait__ = LayerN;
    };
}

pub const LayerN = struct {};

pub fn CameraLayer(comptime N: i32) type {
    return struct {
        pub const __group_key__ = N;
        pub const __trait__ = CameraLayerN;
    };
}

pub const CameraLayerN = struct {};
