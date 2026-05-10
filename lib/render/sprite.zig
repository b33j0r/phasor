pub const Sprite = struct {
    color: common.Color = common.Color.WHITE,
    material: ?mesh.Material = null,
    size_mode: SizeMode = .Auto,
    source_size: ?utils.Size = null,
    mesh_handle: mesh.MeshHandle = mesh.MeshHandle.invalid(),
    size_hash: u64 = 0,

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
};

pub fn sizeHash(sprite: Sprite) u64 {
    var hash = std.hash.Wyhash.init(0);
    const tag: u8 = @intFromEnum(std.meta.activeTag(sprite.size_mode));
    hash.update(std.mem.asBytes(&tag));
    switch (sprite.size_mode) {
        .Auto => {
            if (sprite.source_size) |size| {
                hash.update(std.mem.asBytes(&size.width));
                hash.update(std.mem.asBytes(&size.height));
            }
        },
        .Manual => |m| {
            hash.update(std.mem.asBytes(&m.width));
            hash.update(std.mem.asBytes(&m.height));
        },
    }
    return hash.final();
}

const std = @import("std");
const common = @import("common");
const mesh = @import("mesh.zig");
const utils = @import("utils.zig");
