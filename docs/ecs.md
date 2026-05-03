# Entity-Component-Systems in Phasor

Phasor apps have a specialized database that stores entities, components, and resources:

- **Entities** represent game objects and are uniquely identified by their ID.
- **Components** are data structures that describe the behavior or state of an entity.
- **Resources** are global data, e.g. a game settings object.

**Systems** are simply functions that process entities and components.

