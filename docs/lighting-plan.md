# Lighting Plan

## Goal

Introduce an ECS-first dynamic lighting system for `phasor-lite` that:

- treats lights as ordinary ECS components/resources, not renderer-owned scene objects
- supports many dynamic lights in one scene without switching to a deferred pipeline
- works on native and wasm/WebGPU
- uses the Sponza example as the primary validation target

Static lighting is not a separate first-class goal for the initial branch. The working assumption is that a static light is just a dynamic light whose authored state does not change at runtime. If later we need offline baking, probes, or precomputed visibility, those should layer onto the same ECS-facing light model rather than replace it.

## Direction

We should not build a classic deferred renderer first.

Reasons in this codebase:

- the current renderer is already organized around a forward scene pass plus optional post-process passes
- wasm/WebGPU support raises the cost of introducing a wide G-buffer pipeline and extra bandwidth-heavy full-screen passes
- transparency, alpha-masked foliage, and mixed material paths are easier to preserve in a forward design
- Sponza validation needs dynamic point and spot lights around geometry and curtains, which fits a forward-plus path well

Recommended target architecture: clustered or tiled forward lighting, implemented incrementally.

Practical reading of that recommendation:

- branch phase 1 can start with a capped forward light list so the ECS and material APIs settle quickly
- the intended steady-state design should be forward-plus, not "naive forward forever"
- we should avoid cementing APIs that assume "exactly N global lights" or "one directional + four points"

## Current Renderer Constraints

The current renderer is not lighting-ready yet:

- render extraction only collects triangles and `render.MeshInstance`
- `RenderQueue` does not carry per-view lighting data
- scene materials imported from glTF currently preserve base color and base-color textures, but not metallic-roughness, normal, occlusion, or emissive inputs
- scene drawing is built around existing backend mesh/material/shader handles rather than a richer scene-material abstraction

That means "add lights to Sponza" actually requires three parallel tracks:

1. ECS light authoring and extraction
2. scene/material pipeline upgrade for lit 3D surfaces
3. render submission path that can evaluate many lights efficiently

## ECS-First API

Lights should be represented as components attached to entities with `Transform`.

Proposed components:

```zig
pub const Light = union(enum) {
    directional: DirectionalLight,
    point: PointLight,
    spot: SpotLight,
};

pub const LightVisibility = struct {
    enabled: bool = true,
    shadows: bool = false,
    static: bool = false,
};

pub const DirectionalLight = struct {
    color: Color.F32 = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
    illuminance_lux: f32 = 10000.0,
};

pub const PointLight = struct {
    color: Color.F32 = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
    intensity_candela: f32 = 800.0,
    range: f32 = 10.0,
    radius: f32 = 0.05,
};

pub const SpotLight = struct {
    color: Color.F32 = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
    intensity_candela: f32 = 1200.0,
    range: f32 = 15.0,
    inner_angle_rad: f32 = 0.35,
    outer_angle_rad: f32 = 0.55,
    radius: f32 = 0.05,
};
```

Notes:

- keep transform separate; position comes from `Transform.translation`, orientation from `Transform.rotation`
- keep enable/static/shadow policy separate from the physical light payload so systems can toggle behavior without mutating the authored type
- use physically named units from the start even if the first shading pass only approximates them
- avoid splitting into `PointLightColor`, `PointLightRange`, etc.; one coherent light payload is easier to author and inspect

Optional helper components/resources:

- `LightTag` or gameplay-specific tags for authored groups
- `LightAnimation` for demo motion in Sponza
- `AmbientLight` resource for a global fill term
- `ExposureSettings` resource if tone mapping/exposure lands during the same branch

## Environment Lighting

HDR panorama lighting should be a first-class part of the design, but it should not be encoded as ordinary directional or point lights.

Recommended split:

- direct lighting stays ECS-authored through `lighting.Light` entities
- environment lighting is driven by separate resources such as `lighting.EnvironmentLight` or `lighting.SkyIbl`
- later localized environment captures can layer in as probes rather than distorting the direct-light API

Why this matters:

