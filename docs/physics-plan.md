# Physics + Sponza Roadmap

Status: authoritative branch roadmap

Branch: `codex/physics`

Merge note:

- delete this roadmap before merging `codex/physics`
- it is a branch execution document, not intended as durable merged docs

## Branch Outcome

This branch is complete when all of the following are true:

- `phasor-lite` exposes a standalone public `physics` module with a backend-neutral gameplay API
- a native backend exists that supports static scene collision, rigid bodies needed for gameplay, and scene queries
- Sponza collision is baked ahead of runtime from the existing glTF scene pipeline
- a native command such as `zig build run-sponza-fps` launches a basic FPS walkthrough in Sponza
- Sponza assets are fetched on first use and are not vendored into git

## Starting Point

The branch starts from a `main` that already has:

- `cgltf` integrated under `assets`
- a neutral glTF scene data model
- an `examples/gltf` sample that loads FlightHelmet
- enough mesh and texture import support to render real imported content

That means the remaining branch-critical path is now:

1. finalize the public `physics` module boundary
2. integrate the first real backend for native builds
3. define and ship offline collision baking for imported scenes
4. wire baked collision into gameplay
5. finish at the native Sponza FPS demo

glTF work is no longer phase one of this branch.
It is an existing dependency that the physics branch should reuse rather than re-litigate.

## Architectural Decisions

These decisions are fixed for this branch unless a concrete blocker appears.

### Physics backend

- primary native backend: Jolt
- backend ownership lives under `lib/physics/` and `deps/physics_jolt_c/`
- gameplay must not depend on raw Jolt handles

### Scene import dependency

- the existing `assets.gltf` pipeline on `main` is the source scene format for collision baking
- no importer replacement should be attempted on this branch unless it blocks collision bake correctness

### Module boundaries

- `physics` owns simulation-facing components, resources, events, queries, and collision assets
- `assets` owns glTF parsing, scene/model asset loading, and image/material resolution
- `render` owns renderer-native mesh/material/texture resources
- build tooling owns offline fetch and collision baking

### Threading

- ECS world mutation remains main-thread only
- renderer-facing resources remain main-thread only
- worker-thread handoff uses `std.Io.Queue` through `common.Channel(T)`

### Sponza asset policy

- do not vendor Sponza assets
- fetch them on first use from the Khronos sample asset repository
- keep downloaded assets under a local ignored cache, not tracked source

## Minimum Feature Set

This is the minimum scope required to hit the branch goal.
Anything outside this list is explicitly out of scope for the first pass.

### Physics features required for Sponza FPS

- static triangle-mesh collision
- dynamic or kinematic capsule controller body
- gravity
- sweep or raycast queries for grounded checks and FPS interaction
- transform writeback into ECS
- deterministic-enough behavior for local gameplay debugging

### Physics features out of scope for first pass

- ragdolls
- joints/constraints beyond what is needed for the controller
- destructible geometry
- soft bodies
- network determinism
- wasm feature parity with the native backend

### Bake pipeline requirements

- consume imported scene data from the existing glTF pipeline
- extract static collision meshes into a backend-neutral baked format
- write one baked file per scene
- support incremental rebuilds
- keep runtime startup free of large collision rebuild work

## Repository Layout Target

```text
phasor-lite/
  deps/
    jolt/
    physics_jolt_c/
  lib/
    assets/
      gltf/
        root.zig
        scene.zig
        parse.zig
    common/
      channel.zig
    physics/
      root.zig
      components.zig
      resources.zig
      events.zig
      queries.zig
      backend.zig
      module.zig
      authoring.zig
      backends/
        null.zig
        jolt.zig
      bake/
        root.zig
        mesh_bake.zig
        mesh_formats.zig
  tools/
    fetch_sponza.zig
    bake_collision.zig
```

## Build Commands

The branch should add explicit commands with predictable behavior.

Required build steps:

- `zig build fetch-sponza`
- `zig build bake-sponza-collision`
- `zig build run-sponza-fps`

Behavior requirements:

- `fetch-sponza` performs network access only when cache is missing or explicitly refreshed
- `bake-sponza-collision` is incremental
- `run-sponza-fps` fails with a clear message if the fetch step has not run and auto-fetch is disabled
- unrelated builds must not silently fetch network assets

Recommended cache layout:

```text
phasor-lite/local/cache/sponza/
  source/
    glTF-Sample-Assets/...
  baked/
    Sponza.physics
```

## Phase Plan

Each phase has a purpose, concrete outputs, and a gate for moving forward.

### Phase 0: Branch Stabilization

Purpose:

- keep the branch buildable while physics foundations move

Work:

- keep `physics` as a standalone public module
- do not re-export `PhysicsModule` from `modules`
- keep existing glTF and render paths passing while physics lands

Gate:

- `zig build test` passes
- any remaining failures are explicitly identified as pre-existing or unrelated

### Phase 1: Public Physics Surface

Purpose:

- define the public API shape before backend-specific detail spreads

Work:

- finalize `physics/root.zig`
- define core components, resources, events, and queries
- keep backend handles private to backend code
- decide how the existing FPS helper maps onto the new module

Gate:

- gameplay code can depend on `physics` without backend-specific imports
- a null backend compiles for wasm and non-physics test paths

### Phase 2: Native Backend Integration

Purpose:

- make the module real on native targets

Work:

- add `deps/jolt/` and the small owned `deps/physics_jolt_c/` shim
- implement backend init, world lifecycle, body creation, and scene queries
- establish the minimum debug and error-reporting story for native integration

Gate:

- native tests and examples compile and run with the new backend enabled
- a simple body/ground test demonstrates gravity and collision

### Phase 3: Collision Baking

Purpose:

- convert imported scene geometry into physics-ready runtime data

Work:

- define the baked collision file format
- add extraction from neutral glTF scene data
- add `zig build bake-sponza-collision`
- keep the bake format backend-neutral even if Jolt is the first consumer

Gate:

- Sponza collision can be baked once and loaded at runtime without recomputing
- bake output has versioning and basic validation

### Phase 4: FPS Integration

Purpose:

- replace the temporary ad-hoc path with the real physics module

Work:

- migrate the FPS controller path onto `physics`
- load baked Sponza collision at startup
- support movement, grounded checks, and stable wall/floor collision

Gate:

- a simple native Sponza walkthrough works end to end

### Phase 5: Demo Polish

Purpose:

- make the branch outcome usable and reviewable

Work:

- add the `run-sponza-fps` command
- document fetch prerequisites and failure modes
- tighten startup diagnostics for missing assets or missing bake outputs

Gate:

- branch acceptance demo is reproducible from a clean checkout plus explicit fetch step
