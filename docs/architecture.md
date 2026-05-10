# Architecture

Phasor is built as a chain of explicit typed objects. The `App` is the runtime
root. It owns the `World`, owns the schedule graph, owns the command-batch
channel used by the executor, installs modules, and drives startup, frame
stepping, and shutdown.

The main chain is:

- `App` owns a `ScheduleManager`.
- `ScheduleManager` owns a graph of named schedules.
- Each `Schedule` owns a graph of system nodes.
- Each system node owns a `System`.
- Each `System` wraps a plain Zig function.
- The function signature declares the resources, queries, events, and command
  access the system needs.
- System parameters initialize from `Commands`.
- `Commands` points at the current `World`.
- `World` owns resources and a columnar `Database`.
- `Database` stores entity rows in archetype tables.

Most of the engine is built by composing that chain. Modules add resources,
schedules, and systems. Phases add and remove systems at runtime. Rendering
extracts world data into a transient queue, then submits that queue through the
active backend. Events and command batches use channels to move typed data across
delayed or concurrent boundaries.

## App and Schedules

`App` is the object that makes the engine run. It owns allocator and `std.Io`
handles, the `World`, the `ScheduleManager`, and the optional
`Channel(Commands.CommandBatch)` used during execution. The usual application
entrypoint builds an app, installs modules and systems, then returns
`try app.run()`. `AppConfig.parallel_systems` selects the system executor:
serial by default, or a parallel executor that batches non-conflicting systems
with `std.Io.Group`.

`App.run` owns the lifecycle. It runs window creation, asset loading, and
startup once; steps frame schedules from `BeforeFrame` onward until an exit
resource appears; then runs shutdown, asset unload, and window destruction.
`App.start` and `App.step` expose those lifecycle pieces for platform runtimes
that need to split startup from per-frame stepping, such as the browser loop.

Schedules are named nodes in a graph. The default schedule graph is:
`WindowCreate`, `AssetsLoad`, `Startup`, `BeforeFrame`, `Layout`, `Update`,
`Render`, `AfterFrame`, `Shutdown`, `AssetsUnload`, and `WindowDestroy`.
Modules can add systems to existing schedules or insert custom schedules between
known points. The schedule manager caches topological order and invalidates that
cache when the graph changes.

Each schedule owns its own graph of system nodes. That graph stores systems,
supports removal by disabling nodes, and provides topological order. The
executor can run the ordered systems serially or, when configured for parallel
systems, group non-conflicting systems into batches. Parallel batches use
`std.Io.Group`; command batches created by worker systems are sent back through
`Channel(Commands.CommandBatch)` and applied in declared system order.

## World and Database

`World` is the state container systems operate on. It owns two kinds of state:
entity storage and resources.

Entity storage lives in `Database`. The database is columnar. It stores entities
in archetype tables, where each table schema is a set of component types. An
entity is an ID plus a row location. Adding or removing components moves the
entity to a table with the new schema, copies shared component data, writes the
new component shape, and updates the entity location. Rows are dense, and
removal uses swap-remove.

Queries compile a component specification into matching table indices, then
iterate rows in those tables. `Database` caches those table-index matches by the
query's required and excluded component type sets plus a generation counter.
Creating a new archetype table bumps the generation. Changing ordinary component
values does not rebuild query matches.

Resources live beside the database in `World`. A resource is one value per type:
time state, input state, renderer state, asset libraries, bounds, event queues,
phase state, and other app-wide data. Components answer "which entities have
this data?" Resources answer "what is the current app-level value?"

## Systems

Systems are plain Zig functions. The signature is the contract:

- `Res(T)` reads a resource.
- `ResMut(T)` writes a resource.
- `ResOpt(T)` and `ResMutOpt(T)` express optional resources.
- `Query(.{ ... })` visits matching entity rows.
- `EventReader(T)` receives events from a per-system subscription.
- `EventWriter(T)` sends events.
- `*Commands` queues structural changes and exposes the current world for system
  parameter initialization.

Phasor reflects a system function at comptime and builds a `System` object with
registration, execution, and unregistration hooks. Registration lets parameters
set up durable side effects such as event-reader subscriptions. Execution
initializes each parameter from `Commands`, calls the function, then cleans up
transient query state.

