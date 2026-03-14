# Physics Module Proposal

Status: proposed architecture reference

Scope: new public `physics` Zig module for `phasor-lite`, designed to split into its own repo later without dragging `modules/`, `platform`, or renderer along with it.

Merge note:

- delete this planning/proposal doc before merging `codex/physics`
- only keep extracted durable documentation if it is still useful after implementation lands

Execution plan:

- branch sequencing and delivery gates live in [physics-gltf-sponza-plan.md](/Users/brian/Projects/phasor/phasor-lite/docs/physics-gltf-sponza-plan.md)
- this document is the architecture and API reference for the `physics` side of that roadmap

## Summary

Recommended path:

1. Build a new public `physics` module with an ECS-first API and a backend interface.
2. Keep cross-thread communication consistent with `Commands`, `ecs.Events(T)`, and metrics by standardizing on `std.Io.Queue` behind a reusable `Channel(T)` abstraction.
3. Add glTF scene import as a parallel workstream under `assets`, because the branch target is an FPS demo in Sponza.
4. Use Jolt Physics as the primary 3D backend for native targets.
5. Keep the current ad-hoc `FpsPhysicsModule` only as a temporary gameplay helper, then migrate it onto `physics`.
6. Do not make wasm parity a design blocker for v1. Keep wasm behind a fallback backend or feature gate until the native API stabilizes.

This fits the current project direction better than forcing a physics engine choice directly into `lib/modules/`.

## Why This Should Be A Separate Public Module

Current `phasor-lite` structure already separates durable subsystems into module roots such as `common`, `ecs`, `render`, and `gui`, and exports the main public surface with `b.addModule("phasor", ...)`.

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

## Engine Shortlist

The shortlist below is based on official upstream docs/repos as checked on 2026-03-14.

### 1. Jolt Physics

Best fit for `phasor-lite` as the primary 3D backend.

Why it matches:

- modern 3D rigid body engine with broadphase, constraints, character support, and scene queries
- active upstream with a current release line
- permissive license
- good reputation for game runtime performance
- practical shape for a thin in-tree C shim instead of a huge engine fork

Tradeoffs:

- core upstream is C++, not C
- wasm story is not as clean as native Zig+C wrapping
- integration work is higher than a pure C engine

Use it if:

- 3D matters more than immediate wasm parity
- you want a serious long-term physics backend, not a stopgap

Official sources:

- [JoltPhysics README](https://raw.githubusercontent.com/jrouwe/JoltPhysics/master/README.md)
- [JoltPhysics release page](https://github.com/jrouwe/JoltPhysics/releases)
- [JoltPhysics.js README](https://raw.githubusercontent.com/jrouwe/JoltPhysics.js/main/README.md)

### 2. NVIDIA PhysX 5

High-capability 3D option, but not the best first integration for this codebase.

Why it is interesting:

- very capable rigid body stack
- mature scene queries and character/controller support
- large feature surface for future ambitious projects

Why it is not the first choice here:

- much heavier integration and build complexity than Jolt
- larger API surface to wrap and maintain
- worse fit for a small, human-friendly ECS-facing module v1
- wasm path is not an obvious first-class upstream story

Use it if:

- you explicitly want a heavyweight long-term engine and accept slower integration

Official sources:

- [PhysX README](https://raw.githubusercontent.com/NVIDIA-Omniverse/PhysX/main/README.md)
- [PhysX docs](https://nvidia-omniverse.github.io/PhysX/)

### 3. Box2D 3.x

Excellent engine, but mainly a 2D answer.

Why it is attractive:

- modern C API
- handle-based design maps well to ECS ownership
- simpler dependency story than C++
- easier wasm path than 3D C++ engines

Why it is not the primary recommendation:

- `phasor-lite` is already clearly 3D-oriented
- replacing a future 3D engine decision with Box2D would create architectural churn

Use it if:

- you decide to add a separate 2D physics module
- wasm-first 2D matters more than 3D

Official sources:

- [Box2D README](https://raw.githubusercontent.com/erincatto/box2d/main/README.md)
- [Box2D documentation](https://box2d.org/documentation/)

### 4. ReactPhysics3D

Reasonable fallback if you want a smaller 3D integration than Jolt.

Why it is viable:

- smaller and simpler than PhysX
- adequate 3D rigid body feature set for many games

Why it is not the primary recommendation:

- less compelling long-term upside than Jolt
- lower ecosystem momentum than Jolt or PhysX

Official source:

- [ReactPhysics3D README](https://raw.githubusercontent.com/DanielChappuis/reactphysics3d/master/README.md)

## glTF Import Plan

The branch goal now explicitly includes an FPS demo in Sponza, so scene import is part of the critical path.

Recommended importer strategy:

- first choice: `cgltf`
- reference implementation: the Assimp wrapper in `../phasor-vulkan`
- not recommended as the default: Assimp-first public API

Reasoning:

- glTF/GLB is the concrete target format
- `cgltf` matches the current thin-C-wrapper dependency style better than a larger C++ importer stack
- Assimp remains useful as a fallback and migration reference if you later need broader format coverage

Use this separation:

- `assets` parses glTF scenes and resolves buffers/images/materials
- `render` consumes visual meshes/materials/textures
- `physics` consumes baked static collision data generated from imported scenes

## Recommendation

Use Jolt as the primary native backend, but design `physics` so backend choice is not exposed to gameplay code.

Practical recommendation:

- v1 backend: `jolt`
- optional later backend: `box2d` in a separate `physics2d` or `physics_box2d` module
- do not start with PhysX
- do not bind gameplay directly to raw engine handles

Reasoning:

- your current code already has 3D transforms, quaternions, cameras, and an FPS collision prototype
- a 3D-first engine avoids rebuilding the API twice
- Jolt gives you a better long-term ceiling without forcing PhysX-level complexity

## Integration Strategy

### Build Layout

Add a new public module in `phasor-lite/build.zig`:

- `PhysicsModuleLib`
- `moduleBundlePublic("physics", "lib/physics/root.zig", imports)`

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
        simple.zig
```

Notes:

- `deps/jolt/` is upstream source
- `deps/physics_jolt_c/` is your small owned C shim exposing only what `physics` needs
- prefer an owned shim over a third-party wrapper so the future repo split keeps stable API control
- add a reusable `common.Channel(T)` or `common.channel.Channel(T)` instead of introducing a physics-only queue wrapper

### Why A Small Owned C Shim

This repo already uses thin C dependency wrappers for `glfw`, `stb`, and `miniaudio`.

The same pattern scales best here:

- keep Zig-facing bindings small
- keep the public API backend-neutral
- only expose the subset needed by the ECS module
- avoid coupling module design to someone else’s wrapper design

For Jolt, that means:

- one small C layer compiled inside the build
- no raw C++ surface leaking into Zig gameplay code
- explicit functions for body creation, body mutation, stepping, contact extraction, and scene queries

## Channel(T) Generalization

There are already three separate `std.Io.Queue` usage patterns in this codebase:

- `ecs.App` command batching
- `ecs.Events(T)` subscriptions
- `metrics.Bus`

That is enough repetition to justify a first-class generic channel abstraction.

Recommendation:

- add `common.Channel(T)` as a small owned wrapper around `std.Io.Queue(T)`
- let higher-level systems compose policy on top of it instead of each subsystem owning queue boilerplate

Target shape:

```zig
pub fn Channel(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        io: *const std.Io,
        queue: std.Io.Queue(T),
        buffer: []T,

        pub fn init(allocator: std.mem.Allocator, io: *const std.Io, capacity: usize) !@This() { ... }
        pub fn deinit(self: *@This()) void { ... }
        pub fn close(self: *@This()) void { ... }
        pub fn send(self: *@This(), value: T) !void { ... }
        pub fn trySend(self: *@This(), value: T) !bool { ... }
        pub fn recv(self: *@This()) !T { ... }
        pub fn tryRecv(self: *@This()) ?T { ... }
        pub fn sendSlice(self: *@This(), values: []const T) !usize { ... }
    };
}
```

Keep it minimal:

- ownership of queue buffer
- blocking and non-blocking send/recv helpers
- close semantics
- no ECS-specific behavior inside the type

Then refactor gradually:

- `ecs.App` command queue can become `Channel(CommandBatch)`
- `metrics.Bus` can own `Channel(metrics.Event)`
- `ecs.Events(T)` can compose `Channel(T)` per subscriber instead of open-coding queue storage
- `physics` can use request/result channels immediately

This is the right consistency point for `Commands`, renderer-facing systems, and future worker-backed modules.

## ECS-First API Design

The API should be entity-driven, not world-handle-driven.

Gameplay code should say:

- this entity has a dynamic body
- this entity has a capsule collider
- this entity is kinematic
- this entity receives trigger/contact events

Gameplay code should not say:

- create body in world X
- store engine body pointer here
- manually mirror transforms each frame

### User-Facing Components

Initial proposed components:

```zig
pub const Body = struct {
    kind: Kind = .Dynamic,
    gravity_scale: f32 = 1.0,
    linear_damping: f32 = 0.0,
    angular_damping: f32 = 0.05,
    allow_sleep: bool = true,
    is_ccd: bool = false,

    pub const Kind = enum {
        Static,
        Dynamic,
        Kinematic,
    };
};

pub const Collider = struct {
    shape: Shape,
    material: Material = .{},
    collision: CollisionFilter = .{},
    is_sensor: bool = false,
    density: f32 = 1.0,
};

pub const Velocity = struct {
    linear: common.Vec3 = .{},
    angular: common.Vec3 = .{},
};

pub const MassProperties = struct {
    mode: Mode = .Auto,
    mass: f32 = 1.0,

    pub const Mode = enum {
        Auto,
        Explicit,
    };
};

pub const LockAxes = struct {
    translation_x: bool = false,
    translation_y: bool = false,
    translation_z: bool = false,
    rotation_x: bool = false,
    rotation_y: bool = false,
    rotation_z: bool = false,
};

pub const KinematicTarget = struct {
    transform: common.Transform,
    linear_velocity_hint: common.Vec3 = .{},
    angular_velocity_hint: common.Vec3 = .{},
};
```

Shape authoring:

```zig
pub const Shape = union(enum) {
    Sphere: struct { radius: f32 },
    Capsule: struct { radius: f32, half_height: f32 },
    Box: struct { half_extents: common.Vec3 },
    Cylinder: struct { radius: f32, half_height: f32 },
    ConvexHull: ConvexHullAssetHandle,
    TriangleMesh: TriangleMeshAssetHandle,
    Compound: CompoundShapeHandle,
};
```

Supporting internal components:

- `BodyHandle`: backend-owned opaque handle
- `PhysicsDirty`: authoring changed and backend object must be rebuilt or patched
- `PhysicsDisabled`: explicit opt-out without removing authoring components
- `PreviousTransform`: optional interpolation support

### Resources

```zig
pub const Config = struct {
    backend: Backend = .Jolt,
    fixed_dt: f32 = 1.0 / 60.0,
    max_substeps: u8 = 4,
    max_frame_dt: f32 = 0.25,
    gravity: common.Vec3 = .{ .x = 0.0, .y = -9.81, .z = 0.0 },
    writeback_mode: WritebackMode = .AuthoritativeToTransform,
    execution: Execution = .MainThread,

    pub const Backend = enum {
        Jolt,
        Null,
        Simple,
    };

    pub const WritebackMode = enum {
        AuthoritativeToTransform,
        InterpolatedToTransform,
    };

    pub const Execution = enum {
        MainThread,
        WorkerThread,
    };
};

pub const World = struct {
    backend: backend.BackendWorld,
};

pub const StepState = struct {
    accumulator: f32 = 0.0,
    alpha: f32 = 0.0,
    steps_last_frame: u8 = 0,
};

pub const Stats = struct {
    body_count: u32 = 0,
    active_body_count: u32 = 0,
    contact_count: u32 = 0,
    broadphase_pairs: u32 = 0,
    step_ms: f32 = 0.0,
};

pub const WorkerChannels = struct {
    requests: common.Channel(PhysicsRequest),
    results: common.Channel(PhysicsResult),
};
```

### Events

Physics should emit ECS events/resources instead of forcing polling:

```zig
pub const ContactBegan = struct {
    a: ecs.Entity.Id,
    b: ecs.Entity.Id,
    normal: common.Vec3,
};

pub const ContactEnded = struct {
    a: ecs.Entity.Id,
    b: ecs.Entity.Id,
};

pub const TriggerEntered = struct {
    sensor: ecs.Entity.Id,
    other: ecs.Entity.Id,
};

pub const TriggerExited = struct {
    sensor: ecs.Entity.Id,
    other: ecs.Entity.Id,
};
```

Add richer hit/manifold events later if they pay for themselves.

### Query API

Scene queries should be resource-driven helpers, not global free functions:

```zig
pub const RaycastQuery = struct {
    origin: common.Vec3,
    direction: common.Vec3,
    max_distance: f32,
    filter: CollisionFilter = .{},
};

pub const RaycastHit = struct {
    entity: ecs.Entity.Id,
    position: common.Vec3,
    normal: common.Vec3,
    fraction: f32,
};

pub const Queries = struct {
    pub fn raycast(self: *const @This(), q: RaycastQuery) ?RaycastHit { ... }
    pub fn overlapSphere(self: *const @This(), center: common.Vec3, radius: f32, filter: CollisionFilter) []const ecs.Entity.Id { ... }
    pub fn sweepCapsule(...) ?SweepHit { ... }
};
```

This API is friendlier to ECS systems:

```zig
fn aimSystem(physics_queries: Res(physics.Queries)) void {
    _ = physics_queries.ptr.raycast(.{
        .origin = .{ .x = 0, .y = 1, .z = 0 },
        .direction = .{ .x = 0, .y = 0, .z = -1 },
        .max_distance = 200.0,
    });
}
```

## Main Thread / Worker Thread Boundary

Physics integration must stay consistent with how `Commands` works today:

- systems build typed intents on the main thread
- those intents are queued
- another stage drains and applies them deterministically

Apply the same model to physics.

### Rule

Only the main thread may mutate ECS world state or renderer-facing resources.

The worker thread may:

- own backend physics world state
- consume physics request batches
- step simulation
- emit result batches

The worker thread may not:

- touch `ecs.World`
- touch `Commands`
- touch renderer resources
- mutate `common.Transform` directly

### Physics Requests

Main thread sends request batches to the worker:

```zig
pub const PhysicsRequest = union(enum) {
    CreateBody: CreateBodyRequest,
    DestroyBody: ecs.Entity.Id,
    UpdateBody: UpdateBodyRequest,
    UpdateCollider: UpdateColliderRequest,
    Step: StepRequest,
    Raycast: RaycastRequest,
    Shutdown,
};
```

These are generated from ECS-authoring diffs during `PhysicsSyncIn`.

### Physics Results

Worker sends result batches back:

```zig
pub const PhysicsResult = union(enum) {
    BodyState: BodyStateResult,
    ContactBegan: ContactBegan,
    ContactEnded: ContactEnded,
    TriggerEntered: TriggerEntered,
    TriggerExited: TriggerExited,
    RaycastResult: RaycastResult,
    Stats: Stats,
    StepComplete: StepComplete,
};
```

These are drained on the main thread during `PhysicsEvents` and `PhysicsSyncOut`.

### Why This Matches Renderer And Commands

Renderer consistency:

- renderer keeps consuming `Transform` and render resources on the main thread only
- physics writeback happens before `Update`/`Render`, so render sees stable state

Commands consistency:

- `Commands` already treats structural world mutation as queued work
- physics can follow the same shape with typed request/result batches
- the difference is only that the queue crosses a thread boundary

## Ownership Model

The critical API decision is transform ownership.

Use this rule:

- static bodies: authored from `Transform`, then backend-owned until edited
- kinematic bodies: ECS owns target pose, physics consumes it
- dynamic bodies: physics owns pose after stepping, then writes back to `Transform`

This avoids the common ECS physics failure mode where both gameplay and physics mutate `Transform` every frame.

Recommended v1 writeback model:

1. Read authored component changes into backend objects.
2. Step fixed simulation.
3. Drain worker results and write dynamic body transforms and velocities back into ECS on the main thread.
4. Run gameplay systems that consume resolved physics state.

## Schedule Design

Add explicit physics schedules instead of hiding everything in `Update`.

Recommended chain:

- `PhysicsSyncIn`
- `PhysicsStep`
- `PhysicsEvents`
- `PhysicsSyncOut`

Insert them between `BeforeFrame` and `Update`:

```text
BeforeFrame -> PhysicsSyncIn -> PhysicsStep -> PhysicsEvents -> PhysicsSyncOut -> Update -> Render
```

Why this order:

- time/input modules can run first
- main thread can push request batches before stepping
- worker results can be drained before gameplay reads state
- gameplay sees final body state during `Update`
- rendering reads a stable `Transform`

This also leaves room later for:

- `GameplayPrePhysics`
- `GameplayPostPhysics`
- background physics stepping once schedule affinity matures

## Public Module Shape

Target public surface in `lib/physics/root.zig`:

```zig
pub const types = @import("types.zig");
pub const components = @import("components.zig");
pub const resources = @import("resources.zig");
pub const events = @import("events.zig");
pub const queries = @import("queries.zig");

pub const Body = components.Body;
pub const Collider = components.Collider;
pub const Velocity = components.Velocity;
pub const KinematicTarget = components.KinematicTarget;
pub const Shape = components.Shape;

pub const Config = resources.Config;
pub const Stats = resources.Stats;
pub const Queries = queries.Queries;

pub const PhysicsModule = @import("module.zig").PhysicsModule;
```

Games should install it like this:

```zig
try app.installModule(physics.PhysicsModule{
    .config = .{
        .backend = .Jolt,
        .fixed_dt = 1.0 / 60.0,
        .gravity = .{ .x = 0.0, .y = -9.81, .z = 0.0 },
    },
});
```

Entity authoring should stay simple:

```zig
_ = try commands.createEntity(.{
    common.Transform.fromTranslation(.{ .x = 0.0, .y = 3.0, .z = 0.0 }),
    physics.Body{ .kind = .Dynamic },
    physics.Collider{
        .shape = .{ .Capsule = .{ .radius = 0.35, .half_height = 0.55 } },
    },
    physics.Velocity{},
    Player{},
});
```

Static world geometry:

```zig
_ = try commands.createEntity(.{
    common.Transform.fromTranslation(.{ .x = 0.0, .y = -1.0, .z = 0.0 }),
    physics.Body{ .kind = .Static },
    physics.Collider{
        .shape = .{ .Box = .{ .half_extents = .{ .x = 20.0, .y = 1.0, .z = 20.0 } } },
    },
});
```

## Migration Plan

### Phase 1

- create `lib/physics/` public module
- add backend-neutral API, resources, schedules, and tests
- add `common.Channel(T)` and keep it small
- add `null` backend for compile/test coverage
- keep `FpsPhysicsModule` unchanged

### Phase 2

- refactor existing queue wrappers incrementally toward `Channel(T)` where it reduces duplication
- add `jolt` backend through owned C shim
- support `Body`, `Collider`, `Velocity`, raycast, and contact begin/end
- add worker-thread request/result channel path, while keeping a main-thread execution mode for simpler debugging
- add native example with stacked boxes, capsule player, and raycast gun

### Phase 3

- migrate `FpsPhysicsModule` onto `physics`
- replace ad-hoc AABB collision with character/body systems built on physics queries
- keep the human-friendly controller layer as a higher-level module on top of `physics`

### Phase 4

- decide wasm path after native API proves stable
- options:
  - `null` backend for wasm initially
  - small ECS/simple backend for gameplay prototypes
  - Jolt wasm bridge later if worth the complexity

## Specific Recommendation For This Workspace

Do this next:

1. Create the new public `physics` module and export it from the build.
2. Define the ECS-facing API before integrating any engine.
3. Add a `null` backend first so schedules, resources, and tests settle.
4. Integrate Jolt behind an owned C shim.
5. Rebuild `FpsPhysicsModule` as a convenience layer on top of `physics`, not as the foundation.

Do not do this next:

- do not wire raw Jolt handles directly into gameplay entities
- do not make `modules/PhysicsModule.zig` the canonical physics home
- do not block v1 on wasm
- do not choose Box2D as the main engine unless the project becomes 2D-first

## Notes From Current Codebase

This proposal matches the current codebase shape:

- `common` already owns `Vec3`, `Quat`, and `Transform`
- `ecs` already has a clean module install model and custom schedules
- current `FpsPhysicsModule` shows demand for physics-specific schedules and an ECS-first user API
- existing C dependency wrappers are thin and owned, which is the right precedent for a Jolt shim

## Source Notes

Official upstream sources consulted for this proposal:

- [JoltPhysics README](https://raw.githubusercontent.com/jrouwe/JoltPhysics/master/README.md)
- [JoltPhysics releases](https://github.com/jrouwe/JoltPhysics/releases)
- [JoltPhysics.js README](https://raw.githubusercontent.com/jrouwe/JoltPhysics.js/main/README.md)
- [PhysX README](https://raw.githubusercontent.com/NVIDIA-Omniverse/PhysX/main/README.md)
- [PhysX docs](https://nvidia-omniverse.github.io/PhysX/)
- [Box2D README](https://raw.githubusercontent.com/erincatto/box2d/main/README.md)
- [Box2D docs](https://box2d.org/documentation/)
- [ReactPhysics3D README](https://raw.githubusercontent.com/DanielChappuis/reactphysics3d/master/README.md)
