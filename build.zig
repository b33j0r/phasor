const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ctx = BuildContext.init(b, target, optimize);

    const common = CommonModule.build(&ctx);
    const db = DbModule.build(&ctx, .{ .common = common.module });
    const graph = GraphModule.build(&ctx);
    const glfw = GlfwModule.build(&ctx);
    const ecs = EcsModule.build(&ctx, .{
        .common = common.module,
        .db = db.module,
        .graph = graph.module,
    });
    const metrics = MetricsModule.build(&ctx);
    const modules = ModulesModule.build(&ctx, .{
        .db = db.module,
        .ecs = ecs.module,
        .metrics = metrics.module,
    });
    const window = WindowModule.build(&ctx, .{
        .ecs = ecs.module,
        .glfw = glfw.module,
    });
    const renderer = RenderModule.build(&ctx, .{
        .common = common.module,
        .glfw = glfw.module,
    });
    const phasor = PhasorModule.build(&ctx, .{
        .common = common.module,
        .db = db.module,
        .ecs = ecs.module,
        .graph = graph.module,
        .metrics = metrics.module,
        .modules = modules.module,
        .renderer = renderer.module,
        .window = window.module,
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

    _ = addExample(&ctx, phasor.module, "ecs", "examples/ecs/main.zig", &.{});
    _ = addExample(&ctx, phasor.module, "window", "examples/window/main.zig", &.{});
    _ = addExample(&ctx, phasor.module, "triangle-native", "examples/triangle_native.zig", &.{.{
        .name = "glfw",
        .module = glfw.module,
    }});

    addWebExample(&ctx, phasor.module);

    const test_step = b.step("test", "Run tests");
    addModuleTests(b, test_step, &.{
        common.tests,
        db.tests,
        ecs.tests,
        graph.tests,
        glfw.tests,
        metrics.tests,
        modules.tests,
        renderer.tests,
        phasor.tests,
        window.tests,
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

const CommonModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    fn build(ctx: *const BuildContext) CommonModule {
        const bundle = ctx.moduleBundle("lib/common/root.zig", &.{});
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const DbModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        common: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) DbModule {
        const bundle = ctx.moduleBundle("lib/db/root.zig", &.{.{
            .name = "common",
            .module = deps.common,
        }});
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const EcsModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        common: *std.Build.Module,
        db: *std.Build.Module,
        graph: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) EcsModule {
        const bundle = ctx.moduleBundle("lib/ecs/root.zig", &.{
            .{ .name = "common", .module = deps.common },
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

const GlfwModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    fn build(ctx: *const BuildContext) GlfwModule {
        const glfw_dep = ctx.b.dependency("glfw", .{
            .target = ctx.target,
            .optimize = ctx.optimize,
        });
        const glfw_include = glfw_dep.path("include");

        const glfw_mod = ctx.b.createModule(.{
            .root_source_file = ctx.b.path("deps/glfw/root.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
        });
        glfw_mod.addIncludePath(glfw_include);
        if (ctx.target.result.os.tag.isDarwin()) {
            glfw_mod.addCMacro("_GLFW_COCOA", "1");
        }

        glfw_mod.addCSourceFiles(.{
            .root = glfw_dep.path(""),
            .files = &.{
                "src/context.c",
                "src/init.c",
                "src/input.c",
                "src/monitor.c",
                "src/platform.c",
                "src/vulkan.c",
                "src/window.c",
                "src/posix_thread.c",
                "src/posix_module.c",
                "src/null_init.c",
                "src/null_joystick.c",
                "src/null_monitor.c",
                "src/null_window.c",
                "src/egl_context.c",
                "src/osmesa_context.c",
            },
            .flags = &.{
                "-Wno-deprecated-declarations",
            },
        });

        if (ctx.target.result.os.tag.isDarwin()) {
            glfw_mod.addCSourceFiles(.{
                .root = glfw_dep.path(""),
                .files = &.{
                    "src/cocoa_init.m",
                    "src/cocoa_joystick.m",
                    "src/cocoa_monitor.m",
                    "src/cocoa_window.m",
                    "src/cocoa_time.c",
                    "src/nsgl_context.m",
                },
                .flags = &.{
                    "-Wno-deprecated-declarations",
                },
            });
        }

        if (ctx.target.result.os.tag.isDarwin()) {
            glfw_mod.linkFramework("Cocoa", .{});
            glfw_mod.linkFramework("IOKit", .{});
            glfw_mod.linkFramework("CoreVideo", .{});
        }

        return .{
            .module = glfw_mod,
            .tests = ctx.b.addTest(.{ .root_module = glfw_mod }),
        };
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
        common: *std.Build.Module,
        db: *std.Build.Module,
        ecs: *std.Build.Module,
        graph: *std.Build.Module,
        metrics: *std.Build.Module,
        modules: *std.Build.Module,
        renderer: *std.Build.Module,
        window: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) PhasorModule {
        const bundle = ctx.moduleBundle("src/root.zig", &.{
            .{ .name = "common", .module = deps.common },
            .{ .name = "db", .module = deps.db },
            .{ .name = "ecs", .module = deps.ecs },
            .{ .name = "graph", .module = deps.graph },
            .{ .name = "metrics", .module = deps.metrics },
            .{ .name = "modules", .module = deps.modules },
            .{ .name = "render", .module = deps.renderer },
            .{ .name = "window", .module = deps.window },
        });
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const RenderModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        common: *std.Build.Module,
        glfw: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) RenderModule {
        const is_wasm = ctx.target.result.cpu.arch.isWasm();

        var imports: std.ArrayList(std.Build.Module.Import) = .empty;
        defer imports.deinit(ctx.b.allocator);
        imports.append(ctx.b.allocator, .{ .name = "common", .module = deps.common }) catch unreachable;
        if (!is_wasm) {
            imports.append(ctx.b.allocator, .{ .name = "glfw", .module = deps.glfw }) catch unreachable;
        }

        if (!is_wasm) {
            const wgpu_dep = ctx.b.dependency("wgpu_native_zig", .{
                .target = ctx.target,
                .optimize = ctx.optimize,
            });
            const wgpu_mod = wgpu_dep.module("wgpu");
            imports.append(ctx.b.allocator, .{ .name = "wgpu", .module = wgpu_mod }) catch unreachable;
        }

        const bundle = ctx.moduleBundle("lib/render/root.zig", imports.items);

        if (!is_wasm and ctx.target.result.os.tag.isDarwin()) {
            bundle.module.addCSourceFiles(.{
                .files = &.{"lib/render/macos_utils.m"},
                .flags = &.{"-fobjc-arc"},
            });
            bundle.module.linkFramework("Cocoa", .{});
            bundle.module.linkFramework("QuartzCore", .{});
            bundle.module.linkFramework("Metal", .{});
        }

        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const WindowModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        ecs: *std.Build.Module,
        glfw: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) WindowModule {
        const bundle = ctx.moduleBundle("lib/window/root.zig", &.{
            .{ .name = "ecs", .module = deps.ecs },
            .{ .name = "glfw", .module = deps.glfw },
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

fn addExample(
    ctx: *const BuildContext,
    phasor_module: *std.Build.Module,
    name: []const u8,
    root: []const u8,
    extra_imports: []const std.Build.Module.Import,
) *std.Build.Step.Compile {
    var imports: std.ArrayList(std.Build.Module.Import) = .empty;
    defer imports.deinit(ctx.b.allocator);
    imports.append(ctx.b.allocator, .{
        .name = "phasor",
        .module = phasor_module,
    }) catch unreachable;
    for (extra_imports) |imp| {
        imports.append(ctx.b.allocator, imp) catch unreachable;
    }

    const exe_mod = ctx.module(root, imports.items);
    const exe = ctx.b.addExecutable(.{
        .name = name,
        .root_module = exe_mod,
    });
    ctx.b.installArtifact(exe);

    const run_step = ctx.b.step(ctx.b.fmt("run-{s}", .{name}), ctx.b.fmt("Run the {s} example", .{name}));
    const run_cmd = ctx.b.addRunArtifact(exe);
    run_cmd.step.dependOn(ctx.b.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    return exe;
}

fn addWebExample(ctx: *const BuildContext, _: *std.Build.Module) void {
    const wasm_target = ctx.b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_common = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/common/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
    });
    const wasm_render = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/render/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .imports = &.{.{ .name = "common", .module = wasm_common }},
    });
    const wasm_mod = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("examples/quad_web.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .imports = &.{
            .{ .name = "render", .module = wasm_render },
            .{ .name = "common", .module = wasm_common },
        },
    });

    const wasm_exe = ctx.b.addExecutable(.{
        .name = "quad_web",
        .root_module = wasm_mod,
    });
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;

    const install_wasm = ctx.b.addInstallArtifact(wasm_exe, .{
        .dest_dir = .{ .override = .{ .custom = "web" } },
    });
    const install_html = ctx.b.addInstallFile(ctx.b.path("examples/web/index.html"), "web/index.html");
    const install_js = ctx.b.addInstallFile(ctx.b.path("examples/web/webgpu.js"), "web/webgpu.js");

    const web_step = ctx.b.step("web", "Build the web example");
    web_step.dependOn(&install_wasm.step);
    web_step.dependOn(&install_html.step);
    web_step.dependOn(&install_js.step);
}
