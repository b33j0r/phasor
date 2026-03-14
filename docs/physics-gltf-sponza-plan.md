# Physics + glTF + Sponza Roadmap

Status: authoritative branch roadmap

Branch: `codex/physics`

Merge note:

- delete this roadmap before merging `codex/physics`
- it is a branch execution document, not intended as durable merged docs

## Branch Outcome

This branch is complete when all of the following are true:

- `phasor-lite` exposes a standalone public `physics` module
- `phasor-lite` has a `gltf` example that loads a Khronos sample model with materials
- `phasor-lite` can import static glTF scenes needed for Sponza
- static collision for Sponza is baked ahead of runtime
- Sponza assets are fetched on first use and are not vendored into git
- a native command such as `zig build run-sponza-fps` launches a basic FPS walkthrough in Sponza

## Architectural Decisions

These decisions are fixed for this branch unless we hit a concrete blocker.

### Physics backend

- primary native backend: Jolt
- backend ownership lives under `lib/physics/` and `deps/physics_jolt_c/`
- gameplay must not depend on raw Jolt handles

### Scene import

- primary importer implementation for this branch: `cgltf`
- Assimp is reference material only, using `../phasor-vulkan`
- `fastgltf` is the technically stronger glTF library overall, but not the right first integration for this repo because it introduces a new C++17 dependency surface before the asset pipeline is stable

### Module boundaries

- `physics` owns simulation-facing components, resources, queries, and collision assets
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
- use the glTF sample asset path rooted at:
  - [KhronosGroup/glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets)
  - `Models/Sponza/glTF/Sponza.gltf`
- keep downloaded assets under a local ignored cache, not tracked source

### Khronos sample asset repo policy

- do not vendor the full Khronos sample asset repository into `phasor-lite`
- keep a developer checkout at:
  - `~/Projects/phasor/vendor/glTF-Sample-Assets`
- use that checkout for manual inspection and pre-Sponza rendering work
- the first example target should use:
  - `Models/FlightHelmet/glTF/FlightHelmet.gltf`

## Minimum Feature Set

This is the minimum scope required to hit the branch goal. Anything outside this list is explicitly out of scope for the first pass.

### glTF features required for Sponza

- `.gltf` with external `.bin`
- external PNG or JPG textures
- node hierarchy
- per-node transforms
- one mesh with many primitives
- positions
- normals
- UV0
- indices
- material base color textures
- alpha modes:
  - opaque
  - mask
  - blend
- double-sided flag

### glTF features explicitly out of scope for first pass

- skinning
- animation
- morph targets
- punctual lights extensions
- cameras embedded in glTF
- full metallic-roughness shading parity
- transmission, clearcoat, volume, or other advanced extensions

### Physics features required for Sponza FPS

- static triangle-mesh collision
- dynamic or kinematic capsule controller body
- gravity
- sweep or raycast queries for grounded checks and FPS interaction
- transform writeback into ECS

### Physics features out of scope for first pass

- ragdolls
- joints/constraints beyond what is needed for the controller
- destructible geometry
- soft bodies
- network determinism

## Repository Layout Target

