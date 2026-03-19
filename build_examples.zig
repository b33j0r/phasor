const std = @import("std");
const build_deps = @import("build_deps.zig");

pub const BuildContext = build_deps.BuildContext;

pub fn addEcsQueryCacheBenchmark(
    ctx: *const BuildContext,
    phasor_module: *std.Build.Module,
) void {
    const bench_mod = ctx.module("examples/ecs/query_cache_bench.zig", &.{.{
        .name = "phasor",
        .module = phasor_module,
    }});
    const bench_exe = ctx.b.addExecutable(.{
        .name = "ecs-query-cache-bench",
        .root_module = bench_mod,
    });
    const bench_run = ctx.b.addRunArtifact(bench_exe);
    const bench_step = ctx.b.step(
        "bench-ecs-query-cache",
        "Benchmark ECS query-plan caching (fails when speedup is too small)",
    );
    bench_step.dependOn(&bench_run.step);
}

fn addForwardedExampleRunStep(
    b: *std.Build,
    step_name: []const u8,
    description: []const u8,
    example_name: []const u8,
    wasm: bool,
) void {
    var command = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "run",
        "examples.zig",
        "--",
        example_name,
    });
    command.setCwd(b.path("."));
    if (wasm) {
        command.addArg("--wasm");
    }
    if (b.args) |args| {
        command.addArg("--");
        command.addArgs(args);
    }

    const step = b.step(step_name, description);
    step.dependOn(&command.step);
}

fn addForwardedExampleStep(
    b: *std.Build,
    step_name: []const u8,
    description: []const u8,
    child_args: []const []const u8,
    example_dir: []const u8,
) void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(b.allocator);
    argv.append(b.allocator, b.graph.zig_exe) catch unreachable;
    argv.appendSlice(b.allocator, child_args) catch unreachable;
    if (b.args) |args| {
        argv.append(b.allocator, "--") catch unreachable;
        argv.appendSlice(b.allocator, args) catch unreachable;
    }

    const command = b.addSystemCommand(argv.items);
    command.setCwd(b.path(example_dir));

    const step = b.step(step_name, description);
    step.dependOn(&command.step);
}

pub const ManagedChildStep = struct {
    step_name: []const u8,
    description: []const u8,
    child_args: []const []const u8,
};

pub const ManagedChildProject = struct {
    name: []const u8,
    dir: []const u8,
    enable_wasm: bool,
    extra_steps: []const ManagedChildStep = &.{},
};

pub fn addManagedChildProjects(b: *std.Build, projects: []const ManagedChildProject) void {
    for (projects) |project| {
        for (project.extra_steps) |extra_step| {
            addForwardedExampleStep(
                b,
                extra_step.step_name,
                extra_step.description,
                extra_step.child_args,
                project.dir,
            );
        }

        addForwardedExampleRunStep(
            b,
            b.fmt("run-{s}", .{project.name}),
            b.fmt("Run the {s} example", .{project.name}),
            project.name,
            false,
        );
        addForwardedExampleRunStep(
            b,
            b.fmt("run-{s}-native", .{project.name}),
            b.fmt("Run the {s} example natively", .{project.name}),
            project.name,
            false,
        );

        if (project.enable_wasm) {
            addForwardedExampleStep(
                b,
                b.fmt("web-{s}", .{project.name}),
                b.fmt("Build the {s} web bundle", .{project.name}),
                &.{ "build", "web" },
                project.dir,
            );
            addForwardedExampleRunStep(
                b,
                b.fmt("run-{s}-wasm", .{project.name}),
                b.fmt("Run the {s} wasm example", .{project.name}),
                project.name,
                true,
            );
        }
    }
}
