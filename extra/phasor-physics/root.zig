const core_physics = @import("physics");

test "import tests" {
    _ = core_physics;
    _ = FpsPhysicsModule;
    _ = FpsKeyBindingModule;
}

pub const components = core_physics.components;
pub const resources = core_physics.resources;
pub const events = core_physics.events;
pub const queries = core_physics.queries;
pub const backend = core_physics.backend;
pub const bake = core_physics.bake;
pub const module = core_physics.module;

pub const Body = core_physics.Body;
pub const Character = core_physics.Character;
pub const Collider = core_physics.Collider;
pub const Velocity = core_physics.Velocity;
pub const CharacterVelocity = core_physics.CharacterVelocity;
pub const CharacterState = core_physics.CharacterState;
pub const CharacterGroundState = core_physics.CharacterGroundState;
pub const MassProperties = core_physics.MassProperties;
pub const LockAxes = core_physics.LockAxes;
pub const KinematicTarget = core_physics.KinematicTarget;
pub const Shape = core_physics.Shape;
pub const Material = core_physics.Material;
pub const CollisionFilter = core_physics.CollisionFilter;
pub const CollisionMeshHandle = core_physics.CollisionMeshHandle;
pub const HeightFieldHandle = core_physics.HeightFieldHandle;
pub const CompoundShapeHandle = core_physics.CompoundShapeHandle;
pub const PhysicsDirty = core_physics.PhysicsDirty;
pub const PhysicsDisabled = core_physics.PhysicsDisabled;
pub const BodyHandle = core_physics.BodyHandle;
pub const CharacterHandle = core_physics.CharacterHandle;

pub const Config = core_physics.Config;
pub const Stats = core_physics.Stats;
pub const StepState = core_physics.StepState;
pub const CollisionMeshBlob = core_physics.CollisionMeshBlob;
pub const CollisionMeshAsset = core_physics.CollisionMeshAsset;
pub const CollisionMeshStore = core_physics.CollisionMeshStore;
pub const HeightFieldAsset = core_physics.HeightFieldAsset;
pub const HeightFieldStore = core_physics.HeightFieldStore;

pub const ContactBegan = core_physics.ContactBegan;
pub const ContactEnded = core_physics.ContactEnded;
pub const TriggerEntered = core_physics.TriggerEntered;
pub const TriggerExited = core_physics.TriggerExited;
pub const RayCast = core_physics.RayCast;
pub const RayHit = core_physics.RayHit;
pub const ShapeCast = core_physics.ShapeCast;
pub const ShapeHit = core_physics.ShapeHit;
pub const BackendWorld = core_physics.BackendWorld;
pub const CollisionBake = core_physics.CollisionBake;
pub const units = core_physics.units;

pub const PhysicsModule = core_physics.PhysicsModule;
pub const PhysicsSchedules = core_physics.PhysicsSchedules;

pub const FpsControlInput = @import("fps_physics").FpsControlInput;
pub const FpsPhysicsModule = @import("fps_physics").FpsPhysicsModule;
pub const FpsKeyBindings = @import("fps_key_binding").FpsKeyBindings;
pub const FpsKeyBindingModule = @import("fps_key_binding").FpsKeyBindingModule;