- an HDR panorama is both a visible background source and an indirect/specular lighting source
- image-based lighting wants different preprocessing and shader inputs than direct punctual lights
- forcing panorama lighting into fake direct lights would produce the wrong API and the wrong renderer layout

Initial environment-light target:

- support an HDR panorama asset as the source for sky/background rendering
- derive diffuse irradiance and prefiltered specular environment data from the same source
- bind environment-light data per view so lit materials can consume it alongside ECS-authored direct lights

## Render-Side ECS Resources

The render module should extract authored light components into frame resources, similar to how meshes are extracted into the render queue now.

Proposed resources:

- `render.LightFrameData`
- `render.VisibleLightSet`
- `render.LightGrid` or `render.ClusteredLightGrid`

Responsibility split:

- world/ECS components remain the source of truth
- extraction builds a compact frame-local light buffer from entities
- visibility assignment builds per-view or per-cluster light lists
- submit consumes only compact render data, not arbitrary ECS queries

This keeps the public API ECS-first while preserving a renderer-friendly memory layout.

## Material Model

Sponza is not a credible lighting validation target without a lit material path.

We should move the imported scene path toward glTF metallic-roughness support:

- base color factor + texture
- normal texture
- metallic-roughness texture and factors
- occlusion texture
- emissive factor + texture
- alpha mode and double-sided handling

Recommended public-facing split:

- `render.Material` remains a lightweight instance/reference type used on entities
- add an internal `render.SceneMaterial` or equivalent packed GPU-ready material representation for lit mesh submission
- keep unlit sprite/text/triangle paths intact rather than forcing them through the lit material model
- leave room for image-based lighting inputs from HDR panoramas and future reflection probes

## Shading Path

Recommended sequence:

### Phase 1: Forward Lit Baseline

- add a lit scene shader for 3D meshes
- support one directional light plus a bounded array of point/spot lights
- get Sponza rendering with colored local lights
- no shadows yet
- keep the shader/material layout compatible with later HDR environment-light inputs

This is not the final scalability target. It is the shortest path to validate:

- ECS API shape
- glTF material data plumbing
- camera/view/light extraction
- native and wasm backend parity

### Phase 2: Forward+

- add a depth prepass or depth texture path if required by the implementation choice
- build tile/cluster assignment on the GPU if practical, or on CPU first if needed to de-risk the branch
- allow scenes with dozens to low hundreds of dynamic lights
- keep the scene pass forward-shaded using per-tile/per-cluster light lists
- add environment-light bindings that can combine HDR panorama lighting with direct-light lists

For this engine, "forward+" is the intended end state for the branch, even if implementation lands in slices.

### Phase 3: Shadows

- start with one shadowed directional light or a small number of shadowed spot lights
- keep shadows optional and separate from the initial lighting milestone

Shadows should not block the first lighting merge unless the branch explicitly expands scope.

## ECS and Module Layout

Recommended new module boundary:

- `lib/modules/LightingModule.zig`

Likely subfiles:

- `lib/modules/lighting/components.zig`
- `lib/modules/lighting/resources.zig`
- `lib/modules/lighting/extract.zig`
- `lib/modules/lighting/cull.zig`
- `lib/modules/lighting/debug.zig`

Render integration points:

- `lib/modules/render/extract.zig`
- `lib/modules/render/submit.zig`
- new render-side light/material shader support in `lib/render/*`

The lighting module should own ECS registration and frame extraction, while the render module remains the final consumer during submission.

## Sponza Verification Plan

Sponza should become the branch proving ground.

Verification target:

- one sun-like directional light through the atrium
- multiple colored point lights placed in arches, hallways, and side rooms
- at least a few animated lights to prove dynamic updates, not just static authoring
- mixed warm/cool light colors to expose normal/material mistakes quickly
- preserve the current FPS controller and collision setup for walk-through inspection

Suggested authored scene set:

1. One white-gold directional light angled downward across the central hall.
2. Six to twelve colored point lights near columns and alcoves.
3. Two or more spot lights aimed across long sightlines.
4. A small number of animated lights:
   - slow hue/intensity pulse
   - small orbital motion around a column

