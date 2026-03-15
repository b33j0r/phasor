const common = @import("common");

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
    transform: common.Transform = .{},
    linear_velocity_hint: common.Vec3 = .{},
    angular_velocity_hint: common.Vec3 = .{},
};

pub const PhysicsDirty = struct {};
pub const PhysicsDisabled = struct {};

pub const BodyHandle = struct {
    value: u64 = 0,
};
