const std = @import("std");
const builtin = @import("builtin");

const http = std.http;
const net = std.Io.net;

pub const std_options: std.Options = .{
    .log_level = .info,
};

const default_https_cert = "local/tls/phasor.pem";
const default_https_key = "local/tls/phasor-key.pem";
const default_tls_proxy_script = "local/tls/tls_proxy.py";
const tls_proxy_source = @embedFile("tls_proxy.py");

pub const Options = struct {
    root_dir: []const u8 = "zig-out/web",
    index_file: []const u8 = "index.html",
    host: []const u8 = "127.0.0.1",
    port: u16 = 0,
    open_browser: bool = true,
    https: bool = false,
    https_host: ?[]const u8 = null,
    https_port: u16 = 8443,
    https_cert: []const u8 = default_https_cert,
    https_key: []const u8 = default_https_key,
    tls_proxy_script: ?[]const u8 = null,
};

pub fn main(init: std.process.Init) !void {
    var options = Options{};
    parseArgs(init, &options) catch |err| {
        if (err == error.InvalidArguments) return;
        return err;
    };
    validateOptions(init, &options) catch |err| {
        if (err == error.InvalidArguments) return;
        return err;
    };
    try serve(init, options);
}

pub fn serve(init: std.process.Init, options: Options) !void {
    var address = try net.IpAddress.parse(options.host, options.port);
    var server = try address.listen(init.io, .{ .reuse_address = true });
    defer server.deinit(init.io);

    const bound_address = server.socket.address;
    const http_url = try std.fmt.allocPrint(init.gpa, "http://{f}/", .{bound_address});
    defer init.gpa.free(http_url);

    log.info("serving {s} at {s}", .{ options.root_dir, http_url });

    var https_child: ?std.process.Child = null;
    defer if (https_child) |*child| child.kill(init.io);
    var https_url: ?[]const u8 = null;
    defer if (https_url) |url| init.gpa.free(url);

    if (options.https) {
        const https_host = options.https_host orelse options.host;
        const target_host = proxyTargetHost(options.host);
        https_child = spawnHttpsProxy(init, .{
            .listen_host = https_host,
            .listen_port = options.https_port,
            .target_host = target_host,
            .target_port = bound_address.getPort(),
            .cert_path = options.https_cert,
            .key_path = options.https_key,
            .script_path = options.tls_proxy_script,
        }) catch |err| {
            if (err == error.FileNotFound) {
                log.err("failed to start HTTPS proxy: python3 not found", .{});
            } else {
                log.err("failed to start HTTPS proxy: {s}", .{@errorName(err)});
            }
            return err;
        };
        https_url = try std.fmt.allocPrint(init.gpa, "https://{s}:{d}/", .{ https_host, options.https_port });
        log.info("HTTPS proxy at {s}", .{https_url.?});
    }

    if (options.open_browser) {
        const url = https_url orelse http_url;
        openBrowser(init, url) catch |err| {
            log.warn("failed to open browser: {s}", .{@errorName(err)});
        };
    }

    const root_dir = try std.Io.Dir.openDir(.cwd(), init.io, options.root_dir, .{});
    defer root_dir.close(init.io);

    while (true) {
        const stream = server.accept(init.io) catch |err| {
            log.err("accept failed: {s}", .{@errorName(err)});
            continue;
        };
        handleConnection(init, root_dir, stream, options.index_file) catch |err| {
            log.warn("connection error: {s}", .{@errorName(err)});
        };
    }
}

const HttpsProxyOptions = struct {
    listen_host: []const u8,
    listen_port: u16,
    target_host: []const u8,
    target_port: u16,
    cert_path: []const u8,
    key_path: []const u8,
    script_path: ?[]const u8 = null,
};

fn spawnHttpsProxy(init: std.process.Init, options: HttpsProxyOptions) !std.process.Child {
    const script_path = options.script_path orelse default_tls_proxy_script;
    if (options.script_path == null) {
        try ensureBundledTlsProxyScript(init, script_path);
    }

    const listen_port = try std.fmt.allocPrint(init.gpa, "{d}", .{options.listen_port});
    defer init.gpa.free(listen_port);
    const target_port = try std.fmt.allocPrint(init.gpa, "{d}", .{options.target_port});
    defer init.gpa.free(target_port);

    const argv = [_][]const u8{
        "python3",
        script_path,
        "--listen-host",
        options.listen_host,
        "--listen-port",
        listen_port,
        "--target-host",
        options.target_host,
        "--target-port",
        target_port,
        "--cert",
        options.cert_path,
        "--key",
        options.key_path,
    };

    return std.process.spawn(init.io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    });
}

fn ensureBundledTlsProxyScript(init: std.process.Init, script_path: []const u8) !void {
    try ensureTlsDir(init);
    var file = try std.Io.Dir.cwd().createFile(init.io, script_path, .{ .truncate = true });
    defer file.close(init.io);
    try file.writeStreamingAll(init.io, tls_proxy_source);
}

