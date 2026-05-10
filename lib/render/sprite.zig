pub const Sprite = struct {
    color: common.Color = common.Color.WHITE,
    material: ?mesh.Material = null,
    size_mode: SizeMode = .Auto,
    source_size: ?utils.Size = null,

    pub const SizeMode = union(enum) {
        Auto,
        Manual: struct {
            width: f32,
            height: f32,
        },
    };

    pub fn withMaterial(self: Sprite, material: mesh.Material) Sprite {
        var out = self;
        out.material = material;
        return out;
    }

    pub fn dimensions(self: Sprite) struct { width: f32, height: f32 } {
        return switch (self.size_mode) {
            .Auto => blk: {
                if (self.source_size) |size| {
                    break :blk .{
                        .width = @floatFromInt(size.width),
                        .height = @floatFromInt(size.height),
                    };
                }
                break :blk .{ .width = 1.0, .height = 1.0 };
            },
            .Manual => |m| .{ .width = m.width, .height = m.height },
        };
    }

    pub fn meshKey(self: Sprite) shape.GeneratedMeshKey {
        const size = self.dimensions();
        return shape.GeneratedMeshKey.spriteQuad(size.width, size.height);
    }
};

test "sprite mesh key is based on resolved dimensions" {
    const a = Sprite{ .size_mode = .{ .Manual = .{ .width = 32.0, .height = 16.0 } } };
    const b = Sprite{
        .source_size = .{ .width = 32, .height = 16 },
    };
    try std.testing.expectEqual(a.meshKey(), b.meshKey());
}

const std = @import("std");
const common = @import("common");
const mesh = @import("mesh.zig");
const shape = @import("shape.zig");
const utils = @import("utils.zig");
