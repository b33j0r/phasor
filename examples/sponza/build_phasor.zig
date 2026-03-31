const std = @import("std");

pub const BuildOptions = struct {
    name: []const u8,
    root_source: []const u8,
    asset_dirs: []const InstallDir = &.{},
    fetch: ?FetchOptions = null,
    enable_wasm: bool = true,
    extra_modules: []const ExtraModule = &.{},
};

pub const InstallDir = struct {
    source: []const u8,
    dest: []const u8,
};

pub const FetchOptions = struct {
    step_name: []const u8,
    step_description: []const u8,
    tool_source: []const u8,
};

pub const ExtraModule = struct {
    name: []const u8,
    source: Source,

    pub const Source = union(enum) {
        local_path: []const u8,
        phasor_path: []const u8,
    };
};

const FetchBuild = struct {
    user_step: *std.Build.Step,
    prepare_step: *std.Build.Step,
};

pub fn buildExample(b: *std.Build, options: BuildOptions) void {
    const native_target = b.standardTargetOptions(.{});
    const host_target = b.graph.host;
    const optimize = b.standardOptimizeOption(.{});

    const phasor_dep = b.dependency("phasor", .{
        .target = native_target,
        .optimize = optimize,
    });
    const phasor = phasor_dep.module("phasor");
    const phasor_physics = phasor_dep.module("phasor_physics");

    var native_imports: std.ArrayList(std.Build.Module.Import) = .empty;
    defer native_imports.deinit(b.allocator);
    native_imports.append(b.allocator, .{
        .name = "phasor",
        .module = phasor,
    }) catch unreachable;
    native_imports.append(b.allocator, .{
        .name = "phasor_physics",
        .module = phasor_physics,
    }) catch unreachable;
    appendExtraModules(b, native_target, optimize, phasor_dep, options.extra_modules, &native_imports);

    const app_mod = b.createModule(.{
        .root_source_file = b.path(options.root_source),
        .target = native_target,
        .optimize = optimize,
        .imports = native_imports.items,
    });
    const exe = b.addExecutable(.{
        .name = options.name,
        .root_module = app_mod,
    });
    b.installArtifact(exe);

    const fetch = if (options.fetch) |fetch_options|
        addFetchStep(b, host_target, optimize, fetch_options)
    else
        null;

    const run = b.step("run", b.fmt("Run {s}", .{options.name}));
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (fetch) |fetch_build| {
        run_cmd.step.dependOn(fetch_build.prepare_step);
    }
    run.dependOn(&run_cmd.step);

    const run_native = b.step("run-native", b.fmt("Run {s} natively", .{options.name}));
    run_native.dependOn(&run_cmd.step);

    if (fetch) |fetch_build| {
        _ = fetch_build.user_step;
    }

    if (options.enable_wasm) {
        addWebBundle(b, host_target, optimize, phasor_dep, options, fetch);
    }
}

fn addFetchStep(
    b: *std.Build,
    host_target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: FetchOptions,
) FetchBuild {
    const fetch_mod = b.createModule(.{
        .root_source_file = b.path(options.tool_source),
        .target = host_target,
        .optimize = optimize,
    });
    const fetch_exe = b.addExecutable(.{
        .name = options.step_name,
        .root_module = fetch_mod,
    });
    b.installArtifact(fetch_exe);

    const fetch_user_run = b.addRunArtifact(fetch_exe);
    fetch_user_run.setCwd(b.path("."));
    if (b.args) |args| {
        fetch_user_run.addArgs(args);
    }

    const fetch_user_step = b.step(options.step_name, options.step_description);
    fetch_user_step.dependOn(&fetch_user_run.step);

    const fetch_prepare_run = b.addRunArtifact(fetch_exe);
    fetch_prepare_run.setCwd(b.path("."));

    return .{
        .user_step = fetch_user_step,
        .prepare_step = &fetch_prepare_run.step,
    };
}