fn proxyTargetHost(host: []const u8) []const u8 {
    if (std.mem.eql(u8, host, "0.0.0.0")) return "127.0.0.1";
    if (std.mem.eql(u8, host, "::")) return "::1";
    return host;
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

    const max_bytes = 128 * 1024 * 1024;
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
    if (std.mem.endsWith(u8, path, ".gltf")) return "model/gltf+json";
    if (std.mem.endsWith(u8, path, ".glb")) return "model/gltf-binary";
    if (std.mem.endsWith(u8, path, ".bin")) return "application/octet-stream";
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
        } else if (std.mem.eql(u8, arg, "--https")) {
            options.https = true;
        } else if (std.mem.eql(u8, arg, "--https-host")) {
            const value = nextArg(&it) orelse return error.InvalidArguments;
            options.https_host = try init.gpa.dupe(u8, value);
        } else if (std.mem.eql(u8, arg, "--https-port")) {
            const port_str = nextArg(&it) orelse return error.InvalidArguments;
            options.https_port = std.fmt.parseInt(u16, port_str, 10) catch return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--https-cert")) {
            const value = nextArg(&it) orelse return error.InvalidArguments;
            options.https_cert = try init.gpa.dupe(u8, value);
        } else if (std.mem.eql(u8, arg, "--https-key")) {
            const value = nextArg(&it) orelse return error.InvalidArguments;
            options.https_key = try init.gpa.dupe(u8, value);
        } else if (std.mem.eql(u8, arg, "--tls-proxy-script")) {
            const value = nextArg(&it) orelse return error.InvalidArguments;
            options.tls_proxy_script = try init.gpa.dupe(u8, value);
        } else if (std.mem.eql(u8, arg, "--no-open")) {
            options.open_browser = false;
        } else if (std.mem.eql(u8, arg, "--help")) {
            printUsage();
            return error.InvalidArguments;
        } else {
            log.err("unknown argument: {s}", .{arg});
            printUsage();
            return error.InvalidArguments;
        }
    }
}

fn nextArg(it: *std.process.Args.Iterator) ?[]const u8 {
    return it.next() orelse null;
}

fn validateOptions(init: std.process.Init, options: *Options) !void {
    if (!options.https) return;
    if (options.https_port == 0) {
        log.err("invalid --https-port: 0", .{});
        printUsage();
        return error.InvalidArguments;
    }
    ensureHttpsCerts(init, options) catch |err| {
        if (err == error.FileNotFound) {
            log.err("mkcert not found; install it or pass --https-cert/--https-key", .{});
            printUsage();
            return error.InvalidArguments;
        } else if (err == error.MkcertFailed) {
            log.err("mkcert failed; ensure its root CA is installed (mkcert -install)", .{});
            printUsage();
            return error.InvalidArguments;
        }
        return err;
    };
}

fn ensureHttpsCerts(init: std.process.Init, options: *Options) !void {
    if (fileExists(init, options.https_cert) and fileExists(init, options.https_key)) return;
    try ensureTlsDir(init);
    try runMkcert(init, options);
    if (!fileExists(init, options.https_cert) or !fileExists(init, options.https_key)) {
        log.err("missing TLS cert/key at {s} and {s}", .{
            options.https_cert,
            options.https_key,
        });
        return error.InvalidArguments;
    }
}

fn runMkcert(init: std.process.Init, options: *Options) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(init.gpa);
    var allocated: std.ArrayList([]const u8) = .empty;
    defer {
        for (allocated.items) |item| {
            init.gpa.free(item);
        }
        allocated.deinit(init.gpa);
    }

    try argv.append(init.gpa, "mkcert");
    try argv.append(init.gpa, "-cert-file");
    try argv.append(init.gpa, options.https_cert);
    try argv.append(init.gpa, "-key-file");
    try argv.append(init.gpa, options.https_key);

    try argv.append(init.gpa, "localhost");
    try argv.append(init.gpa, "127.0.0.1");
    try argv.append(init.gpa, "::1");

    if (options.https_host) |host| {
        if (!isWildcardHost(host)) try argv.append(init.gpa, host);
    }
    if (!isWildcardHost(options.host)) {
        try argv.append(init.gpa, options.host);
    }

    if (builtin.os.tag != .windows and builtin.os.tag != .wasi) {
        var host_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
        if (std.posix.gethostname(&host_buf)) |host| {
            if (host.len != 0) {
                try argv.append(init.gpa, host);
                if (std.mem.indexOfScalar(u8, host, '.') == null) {
                    const local_name = try std.fmt.allocPrint(init.gpa, "{s}.local", .{host});
                    try allocated.append(init.gpa, local_name);
                    try argv.append(init.gpa, local_name);
                }
            }
        } else |_| {}
    }

    var child = try std.process.spawn(init.io, .{
        .argv = argv.items,
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(init.io);
    switch (term) {
        .exited => |code| if (code != 0) return error.MkcertFailed,
        else => return error.MkcertFailed,
    }
}

fn ensureTlsDir(init: std.process.Init) !void {
    const argv = [_][]const u8{ "mkdir", "-p", "local/tls" };
    var child = try std.process.spawn(init.io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(init.io);
    switch (term) {
        .exited => |code| if (code != 0) return error.MkdirFailed,
        else => return error.MkdirFailed,
    }
}

fn fileExists(init: std.process.Init, path: []const u8) bool {
    const cwd = std.Io.Dir.cwd();
    const file = std.Io.Dir.openFile(cwd, init.io, path, .{}) catch return false;
    file.close(init.io);
    return true;
}

fn isWildcardHost(host: []const u8) bool {
    return std.mem.eql(u8, host, "0.0.0.0") or std.mem.eql(u8, host, "::");
}

fn printUsage() void {
    log.info(
        "wasm-server [--root DIR] [--index FILE] [--host ADDR] [--port N] [--no-open] [--https --https-host ADDR --https-port N --https-cert FILE --https-key FILE --tls-proxy-script FILE]",
        .{},
    );
}

const log = std.log.scoped(.wasm_server);
