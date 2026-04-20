const std = @import("std");
const build_deps = @import("build_deps.zig");
const build_examples = @import("build_examples.zig");
const build_docs = @import("build_docs.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ctx = build_deps.BuildContext.init(b, target, optimize);
    const is_wasm = ctx.target.result.cpu.arch.isWasm();
    const engine = build_deps.buildEngine(&ctx);

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
            engine.physics_fps_support.tests,
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
            engine.physics_fps_support.tests,
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
