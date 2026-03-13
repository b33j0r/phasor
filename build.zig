const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ctx = BuildContext.init(b, target, optimize);
    const is_wasm = ctx.target.result.cpu.arch.isWasm();

    const common = CommonModule.build(&ctx);
    const db = DbModule.build(&ctx, .{ .common = common.module });
    const graph = GraphModule.build(&ctx);
    const glfw = if (!is_wasm) GlfwModule.build(&ctx) else null;
    const stb = StbModule.build(&ctx);
    const stb_image = StbImageModule.build(&ctx);
    const miniaudio = if (!is_wasm) MiniaudioModule.build(&ctx) else null;
    const fastnoise = FastNoiseModule.build(&ctx);
    const ecs = EcsModule.build(&ctx, .{
        .common = common.module,
        .db = db.module,
        .graph = graph.module,
    });
    const metrics = MetricsModule.build(&ctx);
    const wasm_support = WasmSupportModule.build(&ctx);
    const renderer = RenderModule.build(&ctx, .{
        .common = common.module,
        .glfw = if (!is_wasm) glfw.?.module else null,
        .stb = stb.module,
    });
    const gui = GuiModuleLib.build(&ctx, .{
        .common = common.module,
        .ecs = ecs.module,
        .render = renderer.module,
    });
    const assets = AssetsModule.build(&ctx, .{
        .render = renderer.module,
        .stb_image = stb_image.module,
    });
    const audio = AudioModule.build(&ctx, .{
        .assets = assets.module,
    });
    const window = if (!is_wasm) WindowModule.build(&ctx, .{
        .common = common.module,
        .ecs = ecs.module,
        .glfw = glfw.?.module,
    }) else null;
    const modules = ModulesModule.build(&ctx, .{
        .common = common.module,
        .db = db.module,
        .ecs = ecs.module,
        .gui = gui.module,
        .assets = assets.module,
        .audio = audio.module,
        .metrics = metrics.module,
        .render = renderer.module,
        .fastnoise = fastnoise.module,
        .miniaudio = if (miniaudio) |mod| mod.module else null,
        .glfw = if (!is_wasm) glfw.?.module else null,
        .window = if (!is_wasm) window.?.module else null,
        .wasm = if (is_wasm) wasm_support.module else null,
    });
    const platform = PlatformModule.build(&ctx, .{
        .common = common.module,
        .ecs = ecs.module,
        .modules = modules.module,
        .renderer = renderer.module,
        .window = if (!is_wasm) window.?.module else null,
        .wasm = if (is_wasm) wasm_support.module else null,
    });
    const phasor = PhasorModule.build(&ctx, .{
        .common = common.module,
        .db = db.module,
        .ecs = ecs.module,
        .graph = graph.module,
        .metrics = metrics.module,
        .modules = modules.module,
        .platform = platform.module,
        .renderer = renderer.module,
        .gui = gui.module,
        .assets = assets.module,
        .audio = audio.module,
        .window = if (!is_wasm) window.?.module else null,
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
    _ = addExample(&ctx, phasor.module, "triangle", "examples/triangle/main.zig", &.{});
    _ = addExample(&ctx, phasor.module, "bouncing-ball", "examples/bouncing-ball/main.zig", &.{});
    _ = addExample(&ctx, phasor.module, "cube", "examples/cube/main.zig", &.{});
    _ = addExample(&ctx, phasor.module, "warehouse", "examples/warehouse/main.zig", &.{});
    addEcsQueryCacheBenchmark(&ctx, phasor.module);

    addWebExamples(&ctx);

    const test_step = b.step("test", "Run tests");
    if (is_wasm) {
        addModuleTests(b, test_step, &.{
            common.tests,
            db.tests,
            ecs.tests,
            graph.tests,
            stb.tests,
            stb_image.tests,
            fastnoise.tests,
            metrics.tests,
            audio.tests,
            modules.tests,
            platform.tests,
            renderer.tests,
            assets.tests,
            phasor.tests,
            wasm_support.tests,
        });
    } else {
        addModuleTests(b, test_step, &.{
            common.tests,
            db.tests,
            ecs.tests,
            graph.tests,
            glfw.?.tests,
            stb.tests,
            stb_image.tests,
            fastnoise.tests,
            metrics.tests,
            audio.tests,
            modules.tests,
            platform.tests,
            renderer.tests,
            assets.tests,
            phasor.tests,
            wasm_support.tests,
            window.?.tests,
        });
    }

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

    fn moduleBundlePublic(
        self: *const BuildContext,
        name: []const u8,
        root: []const u8,
        imports: []const std.Build.Module.Import,
    ) ModuleBundle {
        const mod = self.b.addModule(name, .{
            .root_source_file = self.b.path(root),
            .target = self.target,
            .optimize = self.optimize,
            .imports = imports,
        });
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

const StbModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    fn build(ctx: *const BuildContext) StbModule {
        const stb_dep = ctx.b.dependency("stb", .{
            .target = ctx.target,
            .optimize = ctx.optimize,
        });
        const stb_include = stb_dep.path("");

        const stb_mod = ctx.b.createModule(.{
            .root_source_file = ctx.b.path("deps/stb_truetype/root.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .link_libc = true,
        });
        stb_mod.addIncludePath(stb_include);
        stb_mod.addCSourceFiles(.{
            .root = ctx.b.path("deps/stb_truetype"),
            .files = &.{"stb_truetype.c"},
        });

        return .{
            .module = stb_mod,
            .tests = ctx.b.addTest(.{ .root_module = stb_mod }),
        };
    }
};

const StbImageModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    fn build(ctx: *const BuildContext) StbImageModule {
        const stb_dep = ctx.b.dependency("stb", .{
            .target = ctx.target,
            .optimize = ctx.optimize,
        });
        const stb_include = stb_dep.path("");

        const stb_image_mod = ctx.b.createModule(.{
            .root_source_file = ctx.b.path("deps/stb_image/root.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .link_libc = true,
        });
        stb_image_mod.addIncludePath(stb_include);
        stb_image_mod.addCSourceFiles(.{
            .root = ctx.b.path("deps/stb_image"),
            .files = &.{"stb_image.c"},
        });

        return .{
            .module = stb_image_mod,
            .tests = ctx.b.addTest(.{ .root_module = stb_image_mod }),
        };
    }
};

const AssetsModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        render: *std.Build.Module,
        stb_image: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) AssetsModule {
        const bundle = ctx.moduleBundle("lib/assets/root.zig", &.{
            .{ .name = "render", .module = deps.render },
            .{ .name = "stb_image", .module = deps.stb_image },
        });
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const AudioModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        assets: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) AudioModule {
        const bundle = ctx.moduleBundle("lib/audio/root.zig", &.{
            .{ .name = "assets", .module = deps.assets },
        });
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const MiniaudioModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    fn build(ctx: *const BuildContext) MiniaudioModule {
        const miniaudio_mod = ctx.b.createModule(.{
            .root_source_file = ctx.b.path("deps/miniaudio/root.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .link_libc = true,
        });
        miniaudio_mod.addIncludePath(ctx.b.path("deps/miniaudio"));
        miniaudio_mod.addCSourceFiles(.{
            .root = ctx.b.path("deps/miniaudio"),
            .files = &.{"miniaudio.c"},
        });

        return .{
            .module = miniaudio_mod,
            .tests = ctx.b.addTest(.{ .root_module = miniaudio_mod }),
        };
    }
};

const FastNoiseModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    fn build(ctx: *const BuildContext) FastNoiseModule {
        const fastnoise_mod = ctx.b.createModule(.{
            .root_source_file = ctx.b.path("deps/fastnoiselite/fastnoise.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
        });

        return .{
            .module = fastnoise_mod,
            .tests = ctx.b.addTest(.{ .root_module = fastnoise_mod }),
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

const GuiModuleLib = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        common: *std.Build.Module,
        ecs: *std.Build.Module,
        render: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) GuiModuleLib {
        const bundle = ctx.moduleBundlePublic("gui", "lib/gui/root.zig", &.{
            .{ .name = "common", .module = deps.common },
            .{ .name = "ecs", .module = deps.ecs },
            .{ .name = "render", .module = deps.render },
        });
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const ModulesModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        common: *std.Build.Module,
        db: *std.Build.Module,
        ecs: *std.Build.Module,
        gui: *std.Build.Module,
        assets: *std.Build.Module,
        audio: *std.Build.Module,
        metrics: *std.Build.Module,
        render: *std.Build.Module,
        fastnoise: *std.Build.Module,
        miniaudio: ?*std.Build.Module,
        glfw: ?*std.Build.Module,
        window: ?*std.Build.Module,
        wasm: ?*std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) ModulesModule {
        var imports: std.ArrayList(std.Build.Module.Import) = .empty;
        defer imports.deinit(ctx.b.allocator);
        imports.append(ctx.b.allocator, .{ .name = "common", .module = deps.common }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "db", .module = deps.db }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "ecs", .module = deps.ecs }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "gui", .module = deps.gui }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "assets", .module = deps.assets }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "audio", .module = deps.audio }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "metrics", .module = deps.metrics }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "render", .module = deps.render }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "fastnoise", .module = deps.fastnoise }) catch unreachable;
        if (deps.miniaudio) |miniaudio_mod| {
            imports.append(ctx.b.allocator, .{ .name = "miniaudio", .module = miniaudio_mod }) catch unreachable;
        }
        if (deps.glfw) |glfw_mod| {
            imports.append(ctx.b.allocator, .{ .name = "glfw", .module = glfw_mod }) catch unreachable;
        }
        if (deps.window) |window_mod| {
            imports.append(ctx.b.allocator, .{ .name = "window", .module = window_mod }) catch unreachable;
        }
        if (deps.wasm) |wasm_mod| {
            imports.append(ctx.b.allocator, .{ .name = "wasm", .module = wasm_mod }) catch unreachable;
        }

        const bundle = ctx.moduleBundle("lib/modules/root.zig", imports.items);
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
        platform: *std.Build.Module,
        renderer: *std.Build.Module,
        gui: *std.Build.Module,
        assets: *std.Build.Module,
        audio: *std.Build.Module,
        window: ?*std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) PhasorModule {
        const is_wasm = ctx.target.result.cpu.arch.isWasm();
        const root = if (is_wasm) "src/root_wasm.zig" else "src/root.zig";

        var imports: std.ArrayList(std.Build.Module.Import) = .empty;
        defer imports.deinit(ctx.b.allocator);
        imports.append(ctx.b.allocator, .{ .name = "common", .module = deps.common }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "db", .module = deps.db }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "ecs", .module = deps.ecs }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "graph", .module = deps.graph }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "metrics", .module = deps.metrics }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "modules", .module = deps.modules }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "platform", .module = deps.platform }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "render", .module = deps.renderer }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "gui", .module = deps.gui }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "assets", .module = deps.assets }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "audio", .module = deps.audio }) catch unreachable;
        if (!is_wasm) {
            const window_mod = deps.window orelse @panic("window module required for native builds");
            imports.append(ctx.b.allocator, .{ .name = "window", .module = window_mod }) catch unreachable;
        }

        const bundle = ctx.moduleBundlePublic("phasor", root, imports.items);
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const RenderModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        common: *std.Build.Module,
        glfw: ?*std.Build.Module,
        stb: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) RenderModule {
        const is_wasm = ctx.target.result.cpu.arch.isWasm();

        var imports: std.ArrayList(std.Build.Module.Import) = .empty;
        defer imports.deinit(ctx.b.allocator);
        imports.append(ctx.b.allocator, .{ .name = "common", .module = deps.common }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "stb", .module = deps.stb }) catch unreachable;
        if (!is_wasm) {
            const glfw_mod = deps.glfw orelse @panic("glfw module required for native builds");
            imports.append(ctx.b.allocator, .{ .name = "glfw", .module = glfw_mod }) catch unreachable;
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
        common: *std.Build.Module,
        ecs: *std.Build.Module,
        glfw: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) WindowModule {
        const bundle = ctx.moduleBundle("lib/window/root.zig", &.{
            .{ .name = "common", .module = deps.common },
            .{ .name = "ecs", .module = deps.ecs },
            .{ .name = "glfw", .module = deps.glfw },
        });
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const WasmSupportModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    fn build(ctx: *const BuildContext) WasmSupportModule {
        const bundle = ctx.moduleBundle("lib/wasm/root.zig", &.{});
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const PlatformModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        common: *std.Build.Module,
        ecs: *std.Build.Module,
        modules: *std.Build.Module,
        renderer: *std.Build.Module,
        window: ?*std.Build.Module,
        wasm: ?*std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) PlatformModule {
        const is_wasm = ctx.target.result.cpu.arch.isWasm();

        var imports: std.ArrayList(std.Build.Module.Import) = .empty;
        defer imports.deinit(ctx.b.allocator);
        imports.append(ctx.b.allocator, .{ .name = "common", .module = deps.common }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "ecs", .module = deps.ecs }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "modules", .module = deps.modules }) catch unreachable;
        imports.append(ctx.b.allocator, .{ .name = "render", .module = deps.renderer }) catch unreachable;
        if (!is_wasm) {
            const window_mod = deps.window orelse @panic("window module required for native builds");
            imports.append(ctx.b.allocator, .{ .name = "window", .module = window_mod }) catch unreachable;
        }
        if (is_wasm) {
            const wasm_mod = deps.wasm orelse @panic("wasm module required for wasm builds");
            imports.append(ctx.b.allocator, .{ .name = "wasm", .module = wasm_mod }) catch unreachable;
        }

        const bundle = ctx.moduleBundle("lib/platform/root.zig", imports.items);
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

    const run_native_step = ctx.b.step(
        ctx.b.fmt("run-{s}-native", .{name}),
        ctx.b.fmt("Run the {s} native example", .{name}),
    );
    run_native_step.dependOn(&run_cmd.step);

    return exe;
}

