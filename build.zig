const std = @import("std");
const build_deps = @import("build_deps.zig");
const build_examples = @import("build_examples.zig");
const build_docs = @import("build_docs.zig");
const jolt_sources = @import("extra/phasor-physics/jolt_sources.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ctx = build_deps.BuildContext.init(b, target, optimize);
    const is_wasm = ctx.target.result.cpu.arch.isWasm();
    const engine = build_deps.buildEngine(&ctx);
    _ = addPhasorPhysicsModule(b, target, optimize, engine.phasor.module);

    const exe_mod = ctx.module("examples/ecs/main.zig", &.{.{
        .name = "phasor",
        .module = engine.phasor.module,
    }});
    const exe = b.addExecutable(.{
        .name = "phasor",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const build_wasm_examples_step = build_examples.addManagedChildProjects(ctx.b, &build_examples.managed_child_projects);
    build_examples.addEcsQueryCacheBenchmark(&ctx, engine.phasor.module);

    build_docs.addDocsSiteSteps(b, build_wasm_examples_step);

    const test_step = b.step("test", "Run tests");
    const test_slow_step = b.step("test-slow", "Run tests including slow dependency suites");
    if (is_wasm) {
        build_deps.addModuleTests(b, test_step, &.{
            engine.common.tests,
            engine.db.tests,
            engine.ecs.tests,
            engine.graph.tests,
            engine.lighting.tests,
            engine.stb.tests,
            engine.stb_image.tests,
            engine.cgltf.tests,
            engine.metrics.tests,
            engine.audio.tests,
            engine.modules.tests,
            engine.platform.tests,
            engine.renderer.tests,
            engine.assets.tests,
            engine.phasor.tests,
            engine.wasm_support.tests,
        });
    } else {
        build_deps.addModuleTests(b, test_step, &.{
            engine.common.tests,
            engine.db.tests,
            engine.ecs.tests,
            engine.graph.tests,
            engine.lighting.tests,
            engine.glfw.?.tests,
            engine.stb.tests,
            engine.stb_image.tests,
            engine.cgltf.tests,
            engine.metrics.tests,
            engine.audio.tests,
            engine.modules.tests,
            engine.platform.tests,
            engine.renderer.tests,
            engine.assets.tests,
            engine.phasor.tests,
            engine.wasm_support.tests,
            engine.window.?.tests,
        });
    }
    test_slow_step.dependOn(test_step);
    build_deps.addModuleTests(b, test_slow_step, &.{engine.fastnoise.tests});

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    test_step.dependOn(&run_exe_tests.step);
}

fn addPhasorPhysicsModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    phasor_module: *std.Build.Module,
) *std.Build.Module {
    const is_wasm = target.result.cpu.arch.isWasm();
    const jolt_dep = if (!is_wasm) b.dependency("jolt", .{
        .target = target,
        .optimize = optimize,
    }) else null;

    const physics = b.createModule(.{
        .root_source_file = b.path("lib/physics/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "phasor", .module = phasor_module }},
    });
    if (jolt_dep) |dep| {
        addJoltSources(b, dep, physics);
    }

    const fps_physics = b.createModule(.{
        .root_source_file = b.path("lib/modules/FpsPhysicsModule.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor", .module = phasor_module },
            .{ .name = "physics", .module = physics },
        },
    });
    const fps_key_binding = b.createModule(.{
        .root_source_file = b.path("lib/modules/FpsKeyBindingModule.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "phasor", .module = phasor_module },
            .{ .name = "fps_physics", .module = fps_physics },
        },
    });

    return b.addModule("phasor_physics", .{
        .root_source_file = b.path("extra/phasor-physics/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "physics", .module = physics },
            .{ .name = "fps_physics", .module = fps_physics },
            .{ .name = "fps_key_binding", .module = fps_key_binding },
        },
    });
}

fn addJoltSources(
    b: *std.Build,
    jolt_dep: *std.Build.Dependency,
    module: *std.Build.Module,
) void {
    module.addIncludePath(jolt_dep.path(""));
    module.addIncludePath(b.path("deps/physics_jolt_c"));
    module.linkSystemLibrary("c++", .{});
    module.addCSourceFiles(.{
        .root = jolt_dep.path(""),
        .files = jolt_sources.files,
        .flags = &.{
            "-std=c++17",
            "-DJPH_OBJECT_LAYER_BITS=32",
            "-DJPH_USE_STD_VECTOR",
            "-DCPP_EXCEPTIONS_ENABLED=0",
            "-DCPP_RTTI_ENABLED=0",
        },
        .language = .cpp,
    });
    module.addCSourceFiles(.{
        .root = b.path(""),
        .files = &.{"deps/physics_jolt_c/physics_jolt_c.cpp"},
        .flags = &.{
            "-std=c++17",
            "-DJPH_OBJECT_LAYER_BITS=32",
            "-DJPH_USE_STD_VECTOR",
            "-DCPP_EXCEPTIONS_ENABLED=0",
            "-DCPP_RTTI_ENABLED=0",
        },
        .language = .cpp,
    });
}
