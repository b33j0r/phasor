# Entity-Component-Systems in Phasor

Phasor is built around an Entity-Component-System architecture, usually shortened
to ECS. If you have not used ECS before, the core idea is simple: instead of
building a world out of big object hierarchies, you build it out of small pieces
of data and small functions that know what data they need.

An `App` owns the world. The world stores entities, components, and resources:

- **Entities** are IDs. They are the "things" in your game, but they do not
  contain behavior by themselves.
- **Components** are data attached to entities. A ship might have a `Transform`,
  a `Velocity`, and a `Health` component.
- **Resources** are single global values. Window settings, elapsed time, loaded
  asset libraries, and game state are all natural resources.
- **Systems** are ordinary Zig functions. A system's parameters say what it
  wants to read or write.

That last point is the part that makes ECS feel different. You do not usually
call systems yourself. You register them with the app, and Phasor calls them at
the right point in the frame. The function signature is the contract.

```zig
fn moveShips(dt: Res(DeltaTime), ships: Query(.{ Transform, Velocity })) void {
    const step: f32 = @floatCast(dt.deref().seconds);

    var it = ships.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const velocity = row.get(Velocity) orelse continue;

        transform.translation.x += velocity.v.x * step;
        transform.translation.y += velocity.v.y * step;
    }
}
```

There is no hidden base class here. `moveShips` is just a function. Phasor uses
Zig comptime reflection to inspect the parameters and provide the right values
when the system runs.

## A Small Mental Model

Think of an entity as a row in a database and each component type as a column.
Adding a component changes what kind of row that entity is. A query asks for
"every entity that has these columns."

For example, a ball in a simple demo might be:

```zig
const Ball = struct {
    radius: f32,
};

const Velocity = struct {
    v: Vec3 = .{},
};
```

The entity is not a `Ball` object. It is an ID with a `Ball` component, a
`Velocity` component, a `Transform`, and maybe a `MeshInstance`. The rendering
module does not need to know anything about the `Ball` component. It only cares
about renderable data. The bounce system does not need to know how rendering
works. It only cares about `Transform`, `Velocity`, `Ball`, and the window size.

That separation is the point. You get a world where systems can be direct and
boring because the shape of the data already decides what they operate on.

## Creating an App

A typical Phasor app creates an `App`, inserts a few resources, installs modules,
adds systems, and then runs.

```zig
pub fn main(init: std.process.Init) !u8 {
    var app = try App.init(&init, .{
        .command_queue_capacity = 64,
        .parallel_systems = true,
    });
    defer app.deinit();

    try app.insertResource(WindowSettings{
        .title = "Ball",
        .width = 800,
        .height = 600,
    });
    try app.insertResource(VSync{ .enabled = false });
    try app.insertResource(ClearColor{ .color = Color.WHITE });

    try app.installDefaultModules();

    try app.addSystem("Startup", setup);
    try app.addSystem("Update", moveShips);

    return try app.run();
}
```

The ergonomics of Phasor's ECS API are intentionally inspired by Bevy. If you
have used Bevy, `Query`, `Res`, `ResMut`, and `Commands` should feel familiar,
even though this is Zig rather than Rust.

## System Parameters

Most systems use a small vocabulary of parameters:

- `Query(.{ A, B })` visits entities that have components `A` and `B`.
- `Query(.{ A, Without(B) })` visits entities that have `A` but not `B`.
- `Res(T)` reads a resource.
- `ResMut(T)` mutates a resource.
- `ResOpt(T)` and `ResMutOpt(T)` are for genuinely optional resources.
- `Commands` creates entities, removes entities, and queues structural changes.

Prefer making dependencies explicit in the function signature. If a system needs
the window size, ask for `Res(WindowBounds)`. If it needs elapsed time, ask for
`Res(ElapsedTime)`. This keeps systems understandable and gives the scheduler a
chance to reason about what can run together.

Use optional resources when absence is a real state, not as a way to avoid
thinking about setup order. A required `Res(T)` is a useful assertion: this
system only makes sense after `T` exists.

## Commands and Timing

`Commands` is for structural changes: create an entity, add a component, remove
an entity, insert a resource. Those changes are deferred. In practice, that
means a system should not queue a write through `Commands` and then expect a
query in the same system to observe the new shape of the world.

This rule keeps system execution predictable. Systems read the world they were
given, request structural changes, and those changes are applied at a defined
boundary after the system runs.

## Schedules

Systems run inside named schedules. The common schedules are:

- `Startup` for one-time setup after the window and renderer basics exist.
- `BeforeFrame` for per-frame engine preparation.
- `Update` for normal game logic.
- `Render` for submitting frame data.
- `AfterFrame` for cleanup.
- `Shutdown` for teardown.

For most gameplay code, `Startup` and `Update` are enough. Modules use the other
schedules to keep engine work in the right part of the frame.

## How to Choose Components and Resources

Put data on an entity when it describes that entity. Position, velocity, health,
sprite state, and "this is the player" tags are all components.

Use a resource when there should be one value for the app or for a whole mode of
the game. Window bounds, timers, asset contexts, input state, and current phase
state are resources.

If you are unsure, ask: "Could there be many of these at once?" If yes, it is
probably a component. "Does this configure or summarize the whole world?" If yes,
it is probably a resource.

## If You Know Bevy

The broad mapping is:

- Bevy `Commands` -> Phasor `*Commands`
- Bevy `Query<...>` -> Phasor `Query(.{ ... })`
- Bevy `Res<T>` -> Phasor `Res(T)`
- Bevy `ResMut<T>` -> Phasor `ResMut(T)`
- Bevy startup/update schedules -> Phasor named schedules such as `"Startup"`
  and `"Update"`

Phasor does not try to copy Bevy exactly. The goal is the same style of
ergonomics: systems should be plain functions, and their parameters should be
enough to understand their data dependencies.

## See Also

- [A Simple Entity Component System (ECS)](https://austinmorlan.com/posts/entity_component_system/)
  by Austin Morlan. A good from-scratch explanation of the pattern.
- [Bevy ECS quick start](https://bevy.org/learn/quick-start/getting-started/ecs/).
  Useful context for the API style that inspired Phasor's ECS ergonomics.
- [Entity component system on Wikipedia](https://en.wikipedia.org/wiki/Entity_component_system).
  A broader overview of the architectural pattern.
