# Physics Module Proposal

Status: proposed architecture reference

Scope: public `physics` Zig module for `phasor-lite`, designed to split into its own repo later without dragging `modules/`, `platform`, or renderer along with it.

Merge note:

- delete this planning/proposal doc before merging `codex/physics`
- only keep extracted durable documentation if it is still useful after implementation lands

Execution plan:

- branch sequencing and delivery gates live in [physics-plan.md](/Users/brian/Projects/phasor/phasor-lite/docs/physics-plan.md)
- this document is the architecture and API reference for the `physics` side of that roadmap

## Summary

Recommended path:

1. Build a public `physics` module with an ECS-first API and a backend interface.
2. Keep cross-thread communication consistent with `Commands`, `ecs.Events(T)`, and metrics by standardizing on `std.Io.Queue` behind `common.Channel(T)`.
3. Reuse the glTF scene pipeline already merged to `main` as the source for offline collision baking.
4. Use Jolt Physics as the primary 3D backend for native targets.
5. Keep the current ad-hoc `FpsPhysicsModule` only as a temporary gameplay helper, then migrate it onto `physics`.
6. Do not make wasm parity a design blocker for v1. Keep wasm behind a fallback backend or feature gate until the native API stabilizes.

## Why This Should Be A Separate Public Module

Current `phasor-lite` structure already separates durable subsystems into module roots such as `common`, `ecs`, `render`, `gui`, and `assets`, and exports the main public surface with `b.addModule("phasor", ...)`.

Physics should follow the same pattern:

- public module name: `physics`
- implementation location: `lib/physics/`
- imported by `phasor` and `modules`, but not owned by either
- engine bindings live under `deps/` plus `lib/physics/backends/`

That keeps the future split clean:

- `physics` depends on `common` math types and `ecs`
- `platform` depends on `physics` only when installing default modules
- games can import `@import("physics")` directly later if you split repos

It also keeps threading clean:

- renderer stays main-thread-facing and reads final ECS state only
- physics worker never mutates the ECS world directly
- all thread handoff goes through channels, then back into ECS resources/components on the main thread

Related boundary:

- model and scene import belong in `assets`, not in `physics`
- `physics` should consume baked collision assets, not raw importer state
- glTF ingestion is already on `main`, so the physics branch should build on that input rather than duplicate importer work

## Engine Shortlist

### 1. Jolt Physics

Best fit for `phasor-lite` as the primary 3D backend.

Why it matches:

- modern 3D rigid body engine with broadphase, constraints, character support, and scene queries
- active upstream
- permissive license
- good reputation for game runtime performance
- practical shape for a thin in-tree C shim instead of a huge engine fork

Tradeoffs:

- core upstream is C++, not C
- wasm story is not as clean as native Zig+C wrapping
- integration work is higher than a pure C engine

### 2. PhysX

High-capability 3D option, but not the best first integration here.

Why it is interesting:

- very capable rigid body stack
- mature scene queries and character/controller support

Why it is not the first choice:

- heavier integration and build complexity than Jolt
- larger API surface to wrap and maintain
- worse fit for a small ECS-facing v1

### 3. Box2D

Strong engine, but mostly a 2D answer.

Why it is attractive:

- modern C API
- simpler dependency story than C++
- easier wasm path than 3D C++ engines

Why it is not the primary recommendation:

- `phasor-lite` is already clearly 3D-oriented
- swapping to Box2D first would create architectural churn

## Recommendation

Use Jolt as the primary native backend, but design `physics` so backend choice is not exposed to gameplay code.

Practical recommendation:

- v1 backend: `jolt`
- wasm/default fallback: `null`
- optional later backend: a simpler or 2D-specific backend if needed

## Integration Strategy

### Build Layout

Add a new public module in `phasor-lite/build.zig`:

- public module name: `physics`
- root file: `lib/physics/root.zig`

Then import it into:

- `phasor-lite/src/root.zig`
- `phasor-lite/src/root_wasm.zig`

Optional internal users may import `physics`, but `PhysicsModule` should not be re-exported as `modules.PhysicsModule`.

Target structure:

```text
phasor-lite/
  deps/
    jolt/
    physics_jolt_c/
  lib/
    physics/
      root.zig
      types.zig
      components.zig
      resources.zig
      events.zig
      queries.zig
      backend.zig
      module.zig
      authoring.zig
      backends/
        jolt.zig
        null.zig
      bake/
        root.zig
        mesh_bake.zig
        mesh_formats.zig
```

### Why A Small Owned C Shim

This repo already uses thin C dependency wrappers for `glfw`, `stb`, `cgltf`, and `miniaudio`.

The same pattern scales best here:

- keep Zig-facing bindings small
- keep the public API backend-neutral
- only expose the subset needed by the ECS module
- avoid coupling module design to a third-party wrapper surface

### ECS-Facing Design Rules

- gameplay systems talk to physics components/resources/events, not backend handles
- the module owns writeback from simulated state to ECS transforms
- scene queries needed by gameplay should be first-class APIs, not backend escape hatches
- backend-specific debug data may exist internally, but should not leak into general gameplay code

## Runtime Model

The runtime split should look like this:

1. authoring/build tools produce baked collision assets from imported scene data
2. gameplay loads those baked assets into `physics`
3. physics simulates bodies and answers scene queries
4. writeback updates ECS-visible transform state

For v1, keep runtime ownership simple:

- one physics world resource per app
- explicit body creation/destruction through components or queued commands
- one baked static scene asset loaded into the world at startup for the Sponza demo

## Non-Goals For This Branch

- full wasm parity with Jolt
- generalized networking/determinism work
- broad editor tooling
- advanced joints or ragdolls
- redoing the glTF importer stack already landed on `main`
