const std = @import("std");

pub fn build(b: *std.Build) void {
    const native_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const phasor_dep = b.dependency("phasor", .{
        .target = native_target,
        .optimize = optimize,
    });
    const phasor = phasor_dep.module("phasor");

    const app_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "phasor",
                .module = phasor,
            },
        }
    });

    const app_exe = b.addExecutable(.{
        .name = "ball",
        .root_module = app_mod,
    });
    b.installArtifact(app_exe);

    const run_cmd = b.addRunArtifact(app_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the ball example");
    run_step.dependOn(&run_cmd.step);
}