fn addWebBundle(
    b: *std.Build,
    host_target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    phasor_dep: *std.Build.Dependency,
    options: BuildOptions,
    fetch: ?FetchBuild,
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
    const wasm_phasor_physics = wasm_phasor_dep.module("phasor_physics");

    var wasm_imports: std.ArrayList(std.Build.Module.Import) = .empty;
    defer wasm_imports.deinit(b.allocator);
    wasm_imports.append(b.allocator, .{
        .name = "phasor",
        .module = wasm_phasor,
    }) catch unreachable;
    wasm_imports.append(b.allocator, .{
        .name = "phasor_physics",
        .module = wasm_phasor_physics,
    }) catch unreachable;
    appendExtraModules(b, wasm_target, optimize, wasm_phasor_dep, options.extra_modules, &wasm_imports);

    const wasm_mod = b.createModule(.{
        .root_source_file = b.path(options.root_source),
        .target = wasm_target,
        .optimize = optimize,
        .imports = wasm_imports.items,
    });
    const wasm_exe = b.addExecutable(.{
        .name = b.fmt("{s}_web", .{options.name}),
        .root_module = wasm_mod,
    });
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;

    const server_mod = b.createModule(.{
        .root_source_file = phasor_dep.path("lib/web/wasm_server.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    const server_exe = b.addExecutable(.{
        .name = b.fmt("{s}_wasm_server", .{options.name}),
        .root_module = server_mod,
    });
    b.installArtifact(server_exe);

    const web_dir = "web";
    const install_wasm = b.addInstallFile(wasm_exe.getEmittedBin(), "web/app.wasm");
    const install_html = b.addInstallFile(phasor_dep.path("assets/web/index.html"), "web/index.html");
    const install_js = b.addInstallFile(phasor_dep.path("assets/web/webgpu.js"), "web/webgpu.js");
    const install_jolt_bridge = b.addInstallFile(phasor_dep.path("assets/web/jolt_bridge.js"), "web/jolt_bridge.js");
    const install_vendor = b.addInstallDirectory(.{
        .source_dir = phasor_dep.path("assets/web/vendor"),
        .install_dir = .prefix,
        .install_subdir = "web/vendor",
    });
    const install_favicon = b.addInstallFile(phasor_dep.path("assets/web/favicon.svg"), "web/favicon.svg");
    const install_triangle_shader = b.addInstallFile(
        phasor_dep.path("lib/render/shaders/triangle.wgsl"),
        "web/shaders/triangle.wgsl",
    );
    const install_quad_shader = b.addInstallFile(
        phasor_dep.path("lib/render/shaders/quad.wgsl"),
        "web/shaders/quad.wgsl",
    );
    const install_mesh_textured_shader = b.addInstallFile(
        phasor_dep.path("lib/render/shaders/mesh_textured.wgsl"),
        "web/shaders/mesh_textured.wgsl",
    );

    const web_step = b.step("web", b.fmt("Build the {s} web bundle", .{options.name}));
    dependOnInstall(web_step, &.{
        &install_wasm.step,
        &install_html.step,
        &install_js.step,
        &install_jolt_bridge.step,
        &install_vendor.step,
        &install_favicon.step,
        &install_triangle_shader.step,
        &install_quad_shader.step,
        &install_mesh_textured_shader.step,
    });
    if (fetch) |fetch_build| {
        web_step.dependOn(fetch_build.prepare_step);
    }

    for (options.asset_dirs) |asset_dir| {
        const install_dir = b.addInstallDirectory(.{
            .source_dir = b.path(asset_dir.source),
            .install_dir = .prefix,
            .install_subdir = b.fmt("{s}/{s}", .{ web_dir, asset_dir.dest }),
        });
        if (fetch) |fetch_build| {
            install_dir.step.dependOn(fetch_build.prepare_step);
        }
        web_step.dependOn(&install_dir.step);
    }

    const run_server = b.addRunArtifact(server_exe);
    run_server.setCwd(b.path("."));
    run_server.addArg("--root");
    run_server.addArg("zig-out/web");
    run_server.addArg("--index");
    run_server.addArg("index.html");
    if (b.args) |args| {
        run_server.addArgs(args);
    }
    dependOnInstall(&run_server.step, &.{
        &install_wasm.step,
        &install_html.step,
        &install_js.step,
        &install_jolt_bridge.step,
        &install_vendor.step,
        &install_favicon.step,
        &install_triangle_shader.step,
        &install_quad_shader.step,
        &install_mesh_textured_shader.step,
    });
    if (fetch) |fetch_build| {
        run_server.step.dependOn(fetch_build.prepare_step);
    }
    for (options.asset_dirs) |asset_dir| {
        const install_dir = b.addInstallDirectory(.{
            .source_dir = b.path(asset_dir.source),
            .install_dir = .prefix,
            .install_subdir = b.fmt("{s}/{s}", .{ web_dir, asset_dir.dest }),
        });
        if (fetch) |fetch_build| {
            install_dir.step.dependOn(fetch_build.prepare_step);
        }
        run_server.step.dependOn(&install_dir.step);
    }

    const run_wasm = b.step("run-wasm", b.fmt("Run {s} in the browser", .{options.name}));
    run_wasm.dependOn(&run_server.step);

    const run_server_https = b.addRunArtifact(server_exe);
    run_server_https.setCwd(b.path("."));
    run_server_https.addArg("--root");
    run_server_https.addArg("zig-out/web");
    run_server_https.addArg("--index");
    run_server_https.addArg("index.html");
    run_server_https.addArg("--https");
    if (b.args) |args| {
        run_server_https.addArgs(args);
    }
    dependOnInstall(&run_server_https.step, &.{
        &install_wasm.step,
        &install_html.step,
        &install_js.step,
        &install_jolt_bridge.step,
        &install_vendor.step,
        &install_favicon.step,
        &install_triangle_shader.step,
        &install_quad_shader.step,
        &install_mesh_textured_shader.step,
    });
    if (fetch) |fetch_build| {
        run_server_https.step.dependOn(fetch_build.prepare_step);
    }
    for (options.asset_dirs) |asset_dir| {
        const install_dir = b.addInstallDirectory(.{
            .source_dir = b.path(asset_dir.source),
            .install_dir = .prefix,
            .install_subdir = b.fmt("{s}/{s}", .{ web_dir, asset_dir.dest }),
        });
        if (fetch) |fetch_build| {
            install_dir.step.dependOn(fetch_build.prepare_step);
        }
        run_server_https.step.dependOn(&install_dir.step);
    }

    const run_wasm_https = b.step("run-wasm-https", b.fmt("Run {s} in the browser over HTTPS", .{options.name}));
    run_wasm_https.dependOn(&run_server_https.step);
}

fn dependOnInstall(step: *std.Build.Step, dependencies: []const *std.Build.Step) void {
    for (dependencies) |dependency| {
        step.dependOn(dependency);
    }
}

fn appendExtraModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    phasor_dep: *std.Build.Dependency,
    extra_modules: []const ExtraModule,
    imports: *std.ArrayList(std.Build.Module.Import),
) void {
    for (extra_modules) |extra_module| {
        const module = b.createModule(.{
            .root_source_file = switch (extra_module.source) {
                .local_path => |path| b.path(path),
                .phasor_path => |path| phasor_dep.path(path),
            },
            .target = target,
            .optimize = optimize,
        });
        imports.append(b.allocator, .{
            .name = extra_module.name,
            .module = module,
        }) catch unreachable;
    }
}
