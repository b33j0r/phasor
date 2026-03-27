# Phases

`PhasesModule` gives phase transitions a real ECS shape. The phase state lives in resources, transitions are requested by inserting `NextPhase`, and runtime systems can read `CurrentPhase` like any other resource.

That keeps phase flow explicit. A system can request a transition without reaching around the scheduler, and another system can gate its behavior on the current phase without inventing a parallel state machine.

## Start With `NextPhase`

The smallest pattern is to define a phase union, install `PhasesModule`, and request the next phase by inserting `NextPhase`.

{{ include_lines path="examples/ecs/main.zig" start="29" end="31" }}

The same pattern works later in the lifecycle too. A running system can decide that the app should advance or exit, then queue that transition as data.

{{ include_lines path="examples/ecs/main.zig" start="91" end="95" }}

## Read `CurrentPhase` In Systems

Once phases are installed, systems can depend on the current phase explicitly:

- use `Res(MyPhases.CurrentPhase)` when the phase module is part of the app and the resource should exist
- branch on the current phase near the top of the system
- insert `NextPhase` when the system decides the state should change

The `sponza` example uses that pattern for pause and resume input. The system reads `CurrentPhase`, updates the mouse-capture resource, and queues the next phase directly.

{{ include_lines path="examples/sponza/gameplay.zig" start="152" end="171" }}

## Scale Up With `PhasesModule`

The more important pattern is not the resource itself. It is that each phase can own its own systems. Instead of registering everything globally and guarding it later, add the relevant systems from `enter`.

The `Loading` phase in `sponza` owns loader, lighting, and loading-screen work:

{{ include_lines path="examples/sponza/phases.zig" start="9" end="58" }}

Then the parent `InGame` phase installs the systems that should survive child transitions like `Playing <-> Paused`:

{{ include_lines path="examples/sponza/phases.zig" start="83" end="108" }}

That split is the part worth preserving:

- root or parent phases own systems and resources that should persist across child transitions
- child phases own only child-local behavior
- `NextPhase` requests the change, while `CurrentPhase` tells systems where they are now

## Mental Model

Use phases when the app has real mode changes and you want those changes to be visible in ECS:

- setup and teardown happen in `enter` and `exit`
- systems declare `CurrentPhase` if they need to react to the active mode
- transitions are queued through `NextPhase`, not by mutating some hidden singleton

That keeps the scheduler, the app state, and the code that changes it in the same model.
