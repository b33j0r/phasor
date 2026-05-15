const std = @import("std");

pub fn build(b: *std.Build) void {
    const host_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const phasor_dep = b.dependency("phasor", .{
        .target = host_target,
        .optimize = optimize,
    });
    const phasor = phasor_dep.module("phasor");

    const app_mod = b.createModule(.{
        .root_source_file = b.path("main2.zig"),
        .target = host_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "phasor",
                .module = phasor,
            },
        },
    });

    const app_exe = b.addExecutable(.{
        .name = "gltf",
        .root_module = app_mod,
    });
    b.installArtifact(app_exe);

    const run_cmd = b.addRunArtifact(app_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the glTF example");
    run_step.dependOn(&run_cmd.step);

    addWebBuild(b, host_target, optimize, phasor_dep);
}

fn addWebBuild(
    b: *std.Build,
    host_target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    phasor_dep: *std.Build.Dependency,
) void {
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });

    const wasm_phasor_dep = b.dependency("phasor", .{
        .target = wasm_target,
        .optimize = optimize,
    });
    const wasm_phasor = wasm_phasor_dep.module("phasor");

    const wasm_app_mod = b.createModule(.{
        .root_source_file = b.path("main2.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "phasor",
                .module = wasm_phasor,
            },
        },
    });
    const wasm_exe = b.addExecutable(.{
        .name = "gltf_web",
        .root_module = wasm_app_mod,
    });
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;

    const server_mod = b.createModule(.{
        .root_source_file = phasor_dep.path("lib/web/wasm_server.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    const server_exe = b.addExecutable(.{
        .name = "gltf_wasm_server",
        .root_module = server_mod,
    });
    b.installArtifact(server_exe);

    const web_dir = "web/gltf";
    const install_wasm = b.addInstallFile(wasm_exe.getEmittedBin(), b.fmt("{s}/app.wasm", .{web_dir}));
    const install_html = b.addInstallFile(phasor_dep.path("assets/web/index.html"), b.fmt("{s}/index.html", .{web_dir}));
    const install_webgpu = b.addInstallFile(phasor_dep.path("assets/web/webgpu.js"), b.fmt("{s}/webgpu.js", .{web_dir}));
    const install_jolt_bridge = b.addInstallFile(phasor_dep.path("assets/web/jolt_bridge.js"), b.fmt("{s}/jolt_bridge.js", .{web_dir}));
    const install_vendor = b.addInstallDirectory(.{
        .source_dir = phasor_dep.path("assets/web/vendor"),
        .install_dir = .prefix,
        .install_subdir = b.fmt("{s}/vendor", .{web_dir}),
    });
    const install_favicon = b.addInstallFile(phasor_dep.path("assets/web/favicon.svg"), b.fmt("{s}/favicon.svg", .{web_dir}));
    const install_triangle_shader = b.addInstallFile(
        phasor_dep.path("lib/render/shaders/triangle.wgsl"),
        b.fmt("{s}/shaders/triangle.wgsl", .{web_dir}),
    );
    const install_quad_shader = b.addInstallFile(
        phasor_dep.path("lib/render/shaders/quad.wgsl"),
        b.fmt("{s}/shaders/quad.wgsl", .{web_dir}),
    );
    const install_mesh_textured_shader = b.addInstallFile(
        phasor_dep.path("lib/render/shaders/mesh_textured.wgsl"),
        b.fmt("{s}/shaders/mesh_textured.wgsl", .{web_dir}),
    );
    const install_assets = b.addInstallDirectory(.{
        .source_dir = b.path("assets"),
        .install_dir = .prefix,
        .install_subdir = b.fmt("{s}/assets", .{web_dir}),
    });

    const run_server = b.addRunArtifact(server_exe);
    run_server.setCwd(b.path("."));
    run_server.addArg("--root");
    run_server.addArg(b.fmt("zig-out/{s}", .{web_dir}));
    run_server.addArg("--index");
    run_server.addArg("index.html");
    if (b.args) |args| {
        run_server.addArgs(args);
    }

    const installs = [_]*std.Build.Step{
        &install_wasm.step,
        &install_html.step,
        &install_webgpu.step,
        &install_jolt_bridge.step,
        &install_vendor.step,
        &install_favicon.step,
        &install_triangle_shader.step,
        &install_quad_shader.step,
        &install_mesh_textured_shader.step,
        &install_assets.step,
    };

    for (installs) |step| {
        run_server.step.dependOn(step);
    }

    const run_wasm = b.step("run-wasm", "Run the glTF example in the browser");
    run_wasm.dependOn(&run_server.step);
}
