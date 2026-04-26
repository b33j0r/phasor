# `phasor`

`phasor` is an ECS-first Zig game engine with native and browser WebGPU backends.

Zig `0.16-dev` APIs are assumed throughout the codebase.

## What Exists Today

Engine coverage in the repo includes:
- ECS schedules, queries, resources, hierarchy, and phases
- native and wasm WebGPU rendering
- 2D sprite/textured-quad rendering and 3D scene examples
- glTF scene import
- physics integration
- audio and metrics modules

Backend parity is an explicit goal. Features added on one backend should generally exist on the other as well.

## Package Name

Downstream projects should depend on `phasor` as dependency name `phasor` and import it with:

```zig
const phasor = @import("phasor");
```

## Build And Run

From `phasor/`:

```bash
zig build test
```

Native examples:

```bash
zig build run-triangle
zig build run-bouncing-ball
zig build run-particles
zig build run-cube
zig build run-physics-cubes
zig build run-gltf
zig build run-warehouse
zig build run-shadows
zig build run-sponza
zig build run-ecs
zig build run-window
```

Wasm examples:

```bash
zig build run-triangle-wasm
zig build run-bouncing-ball-wasm
zig build run-particles-wasm
zig build run-cube-wasm
zig build run-physics-cubes-wasm
zig build run-gltf-wasm
zig build run-warehouse-wasm
zig build run-shadows-wasm
```

Build-only wasm bundles:

```bash
zig build build-triangle-wasm
zig build build-cube-wasm
zig build build-gltf-wasm
zig build build-warehouse-wasm
zig build build-shadows-wasm
```

Sponza assets are fetched separately:

```bash
zig build fetch-sponza
zig build run-sponza
```

## Example Guide

- `triangle`: smallest render path
- `bouncing-ball`: 2D motion, collisions, hierarchy
- `particles`: particle rendering
- `cube`: 3D transforms and hierarchy
- `physics-cubes`: physics-backed 3D scene
- `gltf`: glTF scene loading
- `warehouse`: larger scene/render example
- `shadows`: shadow pipeline work
- `sponza`: native-only scene used for current normals/render investigation
- `ecs`: ECS-only example with no renderer
- `window`: minimal window/platform setup

Each example keeps its own copy of `build_phasor.zig` so it can be copied into a new project without following repo-local symlinks. The helper has one optional physics path: examples that import `phasor_physics` set `.enable_physics = true` in `build.zig` and include the `phasor_physics` dependency in `build.zig.zon`; examples that do not use physics leave the default off.

## Web Notes

WebGPU requires a secure context off localhost. For LAN/device testing:

```bash
mkcert -install
zig build run-cube-wasm -- --host 0.0.0.0 --https --no-open
```

Then browse to your host machine over `https://<host>:8443`.

Notes:
- `0.0.0.0` is bind-only; do not browse to it directly.
- `python3` is required for the HTTPS proxy path.
- wasm examples now serve from their own example output trees, not a single shared top-level web directory.

## Development Notes

- Prefer `std.log` over `std.debug.print`.
- Use `std.heap.c_allocator` outside entrypoint-specific setup/teardown unless a child arena is justified.
- Root executables/examples that need verbose logs should set:

```zig
pub const std_options = phasor.common.logging.stdOptions(.debug);
```

- Runtime diagnostics are opt-in by default:
  - `platform.Options.install_crash_dump = false`
  - `platform.Options.install_soak_monitor = false`
  - `platform.Options.pause_on_gpu_error = false`
  - `SoakMonitorSettings.enabled = false`

## ECS Notes

Default schedules include:

```text
WindowCreate
AssetsLoad
Startup
BeforeFrame
Update
Render
AfterFrame
Shutdown
AssetsUnload
WindowDestroy
```

For `modules.PhasesModule`, phase-specific systems should be registered from phase `enter` with `ctx.addSystem(...)` rather than installed globally and guarded later.
