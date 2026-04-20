const std = @import("std");

fn translatedCModule(
    ctx: *const BuildContext,
    root_source_file: std.Build.LazyPath,
    include_paths: []const std.Build.LazyPath,
    macros: []const struct { name: []const u8, value: ?[]const u8 },
) *std.Build.Module {
    const translate_c = ctx.b.addTranslateC(.{
        .root_source_file = root_source_file,
        .target = ctx.target,
        .optimize = ctx.optimize,
        .link_libc = true,
    });
    for (include_paths) |include_path| translate_c.addIncludePath(include_path);
    for (macros) |macro| translate_c.defineCMacro(macro.name, macro.value);
    return translate_c.createModule();
}

pub const BuildContext = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    pub fn init(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildContext {
        return .{
            .b = b,
            .target = target,
            .optimize = optimize,
        };
    }

    pub fn module(self: *const BuildContext, root: []const u8, imports: []const std.Build.Module.Import) *std.Build.Module {
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
        const bundle = ctx.moduleBundlePublic("common", "lib/common/root.zig", &.{});
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
        const bundle = ctx.moduleBundlePublic("ecs", "lib/ecs/root.zig", &.{
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
        const glfw_c = translatedCModule(
            ctx,
            ctx.b.path("deps/glfw/root.h"),
            &.{glfw_include},
            if (ctx.target.result.os.tag.isDarwin())
                &.{.{ .name = "_GLFW_COCOA", .value = "1" }}
            else
                &.{},
        );

        const glfw_mod = ctx.b.createModule(.{
            .root_source_file = ctx.b.path("deps/glfw/root.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .imports = &.{.{
                .name = "glfw_c",
                .module = glfw_c,
            }},
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
        const stb_c = translatedCModule(
            ctx,
            ctx.b.path("deps/stb_truetype/root.h"),
            &.{stb_include},
            &.{},
        );

        const stb_mod = ctx.b.createModule(.{
            .root_source_file = ctx.b.path("deps/stb_truetype/root.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .link_libc = true,
            .imports = &.{.{
                .name = "stb_truetype_c",
                .module = stb_c,
            }},
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
        const stb_image_c = translatedCModule(
            ctx,
            ctx.b.path("deps/stb_image/root.h"),
            &.{stb_include},
            &.{},
        );

        const stb_image_mod = ctx.b.createModule(.{
            .root_source_file = ctx.b.path("deps/stb_image/root.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .link_libc = true,
            .imports = &.{.{
                .name = "stb_image_c",
                .module = stb_image_c,
            }},
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

const CgltfModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    fn build(ctx: *const BuildContext) CgltfModule {
        const cgltf_dep = ctx.b.dependency("cgltf", .{
            .target = ctx.target,
            .optimize = ctx.optimize,
        });
        const cgltf_c = translatedCModule(
            ctx,
            ctx.b.path("deps/cgltf/root.h"),
            &.{cgltf_dep.path("")},
            &.{},
        );

        const cgltf_mod = ctx.b.createModule(.{
            .root_source_file = ctx.b.path("deps/cgltf/root.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .link_libc = true,
            .imports = &.{.{
                .name = "cgltf_c",
                .module = cgltf_c,
            }},
        });
        cgltf_mod.addIncludePath(cgltf_dep.path(""));
        cgltf_mod.addCSourceFiles(.{
            .root = ctx.b.path("deps/cgltf"),
            .files = &.{"cgltf_impl.c"},
        });

        return .{
            .module = cgltf_mod,
            .tests = ctx.b.addTest(.{ .root_module = cgltf_mod }),
        };
    }
};

const AssetsModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        common: *std.Build.Module,
        render: *std.Build.Module,
        stb_image: *std.Build.Module,
        cgltf: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) AssetsModule {
        const bundle = ctx.moduleBundle("lib/assets/root.zig", &.{
            .{ .name = "common", .module = deps.common },
            .{ .name = "render", .module = deps.render },
            .{ .name = "stb_image", .module = deps.stb_image },
            .{ .name = "cgltf", .module = deps.cgltf },
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
        const miniaudio_c = translatedCModule(
            ctx,
            ctx.b.path("deps/miniaudio/root.h"),
            &.{ctx.b.path("deps/miniaudio")},
            &.{},
        );
        const miniaudio_mod = ctx.b.createModule(.{
            .root_source_file = ctx.b.path("deps/miniaudio/root.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .link_libc = true,
            .imports = &.{.{
                .name = "miniaudio_c",
                .module = miniaudio_c,
            }},
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
        const fastnoise_tests_mod = ctx.b.createModule(.{
            .root_source_file = ctx.b.path("deps/fastnoiselite/exhaustive_tests.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .imports = &.{.{
                .name = "fastnoise",
                .module = fastnoise_mod,
            }},
        });

        return .{
            .module = fastnoise_mod,
            .tests = ctx.b.addTest(.{ .root_module = fastnoise_tests_mod }),
        };
    }
};

const MetricsModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        common: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) MetricsModule {
        const bundle = ctx.moduleBundle("lib/metrics/root.zig", &.{.{
            .name = "common",
            .module = deps.common,
        }});
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
        lighting: *std.Build.Module,
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
        imports.append(ctx.b.allocator, .{ .name = "lighting", .module = deps.lighting }) catch unreachable;
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

        const bundle = ctx.moduleBundlePublic("modules", "lib/modules/root.zig", imports.items);
        return .{ .module = bundle.module, .tests = bundle.tests };
    }
};

const PhysicsFpsSupportModule = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        modules: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) PhysicsFpsSupportModule {
        const bundle = ctx.moduleBundlePublic("physics_fps_support", "lib/support/physics_fps.zig", &.{
            .{ .name = "modules", .module = deps.modules },
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
        lighting: *std.Build.Module,
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
        imports.append(ctx.b.allocator, .{ .name = "lighting", .module = deps.lighting }) catch unreachable;
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

const LightingModuleLib = struct {
    module: *std.Build.Module,
    tests: *std.Build.Step.Compile,

    const Deps = struct {
        common: *std.Build.Module,
        stb_image: *std.Build.Module,
    };

    fn build(ctx: *const BuildContext, deps: Deps) LightingModuleLib {
        const bundle = ctx.moduleBundle("lib/lighting/root.zig", &.{
            .{ .name = "common", .module = deps.common },
            .{ .name = "stb_image", .module = deps.stb_image },
        });
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

pub fn addModuleTests(
    b: *std.Build,
    test_step: *std.Build.Step,
    tests: []const *std.Build.Step.Compile,
) void {
    for (tests) |test_exe| {
        const run = b.addRunArtifact(test_exe);
        test_step.dependOn(&run.step);
    }
}

pub const Engine = struct {
    common: CommonModule,
    db: DbModule,
    graph: GraphModule,
    glfw: ?GlfwModule,
    stb: StbModule,
    stb_image: StbImageModule,
    cgltf: CgltfModule,
    miniaudio: ?MiniaudioModule,
    fastnoise: FastNoiseModule,
    ecs: EcsModule,
    lighting: LightingModuleLib,
    metrics: MetricsModule,
    wasm_support: WasmSupportModule,
    renderer: RenderModule,
    gui: GuiModuleLib,
    assets: AssetsModule,
    audio: AudioModule,
    window: ?WindowModule,
    modules: ModulesModule,
    physics_fps_support: PhysicsFpsSupportModule,
    platform: PlatformModule,
    phasor: PhasorModule,
};

pub fn buildEngine(ctx: *const BuildContext) Engine {
    const is_wasm = ctx.target.result.cpu.arch.isWasm();

    const common = CommonModule.build(ctx);
    const db = DbModule.build(ctx, .{ .common = common.module });
    const graph = GraphModule.build(ctx);
    const glfw = if (!is_wasm) GlfwModule.build(ctx) else null;
    const stb = StbModule.build(ctx);
    const stb_image = StbImageModule.build(ctx);
    const cgltf = CgltfModule.build(ctx);
    const miniaudio = if (!is_wasm) MiniaudioModule.build(ctx) else null;
    const fastnoise = FastNoiseModule.build(ctx);
    const ecs = EcsModule.build(ctx, .{
        .common = common.module,
        .db = db.module,
        .graph = graph.module,
    });
    const lighting = LightingModuleLib.build(ctx, .{
        .common = common.module,
        .stb_image = stb_image.module,
    });
    const metrics = MetricsModule.build(ctx, .{
        .common = common.module,
    });
    const wasm_support = WasmSupportModule.build(ctx);
    const renderer = RenderModule.build(ctx, .{
        .common = common.module,
        .glfw = if (!is_wasm) glfw.?.module else null,
        .stb = stb.module,
    });
    const gui = GuiModuleLib.build(ctx, .{
        .common = common.module,
        .ecs = ecs.module,
        .render = renderer.module,
    });
    const assets = AssetsModule.build(ctx, .{
        .common = common.module,
        .render = renderer.module,
        .stb_image = stb_image.module,
        .cgltf = cgltf.module,
    });
    const audio = AudioModule.build(ctx, .{
        .assets = assets.module,
    });
    const window = if (!is_wasm) WindowModule.build(ctx, .{
        .common = common.module,
        .ecs = ecs.module,
        .glfw = glfw.?.module,
    }) else null;
    const modules = ModulesModule.build(ctx, .{
        .common = common.module,
        .db = db.module,
        .ecs = ecs.module,
        .lighting = lighting.module,
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
    const physics_fps_support = PhysicsFpsSupportModule.build(ctx, .{
        .modules = modules.module,
    });
    const platform = PlatformModule.build(ctx, .{
        .common = common.module,
        .ecs = ecs.module,
        .modules = modules.module,
        .renderer = renderer.module,
        .window = if (!is_wasm) window.?.module else null,
        .wasm = if (is_wasm) wasm_support.module else null,
    });
    const phasor = PhasorModule.build(ctx, .{
        .common = common.module,
        .db = db.module,
        .ecs = ecs.module,
        .graph = graph.module,
        .metrics = metrics.module,
        .lighting = lighting.module,
        .modules = modules.module,
        .platform = platform.module,
        .renderer = renderer.module,
        .gui = gui.module,
        .assets = assets.module,
        .audio = audio.module,
        .window = if (!is_wasm) window.?.module else null,
    });

    return .{
        .common = common,
        .db = db,
        .graph = graph,
        .glfw = glfw,
        .stb = stb,
        .stb_image = stb_image,
        .cgltf = cgltf,
        .miniaudio = miniaudio,
        .fastnoise = fastnoise,
        .ecs = ecs,
        .lighting = lighting,
        .metrics = metrics,
        .wasm_support = wasm_support,
        .renderer = renderer,
        .gui = gui,
        .assets = assets,
        .audio = audio,
        .window = window,
        .modules = modules,
        .physics_fps_support = physics_fps_support,
        .platform = platform,
        .phasor = phasor,
    };
}

const ExampleBuild = struct {
    exe: *std.Build.Step.Compile,
    run_step: *std.Build.Step,
    run_native_step: *std.Build.Step,
};

fn addExample(
    ctx: *const BuildContext,
    phasor_module: *std.Build.Module,
    name: []const u8,
    root: []const u8,
    extra_imports: []const std.Build.Module.Import,
) ExampleBuild {
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

    return .{
        .exe = exe,
        .run_step = run_step,
        .run_native_step = run_native_step,
    };
}
