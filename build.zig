const std = @import("std");
const build_deps = @import("build_deps.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ctx = build_deps.BuildContext.init(b, target, optimize);
    const is_wasm = ctx.target.result.cpu.arch.isWasm();
    const engine = build_deps.buildEngine(&ctx);

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
            engine.particles.tests,
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
            engine.particles.tests,
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
}
