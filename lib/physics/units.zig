pub const Meters = struct {
    value: f32,

    pub fn from(value: f32) Meters {
        return .{ .value = value };
    }
};

pub const Seconds = struct {
    value: f32,

    pub fn from(value: f32) Seconds {
        return .{ .value = value };
    }
};

pub const Kilograms = struct {
    value: f32,

    pub fn from(value: f32) Kilograms {
        return .{ .value = value };
    }
};

pub const MetersPerSecond = struct {
    value: f32,

    pub fn from(value: f32) MetersPerSecond {
        return .{ .value = value };
    }
};

pub const MetersPerSecondSquared = struct {
    value: f32,

    pub fn from(value: f32) MetersPerSecondSquared {
        return .{ .value = value };
    }
};

pub const Hertz = struct {
    value: f32,

    pub fn from(value: f32) Hertz {
        return .{ .value = value };
    }

    pub fn period(self: Hertz) Seconds {
        return .{ .value = 1.0 / self.value };
    }
};
