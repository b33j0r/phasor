const std = @import("std");

const sponza_api_url = "https://api.github.com/repos/KhronosGroup/glTF-Sample-Assets/contents/Models/Sponza/glTF?ref=main";
const sponza_cache_dir = "local/cache/sponza/source/Models/Sponza/glTF";
const user_agent = "phasor-lite-fetch-sponza";

const ApiEntry = struct {
    name: []const u8,
    type: []const u8,
    download_url: ?[]const u8 = null,
};

const Options = struct {
    refresh: bool = false,
};

pub fn main(init: std.process.Init) !void {
    var options = Options{};
    if (!try parseArgs(init, &options)) return;

    try std.Io.Dir.cwd().createDirPath(init.io, sponza_cache_dir);

    var client: std.http.Client = .{
        .allocator = init.gpa,
        .io = init.io,
    };
    defer client.deinit();

    const entries = try fetchManifest(init, &client);
    defer entries.deinit();

    var downloaded: usize = 0;
    var skipped: usize = 0;
    for (entries.value) |entry| {
        if (!std.mem.eql(u8, entry.type, "file")) continue;
        const source_url = entry.download_url orelse continue;
        const dest_path = try std.fmt.allocPrint(init.gpa, "{s}/{s}", .{ sponza_cache_dir, entry.name });
        defer init.gpa.free(dest_path);

        if (!options.refresh and fileExists(init, dest_path)) {
            skipped += 1;
            continue;
        }

        try downloadFile(init, &client, source_url, dest_path);
        downloaded += 1;
        std.log.info("fetched {s}", .{entry.name});
    }

    std.log.info(
        "Sponza cache ready at {s} (downloaded={}, skipped={})",
        .{ sponza_cache_dir, downloaded, skipped },
    );
}

fn parseArgs(init: std.process.Init, out: *Options) !bool {
    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    _ = it.skip();

    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--refresh")) {
            out.refresh = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            printUsage();
            return false;
        } else {
            return invalidArguments("unknown argument");
        }
    }

    return true;
}

fn invalidArguments(message: []const u8) error{InvalidArguments}!bool {
    std.log.err("{s}", .{message});
    printUsage();
    return error.InvalidArguments;
}

fn printUsage() void {
    std.debug.print(
        \\Usage: zig build fetch-sponza [--refresh]
        \\  --refresh  Re-download files even if they already exist in the local cache.
        ,
        .{},
    );
}

fn fetchManifest(
    init: std.process.Init,
    client: *std.http.Client,
) !std.json.Parsed([]ApiEntry) {
    var manifest_bytes: std.ArrayList(u8) = .empty;
    errdefer manifest_bytes.deinit(init.gpa);

    var writer_alloc: std.Io.Writer.Allocating = .fromArrayList(init.gpa, &manifest_bytes);
    const result = try client.fetch(.{
        .location = .{ .url = sponza_api_url },
        .extra_headers = &.{
            .{ .name = "User-Agent", .value = user_agent },
            .{ .name = "Accept", .value = "application/vnd.github+json" },
        },
        .response_writer = &writer_alloc.writer,
    });
    if (result.status != .ok) return error.DownloadFailed;
    manifest_bytes = writer_alloc.toArrayList();
    defer manifest_bytes.deinit(init.gpa);

    return try std.json.parseFromSlice([]ApiEntry, init.gpa, manifest_bytes.items, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

fn downloadFile(
    init: std.process.Init,
    client: *std.http.Client,
    source_url: []const u8,
    dest_path: []const u8,
) !void {
    var file = try std.Io.Dir.cwd().createFile(init.io, dest_path, .{ .truncate = true });
    defer file.close(init.io);

    var file_buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(init.io, &file_buffer);
    const result = try client.fetch(.{
        .location = .{ .url = source_url },
        .extra_headers = &.{
            .{ .name = "User-Agent", .value = user_agent },
        },
        .response_writer = &file_writer.interface,
    });
    try file_writer.flush();
    if (result.status != .ok) {
        return error.DownloadFailed;
    }
}

fn fileExists(init: std.process.Init, path: []const u8) bool {
    std.Io.Dir.cwd().access(init.io, path, .{}) catch return false;
    return true;
}
