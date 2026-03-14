test "import tests" {
    _ = components;
    _ = resources;
    _ = events;
    _ = queries;
    _ = backend;
    _ = module;
}

pub const components = @import("components.zig");
pub const resources = @import("resources.zig");
pub const events = @import("events.zig");
pub const queries = @import("queries.zig");
pub const backend = @import("backend.zig");
pub const module = @import("module.zig");

pub const Body = components.Body;
pub const Collider = components.Collider;
pub const Velocity = components.Velocity;
pub const MassProperties = components.MassProperties;
pub const LockAxes = components.LockAxes;
pub const KinematicTarget = components.KinematicTarget;
pub const Shape = components.Shape;
pub const Material = components.Material;
pub const CollisionFilter = components.CollisionFilter;
pub const CollisionMeshHandle = components.CollisionMeshHandle;
pub const CompoundShapeHandle = components.CompoundShapeHandle;
pub const PhysicsDirty = components.PhysicsDirty;
pub const PhysicsDisabled = components.PhysicsDisabled;
pub const BodyHandle = components.BodyHandle;

pub const Config = resources.Config;
pub const Stats = resources.Stats;
pub const StepState = resources.StepState;
pub const CollisionMeshBlob = resources.CollisionMeshBlob;
pub const CollisionMeshAsset = resources.CollisionMeshAsset;

pub const ContactBegan = events.ContactBegan;
pub const ContactEnded = events.ContactEnded;
pub const TriggerEntered = events.TriggerEntered;
pub const TriggerExited = events.TriggerExited;
pub const RayCast = queries.RayCast;
pub const RayHit = queries.RayHit;
pub const ShapeCast = queries.ShapeCast;
pub const ShapeHit = queries.ShapeHit;
pub const BackendWorld = backend.World;

pub const PhysicsModule = module.PhysicsModule;
pub const PhysicsSchedules = module.PhysicsSchedules;
