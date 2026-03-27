# ECS

`phasor` applications are built out of a small ECS vocabulary:

- entities group related components
- components hold per-entity state
- resources hold singleton state for the whole world
- systems declare the data they need, then run inside schedules
- queries select the entities a system should touch
- events move short-lived messages between systems

That model stays the same from the smallest example up through the larger scene-driven projects. The main difference is how much data the systems declare and how many modules are feeding the world around them.

## Entities And Components

An entity in `phasor` is just an ID plus the components you attach to it. The usual pattern is to spawn a bundle that already describes the job of the entity: renderable geometry, transform, velocity, tags, camera markers, or parent-child relationships.

The triangle example is the smallest version of that pattern. It creates one entity that carries a `Triangle` render component, then a second entity that carries the camera components for the scene:

{{ include_lines path="examples/triangle/main.zig" start="10" end="27" }}

As soon as you need richer scene structure, you keep using the same operation. The bouncing-ball example creates a root ball entity, then child entities for the inset mesh and the sprite decal:

{{ include_lines path="examples/bouncing-ball/main.zig" start="72" end="103" }}

The important part is not the entity ID. It is the bundle shape. The components tell the engine and your own systems what that entity participates in.

## Resources

Resources are world-level state. Use them for data that should exist once for the whole app or once for the current mode: clear color, scene assets, counters, configuration, current phase, caches, and module-owned state.

The ECS example sets up a resource and a helper entity during boot. `SpawnCounter` is a resource because the count belongs to the whole simulation, not to any single particle:

{{ include_lines path="examples/ecs/main.zig" start="33" end="40" }}

The renderer examples do the same thing with engine resources. `ClearColor` is inserted once and then consumed by the render path every frame:

{{ include_lines path="examples/triangle/main.zig" start="21" end="27" }}

When a system needs one of these values later, it should declare `Res(T)` or `ResMut(T)` in its system params instead of reaching back into the world manually.

## Systems

Systems are ordinary Zig functions registered into schedules. They become interesting because their signatures are the dependency contract: if a system needs time, a counter, and a query over particles, those things belong in the params.

The ECS example registers its running behavior as four update systems:

{{ include_lines path="examples/ecs/main.zig" start="44" end="49" }}

That keeps the behavior legible:

- one system spawns particles
- one integrates motion
- one requests exit
- one reacts to the exit event

The function signature tells you what each system reads or mutates without having to inspect hidden world access.

## Queries

Queries are how systems operate on entity data. A query names the component set it needs, and the system iterates the matching rows.

The bouncing-ball example integrates motion with a simple query over `Transform` and `Velocity`:

{{ include_lines path="examples/bouncing-ball/main.zig" start="128" end="136" }}

The same idea scales up to more selective queries. The ECS example updates only entities that have `Position`, `Velocity`, and `ParticleTag`:

{{ include_lines path="examples/ecs/main.zig" start="68" end="77" }}

That is the main ECS rhythm in `phasor`: declare the slice of the world you need, iterate it, and mutate only the components the query hands you.

## Events

Events are for transient messages that should be queued and drained, not stored as long-lived world state. Input, resize notifications, and one-frame decisions all fit that model better than singleton resources.

The ECS example defines an `ExitRequested` event, sends it from one system, then consumes it in another:

{{ include_lines path="examples/ecs/main.zig" start="79" end="94" }}

That split matters. One system decides that the countdown has finished. Another system owns the state transition that follows. The event keeps that handoff explicit without introducing hidden coupling between the two systems.

## Mental Model

Start with this checklist:

- spawn entities with the components that describe what they are
- insert resources for world-level state
- write systems whose params declare exactly what they need
- use queries for persistent entity data
- use events for short-lived messages

Once that feels natural, the next layer is [Phases](phases.md). Phases keep the same ECS model, but add structured mode transitions and phase-owned system registration on top of it.
