const Self = @This();

pub fn init() Self {
    return Self{};
}

pub fn deinit(_: *Self) void {

}

// Imports
const std = @import("std");
