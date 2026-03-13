const std = @import("std");
const common = @import("common");
const ecs = @import("ecs");
const render = @import("render");

pub const Anchor = enum {
    TopLeft,
    TopCenter,
    TopRight,
    CenterLeft,
    Center,
    CenterRight,
    BottomLeft,
    BottomCenter,
    BottomRight,
};

pub const Box = struct {
    width: f32 = 0.0,
    height: f32 = 0.0,

    pub fn sized(width: f32, height: f32) Box {
        return .{ .width = width, .height = height };
    }
};

pub const CanvasRoot = struct {
    z: f32 = 0.0,
};

pub const Placement = struct {
    parent_anchor: Anchor = .TopLeft,
    self_anchor: Anchor = .TopLeft,
    offset: common.Vec2 = .{},
    z: f32 = 0.0,

    pub fn anchored(parent_anchor: Anchor, self_anchor: Anchor, offset: common.Vec2) Placement {
        return .{
            .parent_anchor = parent_anchor,
            .self_anchor = self_anchor,
            .offset = offset,
        };
    }

    pub fn centered(offset: common.Vec2) Placement {
        return anchored(.Center, .Center, offset);
    }

    pub fn topCenter(offset: common.Vec2) Placement {
        return anchored(.TopCenter, .TopCenter, offset);
    }
};

pub const Node = struct {
    entity: ecs.Entity.Id,
};

pub const CanvasOptions = struct {
    z: f32 = 0.0,
};

pub const FrameOptions = struct {
    size: Box = .{},
    placement: Placement = .{},
};

pub const PanelOptions = struct {
    size: Box = .{},
    placement: Placement = .{},
    color: common.Color = common.Color.WHITE,
};

pub const LabelOptions = struct {
    content: []const u8,
    placement: Placement = .{},
    font_size: f32 = 32.0,
    color: common.Color = common.Color.WHITE,
    font_handle: ?render.FontHandle = null,
    horizontal_alignment: ?render.HorizontalAlignment = null,
    vertical_alignment: ?render.VerticalAlignment = null,
};

pub const BuilderOptions = struct {
    font_handle: ?render.FontHandle = null,
};

pub fn Builder(comptime Defaults: anytype) type {
    return struct {
        commands: *ecs.Commands,
        options: BuilderOptions,

        const Self = @This();

        pub fn init(commands: *ecs.Commands, options: BuilderOptions) Self {
            return .{
                .commands = commands,
                .options = options,
            };
        }

        pub fn canvas(self: *Self, options: CanvasOptions) !Node {
            return self.canvasWith(options, .{});
        }

        pub fn canvasWith(self: *Self, options: CanvasOptions, extras: anytype) !Node {
            const entity = try self.commands.createEntity(.{
                common.Transform{},
                CanvasRoot{ .z = options.z },
                Box{},
            });
            try self.addDefaultComponents(entity);
            try self.addExtraComponents(entity, extras);
            return .{ .entity = entity };
        }

        pub fn frame(self: *Self, parent: Node, options: FrameOptions) !Node {
            return self.frameWith(parent, options, .{});
        }

        pub fn frameWith(self: *Self, parent: Node, options: FrameOptions, extras: anytype) !Node {
            const entity = try self.commands.createEntity(.{
                common.Parent{
                    .id = parent.entity,
                    .inherit_translation = false,
                    .inherit_rotation = false,
                    .inherit_scale = false,
                },
                common.Transform{},
                Box{
                    .width = options.size.width,
                    .height = options.size.height,
                },
                options.placement,
            });
            try self.addDefaultComponents(entity);
            try self.addExtraComponents(entity, extras);
            return .{ .entity = entity };
        }

        pub fn panel(self: *Self, parent: Node, options: PanelOptions) !Node {
            return self.panelWith(parent, options, .{});
        }

        pub fn panelWith(self: *Self, parent: Node, options: PanelOptions, extras: anytype) !Node {
            const entity = try self.commands.createEntity(.{
                common.Parent{
                    .id = parent.entity,
                    .inherit_translation = false,
                    .inherit_rotation = false,
                    .inherit_scale = false,
                },
                common.Transform{},
                Box{
                    .width = options.size.width,
                    .height = options.size.height,
                },
                options.placement,
                render.Sprite{
                    .size_mode = .{ .Manual = .{ .width = options.size.width, .height = options.size.height } },
                    .color = options.color,
                },
            });
            try self.addDefaultComponents(entity);
            try self.addExtraComponents(entity, extras);
            return .{ .entity = entity };
        }

        pub fn label(self: *Self, parent: Node, options: LabelOptions) !Node {
            return self.labelWith(parent, options, .{});
        }

        pub fn labelWith(self: *Self, parent: Node, options: LabelOptions, extras: anytype) !Node {
            const entity = try self.commands.createEntity(.{
                common.Parent{
                    .id = parent.entity,
                    .inherit_translation = false,
                    .inherit_rotation = false,
                    .inherit_scale = false,
                },
                common.Transform{},
                options.placement,
                render.Text{
                    .content = options.content,
                    .font_size = options.font_size,
                    .color = options.color,
                    .horizontal_alignment = options.horizontal_alignment orelse horizontalAlignmentForAnchor(options.placement.self_anchor),
                    .vertical_alignment = options.vertical_alignment orelse verticalAlignmentForAnchor(options.placement.self_anchor),
                    .font_handle = options.font_handle orelse self.options.font_handle,
                },
            });
            try self.addDefaultComponents(entity);
            try self.addExtraComponents(entity, extras);
            return .{ .entity = entity };
        }

        pub fn child(self: *Self, parent: Node) Scope(Defaults) {
            return .{
                .builder = self,
                .parent = parent,
            };
        }

        fn addDefaultComponents(self: *Self, entity: ecs.Entity.Id) !void {
            if (comptime tupleLen(@TypeOf(Defaults)) == 0) return;
            try self.commands.addComponents(entity, Defaults);
        }

        fn addExtraComponents(self: *Self, entity: ecs.Entity.Id, extras: anytype) !void {
            if (comptime tupleLen(@TypeOf(extras)) == 0) return;
            try self.commands.addComponents(entity, extras);
        }
    };
}