Success criteria:

- Sponza is visibly lit by authored ECS lights rather than a constant tint
- moving a light entity changes the scene immediately
- disabling a light via ECS state removes its contribution without rebuilds
- wasm and native both render the same authored light setup
- performance remains acceptable with the target authored light count

## Implementation Slices

### Slice 1: Branch scaffolding and ECS API

- create `LightingModule`
- add light components/resources
- add a minimal `examples/sponza` light authoring layer
- no rendering change required beyond debug visibility if helpful

### Slice 2: Lit material and scene import plumbing

- extend glTF material parsing/storage
- add GPU-ready material packing for lit meshes
- preserve existing unlit paths for 2D/UI
- shape the material/shader data so HDR panorama IBL can slot in without another public API reset

### Slice 3: Forward lit mesh path

- add lit mesh shader(s)
- extract visible lights per frame
- render Sponza with bounded dynamic lights

### Slice 4: Scale path to forward+

- add per-view tiled/clustered light assignment
- remove hard-coded small-light assumptions from slice 3
- validate a heavier Sponza light set

### Slice 5: Polish

- debug visualization for light volumes or cluster occupancy
- authoring helpers/utilities
- HDR panorama environment lighting and visible sky integration, if it does not land earlier
- optional first shadow path

## Side Quest: Background Loading and Progress

The branch should also leave room for a responsive loading-screen path for heavy scene setup such as Sponza import, collision baking, HDR preprocessing, and future lighting data preparation.

Recommended direction:

- implement a background loading mechanism that communicates over a typed `Channel(T)`
- keep the loading UI and main frame loop responsive while asset and scene preparation work runs in the background
- model progress as structured messages rather than polling opaque global state

Suggested shape:

```zig
pub fn Channel(comptime T: type) type { ... }

pub const LoadProgress = union(enum) {
    stage_begin: struct { name: []const u8, total_work: ?u32 = null },
    stage_progress: struct { name: []const u8, completed: u32, total: ?u32 = null },
    stage_complete: struct { name: []const u8 },
    failed: struct { message: []const u8 },
    finished,
};
```

Target behavior:

- background jobs publish progress and completion messages into `Channel(LoadProgress)`
- ECS/UI systems consume those messages on the main thread and update a loading overlay
- jobs can publish coarse stage progress immediately, then finer-grained counts when available
- the same mechanism can later support scene import, HDR environment preprocessing, and mesh/light baking tasks

Constraints:

- no direct world mutation from background worker threads
- background jobs should emit data and progress, then hand final world/apply work back to the main thread
- progress messages should be durable enough to drive logs, overlays, and automated loading diagnostics

## API Guardrails

We should keep these constraints explicit during implementation:

- no renderer-owned imperative API like `renderer.addPointLight(...)`
- no special "static light" type until there is real baked/static-only data that justifies it
- no deferred-only material assumptions in ECS components
- no design that excludes alpha-masked materials from receiving lighting
- no branch-local Sponza hacks that bypass the general ECS/light extraction path
- no fake "HDR sky as a directional light bundle" shortcut in the public API

## Open Questions

These should be answered early in implementation:

1. Do we want a true PBR target immediately, or a simpler physically-inspired lit model first with a later material upgrade?
2. Should forward+ light assignment start on CPU for simplicity, then move to GPU, or is GPU-side WebGPU compute already mature enough in the current backend?
3. Do we want exposure and tone mapping in scope for the first lit Sponza pass?
4. Should emissive materials participate only as self-lit surfaces initially, or also seed authored local light placement in the example?

## Recommended Branch Objective

For `codex/lighting`, the concrete branch objective should be:

"Land an ECS-authored dynamic lighting system with a forward-oriented lit 3D material path, demonstrated in Sponza with multiple colored dynamic lights on native and wasm, without introducing a deferred renderer."

That objective is narrow enough to execute and broad enough to leave room for the right forward-plus implementation once the ECS and material foundations are in place.
