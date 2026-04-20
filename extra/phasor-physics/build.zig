const std = @import("std");
const jolt_sources = @import("jolt_sources.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const phasor_dep = b.dependency("phasor", .{
        .target = target,
        .optimize = optimize,
    });
    const jolt_dep = b.dependency("jolt", .{
        .target = target,
        .optimize = optimize,
    });
    const is_wasm = target.result.cpu.arch.isWasm();
    const common = phasor_dep.module("common");
    const ecs = phasor_dep.module("ecs");
    const physics_fps_support = phasor_dep.module("physics_fps_support");

    const physics = b.createModule(.{
        .root_source_file = b.path("lib/physics/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = common },
            .{ .name = "ecs", .module = ecs },
        },
    });
    if (!is_wasm) {
        addJoltSources(b, jolt_dep, physics);
    }

    const fps_physics = b.createModule(.{
        .root_source_file = b.path("lib/modules/FpsPhysicsModule.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = common },
            .{ .name = "ecs", .module = ecs },
            .{ .name = "physics_fps_support", .module = physics_fps_support },
            .{ .name = "physics", .module = physics },
        },
    });
    const fps_key_binding = b.createModule(.{
        .root_source_file = b.path("lib/modules/FpsKeyBindingModule.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ecs", .module = ecs },
            .{ .name = "physics_fps_support", .module = physics_fps_support },
            .{ .name = "fps_physics", .module = fps_physics },
        },
    });

    const phasor_physics = b.addModule("phasor_physics", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "physics", .module = physics },
        },
    });
    const phasor_physics_fps = b.addModule("phasor_physics_fps", .{
        .root_source_file = b.path("fps.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fps_physics", .module = fps_physics },
            .{ .name = "fps_key_binding", .module = fps_key_binding },
        },
    });

    const test_step = b.step("test", "Run phasor_physics tests");
    const physics_tests = b.addTest(.{ .root_module = physics });
    const run_physics_tests = b.addRunArtifact(physics_tests);
    test_step.dependOn(&run_physics_tests.step);

    const package_tests = b.addTest(.{ .root_module = phasor_physics });
    const run_package_tests = b.addRunArtifact(package_tests);
    test_step.dependOn(&run_package_tests.step);

    const fps_package_tests = b.addTest(.{ .root_module = phasor_physics_fps });
    const run_fps_package_tests = b.addRunArtifact(fps_package_tests);
    test_step.dependOn(&run_fps_package_tests.step);
}

fn addJoltSources(
    b: *std.Build,
    jolt_dep: *std.Build.Dependency,
    module: *std.Build.Module,
) void {
    module.addIncludePath(jolt_dep.path(""));
    module.addIncludePath(b.path("../../deps/physics_jolt_c"));
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
        .root = b.path("../.."),
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