pub fn Scope(comptime Defaults: anytype) type {
    return struct {
        builder: *Builder(Defaults),
        parent: Node,

        const Self = @This();

        pub fn frame(self: Self, options: FrameOptions) !Node {
            return self.builder.frame(self.parent, options);
        }

        pub fn frameWith(self: Self, options: FrameOptions, extras: anytype) !Node {
            return self.builder.frameWith(self.parent, options, extras);
        }

        pub fn panel(self: Self, options: PanelOptions) !Node {
            return self.builder.panel(self.parent, options);
        }

        pub fn panelWith(self: Self, options: PanelOptions, extras: anytype) !Node {
            return self.builder.panelWith(self.parent, options, extras);
        }

        pub fn label(self: Self, options: LabelOptions) !Node {
            return self.builder.label(self.parent, options);
        }

        pub fn labelWith(self: Self, options: LabelOptions, extras: anytype) !Node {
            return self.builder.labelWith(self.parent, options, extras);
        }

        pub fn child(self: Self, parent: Node) Scope(Defaults) {
            return self.builder.child(parent);
        }
    };
}

pub fn anchorPoint(box: Box, anchor: Anchor) common.Vec2 {
    return .{
        .x = switch (anchor) {
            .TopLeft, .CenterLeft, .BottomLeft => -box.width * 0.5,
            .TopCenter, .Center, .BottomCenter => 0.0,
            .TopRight, .CenterRight, .BottomRight => box.width * 0.5,
        },
        .y = switch (anchor) {
            .TopLeft, .TopCenter, .TopRight => -box.height * 0.5,
            .CenterLeft, .Center, .CenterRight => 0.0,
            .BottomLeft, .BottomCenter, .BottomRight => box.height * 0.5,
        },
    };
}

pub fn horizontalAlignmentForAnchor(anchor: Anchor) render.HorizontalAlignment {
    return switch (anchor) {
        .TopLeft, .CenterLeft, .BottomLeft => .Left,
        .TopCenter, .Center, .BottomCenter => .Center,
        .TopRight, .CenterRight, .BottomRight => .Right,
    };
}

pub fn verticalAlignmentForAnchor(anchor: Anchor) render.VerticalAlignment {
    return switch (anchor) {
        .TopLeft, .TopCenter, .TopRight => .Top,
        .CenterLeft, .Center, .CenterRight => .Center,
        .BottomLeft, .BottomCenter, .BottomRight => .Bottom,
    };
}

fn tupleLen(comptime T: type) usize {
    const info = @typeInfo(T);
    return switch (info) {
        .@"struct" => |s| if (s.is_tuple) s.fields.len else @compileError("GUI extras/defaults must be tuples like .{ Tag{} }"),
        else => @compileError("GUI extras/defaults must be tuples like .{ Tag{} }"),
    };
}
