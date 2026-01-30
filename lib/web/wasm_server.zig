const std = @import("std");
const builtin = @import("builtin");

const http = std.http;
const net = std.Io.net;

pub const Options = struct {
    root_dir: []const u8 = "zig-out/web",
    index_file: []const u8 = "index.html",
    host: []const u8 = "127.0.0.1",
    port: u16 = 0,
    open_browser: bool = true,
};

pub fn main(init: std.process.Init) !void {
    var options = Options{};
    parseArgs(init, &options) catch |err| {
        if (err == error.InvalidArguments) return;
        return err;
    };
    try serve(init, options);
}

pub fn serve(init: std.process.Init, options: Options) !void {
    var address = try net.IpAddress.parse(options.host, options.port);
    var server = try address.listen(init.io, .{ .reuse_address = true });
    defer server.deinit(init.io);

    const url = try std.fmt.allocPrint(init.gpa, "http://{f}/", .{server.socket.address});
    defer init.gpa.free(url);

    std.debug.print("Serving {s} at {s}\n", .{ options.root_dir, url });
    if (options.open_browser) {
        openBrowser(init, url) catch |err| {
            std.debug.print("Failed to open browser: {s}\n", .{@errorName(err)});
        };
    }

    const root_dir = try std.Io.Dir.openDir(.cwd(), init.io, options.root_dir, .{});
    defer root_dir.close(init.io);

    while (true) {
        const stream = server.accept(init.io) catch |err| {
            std.debug.print("Accept failed: {s}\n", .{@errorName(err)});
            continue;
        };
        handleConnection(init, root_dir, stream, options.index_file) catch |err| {
            std.debug.print("Connection error: {s}\n", .{@errorName(err)});
        };
    }
}

fn handleConnection(
    init: std.process.Init,
    root_dir: std.Io.Dir,
    stream: net.Stream,
    index_file: []const u8,
) !void {
    defer {
        var copy = stream;
        copy.close(init.io);
    }

    var send_buffer: [8192]u8 = undefined;
    var recv_buffer: [8192]u8 = undefined;
    var connection_reader = stream.reader(init.io, &recv_buffer);
    var connection_writer = stream.writer(init.io, &send_buffer);
    var server: http.Server = .init(&connection_reader.interface, &connection_writer.interface);

    var request = server.receiveHead() catch |err| switch (err) {
        error.HttpConnectionClosing => return,
        else => return err,
    };
    try serveRequest(init, root_dir, &request, index_file);
}

fn serveRequest(
    init: std.process.Init,
    root_dir: std.Io.Dir,
    request: *http.Server.Request,
    index_file: []const u8,
) !void {
    const target = request.head.target;
    const path_end = std.mem.indexOfScalar(u8, target, '?') orelse target.len;
    const raw_path = target[0..path_end];
    const rel_path = normalizePath(raw_path, index_file) orelse {
        try respondWithStatus(request, "Bad Request", .bad_request);
        return;
    };

    var file = std.Io.Dir.openFile(root_dir, init.io, rel_path, .{}) catch {
        try respondWithStatus(request, "Not Found", .not_found);
        return;
    };
    defer file.close(init.io);

    const max_bytes = 32 * 1024 * 1024;
    const stat = try file.stat(init.io);
    if (stat.size > max_bytes) return error.FileTooLarge;
    const data = try init.gpa.alloc(u8, @intCast(stat.size));
    defer init.gpa.free(data);
    const read_len = try file.readPositionalAll(init.io, data, 0);
    if (read_len != data.len) return error.EndOfStream;

    const content_type = guessContentType(rel_path);
    const headers = [_]http.Header{
        .{ .name = "content-type", .value = content_type },
        .{ .name = "cache-control", .value = "no-store, no-cache, must-revalidate, max-age=0" },
        .{ .name = "pragma", .value = "no-cache" },
        .{ .name = "expires", .value = "0" },
        .{ .name = "connection", .value = "close" },
    };

    try request.respond(data, .{
        .extra_headers = &headers,
    });
}

fn respondWithStatus(request: *http.Server.Request, message: []const u8, status: http.Status) !void {
    const headers = [_]http.Header{
        .{ .name = "cache-control", .value = "no-store, no-cache, must-revalidate, max-age=0" },
        .{ .name = "pragma", .value = "no-cache" },
        .{ .name = "expires", .value = "0" },
        .{ .name = "connection", .value = "close" },
    };
    try request.respond(message, .{
        .status = status,
        .extra_headers = &headers,
    });
}

fn normalizePath(path: []const u8, index_file: []const u8) ?[]const u8 {
    if (path.len == 0 or std.mem.eql(u8, path, "/")) {
        return index_file;
    }
    if (path[0] != '/') {
        return null;
    }
    const trimmed = path[1..];
    if (trimmed.len == 0) {
        return index_file;
    }
    if (std.mem.indexOf(u8, trimmed, "..") != null) {
        return null;
    }
    return trimmed;
}

fn guessContentType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".js")) return "text/javascript; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".wasm")) return "application/wasm";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, path, ".png")) return "image/png";
    if (std.mem.endsWith(u8, path, ".jpg")) return "image/jpeg";
    return "application/octet-stream";
}

fn openBrowser(init: std.process.Init, url: []const u8) !void {
    const argv = switch (builtin.os.tag) {
        .macos => &.{ "open", url },
        .windows => &.{ "cmd", "/c", "start", "", url },
        else => &.{ "xdg-open", url },
    };

    var child = try std.process.spawn(init.io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    _ = child.wait(init.io) catch {};
}

fn parseArgs(init: std.process.Init, options: *Options) !void {
    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    _ = it.skip();

    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--root")) {
            const value = nextArg(&it) orelse return error.InvalidArguments;
            options.root_dir = try init.gpa.dupe(u8, value);
        } else if (std.mem.eql(u8, arg, "--index")) {
            const value = nextArg(&it) orelse return error.InvalidArguments;
            options.index_file = try init.gpa.dupe(u8, value);
        } else if (std.mem.eql(u8, arg, "--host")) {
            const value = nextArg(&it) orelse return error.InvalidArguments;
            options.host = try init.gpa.dupe(u8, value);
        } else if (std.mem.eql(u8, arg, "--port")) {
            const port_str = nextArg(&it) orelse return error.InvalidArguments;
            options.port = std.fmt.parseInt(u16, port_str, 10) catch return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--no-open")) {
            options.open_browser = false;
        } else if (std.mem.eql(u8, arg, "--help")) {
            printUsage();
            return error.InvalidArguments;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            printUsage();
            return error.InvalidArguments;
        }
    }
}

fn nextArg(it: *std.process.Args.Iterator) ?[]const u8 {
    return it.next() orelse null;
}

fn printUsage() void {
    std.debug.print(
        "wasm-server [--root DIR] [--index FILE] [--host ADDR] [--port N] [--no-open]\n",
        .{},
    );
}