fn addEcsQueryCacheBenchmark(
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

const WasmExample = struct {
    name: []const u8,
    root: []const u8,
};

const WasmModules = struct {
    target: std.Build.ResolvedTarget,
    phasor: *std.Build.Module,
    support: *std.Build.Module,
};

fn sanitizeName(allocator: std.mem.Allocator, name: []const u8) []const u8 {
    var out = allocator.alloc(u8, name.len) catch unreachable;
    for (name, 0..) |c, i| {
        out[i] = if (c == '-') '_' else c;
    }
    return out;
}

fn addWasmExample(
    ctx: *const BuildContext,
    wasm: WasmModules,
    server_exe: *std.Build.Step.Compile,
    web_all: *std.Build.Step,
    ex: WasmExample,
) void {
    const wasm_mod = ctx.b.createModule(.{
        .root_source_file = ctx.b.path(ex.root),
        .target = wasm.target,
        .optimize = ctx.optimize,
        .imports = &.{
            .{ .name = "phasor", .module = wasm.phasor },
            .{ .name = "wasm", .module = wasm.support },
        },
    });

    const exe_name = ctx.b.fmt("{s}_web", .{sanitizeName(ctx.b.allocator, ex.name)});
    const wasm_exe = ctx.b.addExecutable(.{
        .name = exe_name,
        .root_module = wasm_mod,
    });
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;

    const web_dir = ctx.b.fmt("web/{s}", .{ex.name});
    const install_wasm = ctx.b.addInstallFile(wasm_exe.getEmittedBin(), ctx.b.fmt("{s}/app.wasm", .{web_dir}));
    const install_html = ctx.b.addInstallFile(ctx.b.path("assets/web/index.html"), ctx.b.fmt("{s}/index.html", .{web_dir}));
    const install_js = ctx.b.addInstallFile(ctx.b.path("assets/web/webgpu.js"), ctx.b.fmt("{s}/webgpu.js", .{web_dir}));
    const install_favicon = ctx.b.addInstallFile(ctx.b.path("assets/web/favicon.svg"), ctx.b.fmt("{s}/favicon.svg", .{web_dir}));
    const install_triangle_shader = ctx.b.addInstallFile(
        ctx.b.path("lib/render/shaders/triangle.wgsl"),
        ctx.b.fmt("{s}/shaders/triangle.wgsl", .{web_dir}),
    );
    const install_quad_shader = ctx.b.addInstallFile(
        ctx.b.path("lib/render/shaders/quad.wgsl"),
        ctx.b.fmt("{s}/shaders/quad.wgsl", .{web_dir}),
    );

    const web_step = ctx.b.step(ctx.b.fmt("web-{s}", .{ex.name}), ctx.b.fmt("Build the {s} web example", .{ex.name}));
    web_step.dependOn(&install_wasm.step);
    web_step.dependOn(&install_html.step);
    web_step.dependOn(&install_js.step);
    web_step.dependOn(&install_favicon.step);
    web_step.dependOn(&install_triangle_shader.step);
    web_step.dependOn(&install_quad_shader.step);

    web_all.dependOn(web_step);

    const run_server = ctx.b.addRunArtifact(server_exe);
    run_server.setCwd(ctx.b.path("."));
    run_server.addArg("--root");
    run_server.addArg(ctx.b.fmt("zig-out/{s}", .{web_dir}));
    run_server.addArg("--index");
    run_server.addArg("index.html");
    if (ctx.b.args) |args| {
        run_server.addArgs(args);
    }
    run_server.step.dependOn(&install_wasm.step);
    run_server.step.dependOn(&install_html.step);
    run_server.step.dependOn(&install_js.step);
    run_server.step.dependOn(&install_favicon.step);
    run_server.step.dependOn(&install_triangle_shader.step);
    run_server.step.dependOn(&install_quad_shader.step);

    const run_step = ctx.b.step(ctx.b.fmt("run-{s}-wasm", .{ex.name}), ctx.b.fmt("Run the {s} wasm example", .{ex.name}));
    run_step.dependOn(&run_server.step);

    const run_server_https = ctx.b.addRunArtifact(server_exe);
    run_server_https.setCwd(ctx.b.path("."));
    run_server_https.addArg("--root");
    run_server_https.addArg(ctx.b.fmt("zig-out/{s}", .{web_dir}));
    run_server_https.addArg("--index");
    run_server_https.addArg("index.html");
    run_server_https.addArg("--https");
    if (ctx.b.args) |args| {
        run_server_https.addArgs(args);
    }
    run_server_https.step.dependOn(&install_wasm.step);
    run_server_https.step.dependOn(&install_html.step);
    run_server_https.step.dependOn(&install_js.step);
    run_server_https.step.dependOn(&install_favicon.step);
    run_server_https.step.dependOn(&install_triangle_shader.step);
    run_server_https.step.dependOn(&install_quad_shader.step);

    const run_https_step = ctx.b.step(
        ctx.b.fmt("run-{s}-wasm-https", .{ex.name}),
        ctx.b.fmt("Run the {s} wasm example with HTTPS", .{ex.name}),
    );
    run_https_step.dependOn(&run_server_https.step);
}

fn addWebExamples(ctx: *const BuildContext) void {
    const wasm_target = ctx.b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });
    const wasm_common = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/common/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
    });
    const wasm_db = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/db/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .imports = &.{.{ .name = "common", .module = wasm_common }},
    });
    const wasm_graph = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/graph/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
    });
    const wasm_ecs = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/ecs/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .imports = &.{
            .{ .name = "common", .module = wasm_common },
            .{ .name = "db", .module = wasm_db },
            .{ .name = "graph", .module = wasm_graph },
        },
    });
    const wasm_metrics = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/metrics/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
    });
    const wasm_stb_dep = ctx.b.dependency("stb", .{
        .target = wasm_target,
        .optimize = ctx.optimize,
    });
    const wasm_stb = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("deps/stb_truetype/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .link_libc = true,
    });
    wasm_stb.addIncludePath(wasm_stb_dep.path(""));
    wasm_stb.addCSourceFiles(.{
        .root = ctx.b.path("deps/stb_truetype"),
        .files = &.{"stb_truetype.c"},
    });
    const wasm_stb_image = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("deps/stb_image/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .link_libc = true,
    });
    wasm_stb_image.addIncludePath(wasm_stb_dep.path(""));
    wasm_stb_image.addCSourceFiles(.{
        .root = ctx.b.path("deps/stb_image"),
        .files = &.{"stb_image.c"},
    });
    const wasm_render = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/render/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .imports = &.{
            .{ .name = "common", .module = wasm_common },
            .{ .name = "stb", .module = wasm_stb },
        },
    });
    const wasm_gui = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/gui/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .imports = &.{
            .{ .name = "common", .module = wasm_common },
            .{ .name = "ecs", .module = wasm_ecs },
            .{ .name = "render", .module = wasm_render },
        },
    });
    const wasm_assets = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/assets/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .imports = &.{
            .{ .name = "render", .module = wasm_render },
            .{ .name = "stb_image", .module = wasm_stb_image },
        },
    });
    const wasm_audio = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/audio/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .imports = &.{
            .{ .name = "assets", .module = wasm_assets },
        },
    });
    const wasm_fastnoise = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("deps/fastnoiselite/fastnoise.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
    });
    const wasm_support = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/wasm/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
    });
    const wasm_modules = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/modules/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .imports = &.{
            .{ .name = "common", .module = wasm_common },
            .{ .name = "db", .module = wasm_db },
            .{ .name = "ecs", .module = wasm_ecs },
            .{ .name = "gui", .module = wasm_gui },
            .{ .name = "assets", .module = wasm_assets },
            .{ .name = "audio", .module = wasm_audio },
            .{ .name = "metrics", .module = wasm_metrics },
            .{ .name = "render", .module = wasm_render },
            .{ .name = "fastnoise", .module = wasm_fastnoise },
            .{ .name = "wasm", .module = wasm_support },
        },
    });
    const wasm_platform = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("lib/platform/root.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .imports = &.{
            .{ .name = "common", .module = wasm_common },
            .{ .name = "ecs", .module = wasm_ecs },
            .{ .name = "modules", .module = wasm_modules },
            .{ .name = "render", .module = wasm_render },
            .{ .name = "wasm", .module = wasm_support },
        },
    });
    const wasm_phasor = ctx.b.createModule(.{
        .root_source_file = ctx.b.path("src/root_wasm.zig"),
        .target = wasm_target,
        .optimize = ctx.optimize,
        .imports = &.{
            .{ .name = "common", .module = wasm_common },
            .{ .name = "db", .module = wasm_db },
            .{ .name = "ecs", .module = wasm_ecs },
            .{ .name = "graph", .module = wasm_graph },
            .{ .name = "metrics", .module = wasm_metrics },
            .{ .name = "modules", .module = wasm_modules },
            .{ .name = "platform", .module = wasm_platform },
            .{ .name = "render", .module = wasm_render },
            .{ .name = "gui", .module = wasm_gui },
            .{ .name = "assets", .module = wasm_assets },
            .{ .name = "audio", .module = wasm_audio },
        },
    });

    const wasm_examples = [_]WasmExample{
        .{ .name = "bouncing-ball", .root = "examples/bouncing-ball/main.zig" },
        .{ .name = "cube", .root = "examples/cube/main.zig" },
        .{ .name = "triangle", .root = "examples/triangle/main.zig" },
        .{ .name = "warehouse", .root = "examples/warehouse/main.zig" },
    };

    const server_mod = ctx.module("lib/web/wasm_server.zig", &.{});
    const server_exe = ctx.b.addExecutable(.{
        .name = "wasm_server",
        .root_module = server_mod,
    });
    ctx.b.installArtifact(server_exe);

    const web_all = ctx.b.step("web", "Build all web examples");
    const wasm = WasmModules{
        .target = wasm_target,
        .phasor = wasm_phasor,
        .support = wasm_support,
    };

    for (wasm_examples) |ex| {
        addWasmExample(ctx, wasm, server_exe, web_all, ex);
    }
}
