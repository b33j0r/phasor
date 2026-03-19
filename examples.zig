const std = @import("std");

const Options = struct {
    name: ?[]const u8 = null,
    wasm: bool = false,
    help: bool = false,
    forward_args: []const []const u8 = &.{},
};

pub fn main(init: std.process.Init) !u8 {
    const options = try parseArgs(init);
    if (options.help or options.name == null) {
        printUsage();
        return if (options.help) 0 else 1;
    }

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(init.gpa);

    try argv.append(init.gpa, "zig");
    try argv.append(init.gpa, "build");
    try argv.append(init.gpa, if (options.wasm) "run-wasm" else "run");
    if (options.forward_args.len != 0) {
        try argv.append(init.gpa, "--");
        try argv.appendSlice(init.gpa, options.forward_args);
    }

    const example_dir = try std.fmt.allocPrint(init.gpa, "examples/{s}", .{options.name.?});
    defer init.gpa.free(example_dir);

    var child = try std.process.spawn(init.io, .{
        .argv = argv.items,
        .cwd = .{ .path = example_dir },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(init.io);
    return switch (term) {
        .exited => |code| code,
        else => 1,
    };
}

fn parseArgs(init: std.process.Init) !Options {
    var options = Options{};
    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    _ = it.skip();

    var forward_args: std.ArrayList([]const u8) = .empty;
    defer forward_args.deinit(init.gpa);

    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--")) {
            while (it.next()) |forward_arg| {
                try forward_args.append(init.gpa, forward_arg);
            }
            break;
        }
        if (std.mem.eql(u8, arg, "--wasm")) {
            options.wasm = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--help")) {
            options.help = true;
            continue;
        }
        if (options.name == null) {
            options.name = arg;
            continue;
        }
        return error.InvalidArguments;
    }

    options.forward_args = try forward_args.toOwnedSlice(init.gpa);
    return options;
}

fn printUsage() void {
    std.debug.print(
        \\Usage: zig run examples.zig -- <example-name> [--wasm] [-- <example args...>]
        \\  zig run examples.zig -- sponza
        \\  zig run examples.zig -- sponza --wasm
    ,
        .{},
    );
}
