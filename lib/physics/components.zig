const common = @import("common");
const ecs = @import("ecs");

pub const Material = struct {
    friction: f32 = 0.5,
    restitution: f32 = 0.0,
};

pub const CollisionFilter = struct {
    layer: u32 = 1,
    mask: u32 = 0xFFFF_FFFF,
};

pub const CollisionMeshHandle = enum(u32) {
    invalid = 0,
    _,
};

pub const HeightFieldHandle = enum(u32) {
    invalid = 0,
    _,
};

pub const CompoundShapeHandle = enum(u32) {
    invalid = 0,
    _,
};

pub const Shape = union(enum) {
    Sphere: struct { radius: f32 },
    Capsule: struct { radius: f32, half_height: f32 },
    Box: struct { half_extents: common.Vec3 },
    Cylinder: struct { radius: f32, half_height: f32 },
    TriangleMesh: CollisionMeshHandle,
    HeightField: HeightFieldHandle,
    Compound: CompoundShapeHandle,
};

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

pub const Character = struct {
    mass: f32 = 80.0,
    max_strength: f32 = 100.0,
    max_slope_angle_radians: f32 = std.math.degreesToRadians(50.0),
    padding: f32 = 0.02,
    penetration_recovery_speed: f32 = 1.0,
    predictive_contact_distance: f32 = 0.1,
    max_collision_iterations: u32 = 5,
    max_constraint_iterations: u32 = 15,
    min_time_remaining: f32 = 1.0e-4,
    collision_tolerance: f32 = 1.0e-3,
    max_hits: u32 = 256,
    hit_reduction_cos_max_angle: f32 = 0.999,
    enhanced_internal_edge_removal: bool = true,
    stick_to_floor_distance: f32 = 0.5,
    step_up_height: f32 = 0.4,
    step_forward_min_distance: f32 = 0.02,
    step_forward_test_distance: f32 = 0.15,
    step_down_extra_distance: f32 = 0.0,
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

pub const CharacterVelocity = struct {
    linear: common.Vec3 = .{},
};

pub const CharacterGroundState = enum(u8) {
    OnGround,
    OnSteepGround,
    NotSupported,
    InAir,
};

pub const CharacterState = struct {
    ground_state: CharacterGroundState = .InAir,
    ground_normal: common.Vec3 = .{},
    ground_velocity: common.Vec3 = .{},
    ground_body: ?BodyHandle = null,
    ground_entity: ?ecs.Entity.Id = null,
    max_hits_exceeded: bool = false,

    pub fn isSupported(self: @This()) bool {
        return switch (self.ground_state) {
            .OnGround, .OnSteepGround => true,
            .NotSupported, .InAir => false,
        };
    }

    pub fn isGrounded(self: @This()) bool {
        return self.ground_state == .OnGround;
    }
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
    transform: common.Transform = .{},
    linear_velocity_hint: common.Vec3 = .{},
    angular_velocity_hint: common.Vec3 = .{},
};

pub const PhysicsDirty = struct {};
pub const PhysicsDisabled = struct {};

pub const BodyHandle = struct {
    value: u64 = 0,
};

pub const CharacterHandle = struct {
    value: u64 = 0,
};

const std = @import("std");