```text
phasor-lite/
  deps/
    cgltf/
      cgltf.h
      root.zig
      cgltf_impl.c
    jolt/
    physics_jolt_c/
  lib/
    assets/
      gltf/
        root.zig
        scene.zig
        parse.zig
        resolve_buffers.zig
        resolve_images.zig
        convert_scene.zig
    common/
      channel.zig
    physics/
      root.zig
      components.zig
      resources.zig
      events.zig
      queries.zig
      module.zig
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

## Runtime Data Model

### glTF-neutral scene model

The importer should first produce engine-neutral scene data, not renderer-native handles.

Required neutral types:

- `SceneData`
- `NodeData`
- `MeshData`
- `PrimitiveData`
- `MaterialData`
- `ImageData`
- `TextureRef`

That matches the successful separation in `../phasor-vulkan`: thin foreign wrapper, then conversion into neutral data.

### Collision data model

The bake step should output a compact physics-facing blob, not raw imported glTF arrays.

Required baked concepts:

- scene AABB
- list of static collision meshes
- triangle/index data in backend-neutral bake format
- optional named collision groups or layers

For v1, the baked format should be simple and owned:

- header with version and counts
- contiguous vertex and index arrays
- one file per scene

No generic asset database format is needed for this branch.

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

- keep the branch buildable while foundations are moving

Work:

- finish `common.Channel(T)` as the shared queue abstraction
- keep `physics` as a standalone public module
- do not re-export `PhysicsModule` from `modules`
- isolate unrelated existing failures from new regressions

Gate:

- new channel and physics scaffolding compile
- any remaining test failures are explicitly identified as pre-existing or unrelated

### Phase 1: glTF Import Skeleton

Purpose:

- establish the asset pipeline boundary before physics/backend work expands

Work:

- add thin `cgltf` dependency wrapper
- add `lib/assets/gltf/` module structure
- parse:
  - nodes
  - transforms
  - meshes
  - primitives
  - materials
  - images
  - buffers
- support both `.gltf` and `.glb`

Gate:

- a small sample scene loads into neutral `SceneData`
- unit or smoke tests cover multi-primitive meshes and external resource resolution

### Phase 2: Renderable Scene Conversion

Purpose:

- get imported scenes visible in `phasor-lite`

Work:

- convert neutral scene data into engine mesh/material/texture assets
- support ECS spawning for imported node hierarchy
- preserve parent-child transforms using existing `Parent` and `LocalTransform`
- support base-color textured opaque and alpha-tested surfaces
- add `examples/gltf/` as the pre-Sponza import example
- load the Khronos `FlightHelmet` sample from the external checkout
- place it at the camera center and rotate it so material correctness is easy to inspect

Gate:

- `zig build run-gltf` renders the Khronos `FlightHelmet` sample with materials on native
- multi-primitive materials render on the right primitives
- imported hierarchy spawn uses `Parent` and `LocalTransform`, not glTF-specific runtime coupling

### Phase 3: Sponza Fetch Pipeline

Purpose:

- make Sponza setup reproducible without vendoring assets

Work:

- add `fetch-sponza` tool/build step
- fetch from Khronos sample assets repo into ignored local cache
- document source and cache behavior

Gate:

- a clean checkout can prepare local Sponza assets with one explicit command

### Phase 4: Collision Bake Pipeline

Purpose:

- eliminate runtime rebuild cost for large static collision scenes

Work:

- define collision-tagging convention in glTF:
  - preferred: extras metadata
  - acceptable fallback: `COL_` name prefix
- add bake tool that extracts tagged collision geometry
- emit owned `.physics` blob format
- keep bake incremental based on source timestamps or content hash

Gate:

- collision bake produces a reusable file for Sponza
- runtime can load baked collision data without reparsing raw glTF geometry for physics

### Phase 5: Jolt Backend Integration

Purpose:

- make `physics` useful against real static scene data

Work:

- add owned C shim over Jolt
- support:
  - static triangle mesh bodies
  - dynamic bodies
  - kinematic target updates
  - capsule controller shape
  - raycast and sweep query path
- keep ECS-facing API backend-neutral

Gate:

- static baked scene geometry can be registered with physics
- a capsule body can move, collide, and remain grounded on static geometry

### Phase 6: FPS Controller Layer

Purpose:

- replace the current ad-hoc prototype with a layered controller built on `physics`

Work:

- migrate useful behavior from `FpsPhysicsModule`
- implement:
  - mouse look
  - move intent
  - jump
  - coyote time if still desired
  - grounded checks via physics queries
- keep this controller as a higher-level helper on top of `physics`, not inside the backend

Gate:

- FPS movement works in a small test scene before using Sponza

### Phase 7: Sponza FPS Demo

Purpose:

- deliver the branch goal

Work:

- add example or run target for Sponza FPS
- render imported Sponza scene
- load baked Sponza collision
- install camera/controller/gameplay loop
- add a minimal HUD or debug overlay only as needed

Gate:

- `zig build run-sponza-fps` launches a stable walkthrough demo on native

## Testing Strategy

Testing should be attached to each phase, not deferred to the end.

### Unit-level

- `common.Channel(T)` behavior
- glTF buffer and image resolution
- glTF node transform composition
- collision bake serialization and deserialization
- physics resource/component lifecycle

### Asset smoke tests

- one tiny local glTF fixture
- one multi-primitive fixture
- one alpha-masked material fixture

### End-to-end smoke tests

- import and render a small sample scene
- import and render the Khronos `FlightHelmet` sample through `run-gltf`
- bake and load collision for a small sample scene
- FPS controller in a tiny room scene before Sponza

### Final branch verification

- fetch Sponza from clean cache
- bake Sponza collision from clean cache
- launch native Sponza FPS example

## Risks And Mitigations

### Risk: glTF importer grows into a renderer rewrite

Mitigation:

- keep importer output neutral
- only support the Sponza-required feature set in this branch

### Risk: collision bake format becomes prematurely generic

Mitigation:

- use one simple owned format for this branch
- version it from the start

### Risk: Jolt integration dominates the schedule

Mitigation:

- finish import, bake, and a tiny collision test scene before full Sponza work
- keep controller logic out of backend bindings

### Risk: Sponza visual fidelity requirements expand uncontrollably

Mitigation:

- branch goal is a simple FPS walkthrough, not a full PBR renderer overhaul
- prioritize correctness of scene loading and traversal over full material parity

## Non-Goals For This Branch

- full PBR material parity with reference engines
- wasm parity for the Sponza FPS demo
- generalized scene editor tooling
- skeletal animation support
- generic importer support beyond glTF/GLB
- fully asynchronous asset streaming

## Immediate Next Steps

The next execution steps, in order, are:

1. Finish Phase 0 by stabilizing `common.Channel(T)` and the standalone `physics` module export path.
2. Implement Phase 1 with a thin `cgltf` wrapper and neutral `SceneData`.
3. Add a tiny importer smoke-test scene before touching Sponza.
4. Add `run-gltf` with the Khronos `FlightHelmet` sample before touching Sponza.
5. Only after that, add Sponza fetch and collision bake steps.
