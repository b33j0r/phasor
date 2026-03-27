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

pub const managed_child_projects = [_]ManagedChildProject{
    .{
        .name = "ecs",
        .dir = "examples/ecs",
        .enable_wasm = false,
    },
    .{
        .name = "window",
        .dir = "examples/window",
        .enable_wasm = false,
    },
    .{
        .name = "triangle",
        .dir = "examples/triangle",
        .enable_wasm = true,
    },
    .{
        .name = "bouncing-ball",
        .dir = "examples/bouncing-ball",
        .enable_wasm = true,
    },
    .{
        .name = "particles",
        .dir = "examples/particles",
        .enable_wasm = true,
    },
    .{
        .name = "cube",
        .dir = "examples/cube",
        .enable_wasm = true,
    },
    .{
        .name = "physics-cubes",
        .dir = "examples/physics-cubes",
        .enable_wasm = true,
    },
    .{
        .name = "gltf",
        .dir = "examples/gltf",
        .enable_wasm = true,
    },
    .{
        .name = "warehouse",
        .dir = "examples/warehouse",
        .enable_wasm = true,
    },
    .{
        .name = "shadows",
        .dir = "examples/shadows",
        .enable_wasm = true,
    },
    .{
        .name = "sponza",
        .dir = "examples/sponza",
        .enable_wasm = false,
        .extra_steps = &.{
            .{
                .step_name = "fetch-sponza",
                .description = "Download the Sponza glTF sample into examples/sponza/assets",
                .child_args = &.{ "build", "fetch-sponza" },
            },
        },
    },
};

pub fn addManagedChildProjects(b: *std.Build, projects: []const ManagedChildProject) *std.Build.Step {
    const web_examples_step = b.step(
        "web-examples",
        "Build every wasm-capable example web bundle used by the docs site",
    );

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
            const web_step_name = b.fmt("web-{s}", .{project.name});
            addForwardedExampleStep(
                b,
                web_step_name,
                b.fmt("Build the {s} web bundle", .{project.name}),
                &.{ "build", "web" },
                project.dir,
            );
            web_examples_step.dependOn(&b.top_level_steps.get(web_step_name).?.step);
            addForwardedExampleRunStep(
                b,
                b.fmt("run-{s}-wasm", .{project.name}),
                b.fmt("Run the {s} wasm example", .{project.name}),
                project.name,
                true,
            );
        }
    }

    return web_examples_step;
}