The same signature feeds the scheduler's access analysis. Compatible resource
reads can share a batch. Mutable resource access conflicts with other reads or
writes of that resource. Broad world access, including `*Commands` and
`WorldRef`, is treated conservatively. Component access is currently conservative
as well, while the resource-level model already allows useful parallelism.

## Commands

`Commands` is the line between reading the current world and changing world
structure. Creating or removing entities, adding or removing components,
inserting resources, and registering event resources are queued as commands. A
system can reserve an entity ID immediately, but the entity row appears in the
database only when the command is applied.

That rule gives every system a stable view for the duration of its run. In
serial execution, each system's commands are applied before the next system. In
parallel execution, each worker receives its own `Commands` value. When a worker
finishes, it flushes an owned `CommandBatch` into the app's command channel. The
executor drains and applies those batches at batch boundaries in schedule order.

The important invariant is simple: systems may request structural changes, but
world structure mutates at executor boundaries.

## Channels and Events

`Channel(T)` is Phasor's bounded typed queue. It has a clonable sender, a
single-consumer receiver, fixed capacity, explicit close behavior, and shared
lifetime management. It is implemented on `std.Io.Queue(T)`.

Channels are used where ownership crosses an execution boundary. `Agent` uses
paired channels for request and response messages to a concurrent task. The
parallel executor uses a channel to return command batches. Events build on
`Broadcast(T)`, which keeps one `Channel(T)` per subscriber.

Events represent short-lived facts: input edges, window resizes, collision
notifications, UI actions, and gameplay signals. Durable state belongs in a
component or resource. Registering an event type inserts `Events(T)` into the
world. `EventWriter(T)` sends into that resource. Each `EventReader(T)` drains
the subscription registered for that system function, so multiple systems can
observe the same event stream independently.

## Modules

Modules are installable bundles of resources and systems. A module's `install`
function may receive `*AppCommands` for schedule changes and `*Commands` for
world changes. `App.installModule` creates both, invokes the module, then applies
any queued world commands.

This keeps engine features on the same execution model as game code. A module
declares resources, registers systems into schedules, and lets `App` run those
systems with every other system.

## Phases

`PhaseModule` adds mode-specific behavior by registering and unregistering
systems through the schedule manager. Phases are hierarchical. Parent phases own
behavior that should persist across child transitions; child phases own behavior
that should disappear when replaced. A gameplay parent can keep the world mounted
while a pause child adds pause-menu behavior on top.

A transition compares the current phase tree with the requested phase tree. It
exits inactive branches, enters newly active branches, and leaves shared parents
mounted. Each active level owns a `PhaseContext`; systems registered through that
context are removed automatically when the level exits.

Requested transitions are stored as resources and processed in `BeforeFrame`.
Enter hooks add systems. Exit hooks unregister systems. Phase behavior therefore
appears and disappears through the same schedule graph as the rest of the
engine.

## Rendering

Rendering is split between ECS extraction and backend submission. Game code adds
components such as meshes, sprites, text, layers, cameras, transforms, and
lights. Those components live in `Database` like any other component.

The render module creates render resources, prepares assets, and reads world data
during the frame. Extraction resets a transient `RenderQueue`, queries visible
render data, resolves layers and sort keys, gathers lighting, and pushes
normalized draw items into the queue.

Submission consumes the queue with the current `RenderState` and calls the
native or web backend. Native and WASM share the component model, schedule model,
extraction path, and render queue. Backend code diverges only where platform APIs
require it.

## Frame Summary

A frame is the architecture in motion. Internally, `App` gets schedule order
from `ScheduleManager`. Each `Schedule` yields system nodes. Each `System`
initializes parameters from `Commands` and calls its Zig function. Queries read
stable archetype rows from `Database`; resources provide app-level state from
`World`; events drain channel-backed subscriptions; structural changes become
command batches. At executor boundaries, command batches apply to `World`, and
the next stage sees the updated state.

The pieces stay small, but their roles compose cleanly: `Database` stores rows,
`World` owns state, `Commands` controls structural mutation, `System` makes
behavior explicit, schedules provide order, `App` drives the loop, channels carry
typed handoff, modules package features, phases manage mode-specific systems,
and rendering turns world data into backend work.
