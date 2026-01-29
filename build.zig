const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ctx = BuildContext.init(b, target, optimize);

    const db = DbModule.build(&ctx);
    const graph = GraphModule.build(&ctx);
    const ecs = EcsModule.build(&ctx, .{
        .db = db.module,
        .graph = graph.module,
    });
    const metrics = MetricsModule.build(&ctx);
    const modules = ModulesModule.build(&ctx, .{
        .db = db.module,
        .ecs = ecs.module,
        .metrics = metrics.module,
    });
    const phasor = PhasorModule.build(&ctx, .{
        .db = db.module,
        .ecs = ecs.module,
        .graph = graph.module,
        .metrics = metrics.module,
        .modules = modules.module,
    });

    const exe_mod = ctx.module("examples/ecs/main.zig", &.{.{
        .name = "phasor",
        .module = phasor.module,
    }});

    const exe = b.addExecutable(.{
        .name = "phasor",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const test_step = b.step("test", "Run tests");
    addModuleTests(b, test_step, &.{
        db.tests,
        ecs.tests,
        graph.tests,
        metrics.tests,
        modules.tests,
        phasor.tests,
    });

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    test_step.dependOn(&run_exe_tests.step);
}

const BuildContext = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    fn init(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildContext {
        return .{
            .b = b,
            .target = target,
            .optimize = optimize,
        };
    }

    fn module(self: *const BuildContext, root: []const u8, imports: []const std.Build.Module.Import) *std.Build.Module {
        return self.b.createModule(.{
            .root_source_file = self.b.path(root),
            .target = self.target,
            .optimize = self.optimize,
            .imports = imports,
        });
    }

    fn moduleBundle(self: *const BuildContext, root: []const u8, imports: []const std.Build.Module.Import) ModuleBundle {
        const mod = self.module(root, imports);
        return .{
            .module = mod,
            .tests = self.b.addTest(.{ .root_module = mod }),
        };
    }
};

const ModuleBundle = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,
};

const DbModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    fn build(ctx: *const BuildContext) DbModule {
        const bundle = ctx.moduleBundle("lib/db/root.zig", &.{});
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const EcsModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        db: *std.Build.Module,
        graph: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) EcsModule {
        const bundle = ctx.moduleBundle("lib/ecs/root.zig", &.{
            .{ .name = "db", .module = deps.db },
            .{ .name = "graph", .module = deps.graph },
        });
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const GraphModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    fn build(ctx: *const BuildContext) GraphModule {
        const bundle = ctx.moduleBundle("lib/graph/root.zig", &.{});
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const MetricsModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    fn build(ctx: *const BuildContext) MetricsModule {
        const bundle = ctx.moduleBundle("lib/metrics/root.zig", &.{});
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const ModulesModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        db: *std.Build.Module,
        ecs: *std.Build.Module,
        metrics: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) ModulesModule {
        const bundle = ctx.moduleBundle("lib/modules/root.zig", &.{
            .{ .name = "db", .module = deps.db },
            .{ .name = "ecs", .module = deps.ecs },
            .{ .name = "metrics", .module = deps.metrics },
        });
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const PhasorModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        db: *std.Build.Module,
        ecs: *std.Build.Module,
        graph: *std.Build.Module,
        metrics: *std.Build.Module,
        modules: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) PhasorModule {
        const bundle = ctx.moduleBundle("src/root.zig", &.{
            .{ .name = "db", .module = deps.db },
            .{ .name = "ecs", .module = deps.ecs },
            .{ .name = "graph", .module = deps.graph },
            .{ .name = "metrics", .module = deps.metrics },
            .{ .name = "modules", .module = deps.modules },
        });
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

fn addModuleTests(
    b: *std.Build,
    test_step: *std.Build.Step,
    tests: []const *std.Build.Step.Compile,
) void {
    for (tests) |test_exe| {
        const run = b.addRunArtifact(test_exe);
        test_step.dependOn(&run.step);
    }
}
