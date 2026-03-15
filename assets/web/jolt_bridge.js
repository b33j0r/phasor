import initJolt from "./vendor/jolt/jolt-physics.wasm-compat.js";

const kMaxLayers = 32;

const pjMotionType = {
  static: 0,
  dynamic: 1,
  kinematic: 2,
};

const pjShapeKind = {
  sphere: 0,
  capsule: 1,
  box: 2,
  cylinder: 3,
  triangle_mesh: 4,
  height_field: 5,
};

const worldConfigSize = 36;
const bodyDescSize = 168;
const bodyStateSize = 64;
const raycastHitSize = 48;

export function createJoltEnv(getMemoryView) {
  let Jolt = null;
  let initPromise = null;
  let nextWorldHandle = 1;
  const worlds = new Map();

  function assertReady() {
    if (!Jolt) {
      throw new Error("JoltPhysics.js is not initialized");
    }
  }

  async function init() {
    if (Jolt) return Jolt;
    if (!initPromise) {
      initPromise = initJolt().then((loaded) => {
        Jolt = loaded;
        return loaded;
      });
    }
    return initPromise;
  }

  function view() {
    return getMemoryView();
  }

  function readU32(ptr) {
    return view().getUint32(ptr, true);
  }

  function writeU32(ptr, value) {
    view().setUint32(ptr, value >>> 0, true);
  }

  function readI32(ptr) {
    return view().getInt32(ptr, true);
  }

  function readF32(ptr) {
    return view().getFloat32(ptr, true);
  }

  function writeF32(ptr, value) {
    view().setFloat32(ptr, value, true);
  }

  function readBool(ptr) {
    return view().getUint8(ptr) !== 0;
  }

  function writeBool(ptr, value) {
    view().setUint8(ptr, value ? 1 : 0);
  }

  function readU64(ptr) {
    return Number(view().getBigUint64(ptr, true));
  }

  function writeU64(ptr, value) {
    view().setBigUint64(ptr, BigInt(Math.trunc(value)), true);
  }

  function readVec3(ptr) {
    return {
      x: readF32(ptr + 0),
      y: readF32(ptr + 4),
      z: readF32(ptr + 8),
    };
  }

  function writeVec3(ptr, value) {
    writeF32(ptr + 0, value.x);
    writeF32(ptr + 4, value.y);
    writeF32(ptr + 8, value.z);
  }

  function readQuat(ptr) {
    return {
      x: readF32(ptr + 0),
      y: readF32(ptr + 4),
      z: readF32(ptr + 8),
      w: readF32(ptr + 12),
    };
  }

  function writeQuat(ptr, value) {
    writeF32(ptr + 0, value.x);
    writeF32(ptr + 4, value.y);
    writeF32(ptr + 8, value.z);
    writeF32(ptr + 12, value.w);
  }

  function readF32Array(ptr, count) {
    const out = new Array(count);
    for (let i = 0; i < count; i += 1) {
      out[i] = readF32(ptr + i * 4);
    }
    return out;
  }

  function readU32Array(ptr, count) {
    const out = new Array(count);
    for (let i = 0; i < count; i += 1) {
      out[i] = readU32(ptr + i * 4);
    }
    return out;
  }

  function joltVec3(value) {
    return new Jolt.Vec3(value.x, value.y, value.z);
  }

  function joltRVec3(value) {
    return new Jolt.RVec3(value.x, value.y, value.z);
  }

  function joltQuat(value) {
    return new Jolt.Quat(value.x, value.y, value.z, value.w);
  }

  function vec3FromJolt(value) {
    return {
      x: value.GetX(),
      y: value.GetY(),
      z: value.GetZ(),
    };
  }

  function quatFromJolt(value) {
    return {
      x: value.GetX(),
      y: value.GetY(),
      z: value.GetZ(),
      w: value.GetW(),
    };
  }

  function motionTypeFromDesc(motionType) {
    switch (motionType) {
      case pjMotionType.static:
        return Jolt.EMotionType_Static;
      case pjMotionType.kinematic:
        return Jolt.EMotionType_Kinematic;
      case pjMotionType.dynamic:
      default:
        return Jolt.EMotionType_Dynamic;
    }
  }

  function allowedDofsFromMask(mask) {
    let out = 0;
    if ((mask & (1 << 0)) !== 0) out |= Jolt.EAllowedDOFs_TranslationX;
    if ((mask & (1 << 1)) !== 0) out |= Jolt.EAllowedDOFs_TranslationY;
    if ((mask & (1 << 2)) !== 0) out |= Jolt.EAllowedDOFs_TranslationZ;
    if ((mask & (1 << 3)) !== 0) out |= Jolt.EAllowedDOFs_RotationX;
    if ((mask & (1 << 4)) !== 0) out |= Jolt.EAllowedDOFs_RotationY;
    if ((mask & (1 << 5)) !== 0) out |= Jolt.EAllowedDOFs_RotationZ;
    return out === 0 ? Jolt.EAllowedDOFs_All : out;
  }

  function makeShape(desc, meshVerticesPtr, meshVertexCount, meshIndicesPtr, meshIndexCount, heightSamplesPtr, heightSampleCount) {
    switch (desc.shape_kind) {
      case pjShapeKind.sphere:
        return new Jolt.SphereShape(desc.radius);

      case pjShapeKind.capsule:
        return new Jolt.CapsuleShape(desc.half_height, desc.radius);

      case pjShapeKind.box: {
        const halfExtents = joltVec3(desc.half_extents);
        try {
          return new Jolt.BoxShape(halfExtents);
        } finally {
          Jolt.destroy(halfExtents);
        }
      }

      case pjShapeKind.cylinder:
        return new Jolt.CylinderShape(desc.half_height, desc.radius, 0.05);

      case pjShapeKind.triangle_mesh: {
        if (!meshVerticesPtr || !meshIndicesPtr || meshVertexCount === 0 || meshIndexCount < 3) {
          return null;
        }
        const vertices = new Jolt.VertexList();
        const triangles = new Jolt.IndexedTriangleList();
        try {
          vertices.reserve(meshVertexCount);
          triangles.reserve(Math.floor(meshIndexCount / 3));

          const positions = readF32Array(meshVerticesPtr, meshVertexCount * 3);
          for (let i = 0; i < meshVertexCount; i += 1) {
            const v = new Jolt.Float3(
              positions[i * 3 + 0],
              positions[i * 3 + 1],
              positions[i * 3 + 2],
            );
            try {
              vertices.push_back(v);
            } finally {
              Jolt.destroy(v);
            }
          }

          const indices = readU32Array(meshIndicesPtr, meshIndexCount);
          for (let i = 0; i + 2 < meshIndexCount; i += 3) {
            const tri = new Jolt.IndexedTriangle(
              indices[i + 0],
              indices[i + 1],
              indices[i + 2],
              0,
              0,
            );
            try {
              triangles.push_back(tri);
            } finally {
              Jolt.destroy(tri);
            }
          }

          const settings = new Jolt.MeshShapeSettings();
          try {
            settings.mTriangleVertices = vertices;
            settings.mIndexedTriangles = triangles;
            settings.mBuildQuality = Jolt.MeshShapeSettings_EBuildQuality_FavorRuntimePerformance;
            const result = settings.Create();
            try {
              if (result.HasError()) {
                return null;
              }
              return result.Get();
            } finally {
              Jolt.destroy(result);
            }
          } finally {
            Jolt.destroy(settings);
          }
        } finally {
          Jolt.destroy(vertices);
          Jolt.destroy(triangles);
        }
      }

      case pjShapeKind.height_field: {
        if (
          !heightSamplesPtr ||
          desc.heightfield_sample_count === 0 ||
          heightSampleCount !== desc.heightfield_sample_count * desc.heightfield_sample_count
        ) {
          return null;
        }

        const settings = new Jolt.HeightFieldShapeSettings();
        const offset = joltVec3(desc.heightfield_offset);
        const scale = joltVec3(desc.heightfield_scale);
        const samples = new Jolt.ArrayFloat();
        try {
          samples.reserve(heightSampleCount);
          const values = readF32Array(heightSamplesPtr, heightSampleCount);
          let minValue = Number.POSITIVE_INFINITY;
          let maxValue = Number.NEGATIVE_INFINITY;
          for (let i = 0; i < values.length; i += 1) {
            const value = values[i];
            samples.push_back(value);
            minValue = Math.min(minValue, value);
            maxValue = Math.max(maxValue, value);
          }
          settings.mOffset = offset;
          settings.mScale = scale;
          settings.mSampleCount = desc.heightfield_sample_count;
          settings.mMinHeightValue = minValue;
          settings.mMaxHeightValue = maxValue;
          settings.mHeightSamples = samples;
          const result = settings.Create();
          try {
            if (result.HasError()) {
              return null;
            }
            return result.Get();
          } finally {
            Jolt.destroy(result);
          }
        } finally {
          Jolt.destroy(settings);
          Jolt.destroy(offset);
          Jolt.destroy(scale);
          Jolt.destroy(samples);
        }
      }

      default:
        return null;
    }
  }

  function readBodyDesc(ptr) {
    if (!ptr) return null;
    return {
      user_data: readU64(ptr + 0),
      motion_type: readI32(ptr + 8),
      shape_kind: readI32(ptr + 12),
      object_layer: readU32(ptr + 16),
      collision_mask: readU32(ptr + 20),
      allowed_dofs_mask: readU32(ptr + 24),
      is_sensor: readBool(ptr + 28),
      allow_sleep: readBool(ptr + 29),
      use_ccd: readBool(ptr + 30),
      collide_kinematic_vs_non_dynamic: readBool(ptr + 31),
      use_enhanced_internal_edge_removal: readBool(ptr + 32),
      override_mass: readBool(ptr + 33),
      friction: readF32(ptr + 36),
      restitution: readF32(ptr + 40),
      linear_damping: readF32(ptr + 44),
      angular_damping: readF32(ptr + 48),
      gravity_scale: readF32(ptr + 52),
      density: readF32(ptr + 56),
      mass: readF32(ptr + 60),
      position: readVec3(ptr + 64),
      rotation: readQuat(ptr + 76),
      linear_velocity: readVec3(ptr + 92),
      angular_velocity: readVec3(ptr + 104),
      half_extents: readVec3(ptr + 116),
      radius: readF32(ptr + 128),
      half_height: readF32(ptr + 132),
      heightfield_offset: readVec3(ptr + 136),
      heightfield_scale: readVec3(ptr + 148),
      heightfield_sample_count: readU32(ptr + 160),
    };
  }

  function getWorld(handle) {
    const world = worlds.get(handle >>> 0);
    if (!world) throw new Error(`invalid Jolt world handle ${handle}`);
    return world;
  }

  function setCollisionMask(world, objectLayer, mask) {
    if (objectLayer >= kMaxLayers) return;
    for (let other = 0; other < kMaxLayers; other += 1) {
      if ((mask & (1 << other)) !== 0) {
        world.objectLayerPairFilter.EnableCollision(objectLayer, other);
        world.objectLayerPairFilter.EnableCollision(other, objectLayer);
      }
    }
  }

  function destroyWorld(world) {
    if (!world) return;
    for (const value of world.bodies.values()) {
      try {
        const bodyId = new Jolt.BodyID(value);
        try {
          if (world.bodyInterface.IsAdded(bodyId)) {
            world.bodyInterface.RemoveBody(bodyId);
          }
          world.bodyInterface.DestroyBody(bodyId);
        } finally {
          Jolt.destroy(bodyId);
        }
      } catch (_) {}
    }
    world.bodies.clear();
    if (world.shapes) {
      for (const shape of world.shapes) {
        try {
          Jolt.destroy(shape);
        } catch (_) {}
      }
      world.shapes.length = 0;
    }
    Jolt.destroy(world.joltInterface);
    Jolt.destroy(world.settings);
    Jolt.destroy(world.objectVsBroadPhaseLayerFilter);
    Jolt.destroy(world.objectLayerPairFilter);
    Jolt.destroy(world.broadPhaseLayerInterface);
  }

  const imports = {
    pj_world_create(configPtr, outWorldPtr) {
      assertReady();
      if (!configPtr || !outWorldPtr) return 0;
      if (configPtr + worldConfigSize > view().byteLength) return 0;

      const gravity = readVec3(configPtr + 0);
      const maxBodies = readU32(configPtr + 12);
      const maxBodyPairs = readU32(configPtr + 16);
      const maxContactConstraints = readU32(configPtr + 20);
      const maxJobs = readU32(configPtr + 28);

      const broadPhaseLayerInterface = new Jolt.BroadPhaseLayerInterfaceTable(kMaxLayers, kMaxLayers);
      for (let i = 0; i < kMaxLayers; i += 1) {
        const layer = new Jolt.BroadPhaseLayer(i);
        try {
          broadPhaseLayerInterface.MapObjectToBroadPhaseLayer(i, layer);
        } finally {
          Jolt.destroy(layer);
        }
      }

      const objectLayerPairFilter = new Jolt.ObjectLayerPairFilterTable(kMaxLayers);
      const objectVsBroadPhaseLayerFilter = new Jolt.ObjectVsBroadPhaseLayerFilterTable(
        broadPhaseLayerInterface,
        kMaxLayers,
        objectLayerPairFilter,
        kMaxLayers,
      );
      const settings = new Jolt.JoltSettings();
      settings.mMaxBodies = maxBodies > 0 ? maxBodies : 65536;
      settings.mMaxBodyPairs = maxBodyPairs > 0 ? maxBodyPairs : 65536;
      settings.mMaxContactConstraints = maxContactConstraints > 0 ? maxContactConstraints : 10240;
      settings.mMaxWorkerThreads = maxJobs > 0 ? maxJobs : 0;
      settings.mBroadPhaseLayerInterface = broadPhaseLayerInterface;
      settings.mObjectLayerPairFilter = objectLayerPairFilter;
      settings.mObjectVsBroadPhaseLayerFilter = objectVsBroadPhaseLayerFilter;

      const joltInterface = new Jolt.JoltInterface(settings);
      const physicsSystem = joltInterface.GetPhysicsSystem();
      const bodyInterface = physicsSystem.GetBodyInterface();
      const gravityVec = joltVec3(gravity);
      try {
        physicsSystem.SetGravity(gravityVec);
      } finally {
        Jolt.destroy(gravityVec);
      }

      const handle = nextWorldHandle++;
      worlds.set(handle, {
        joltInterface,
        settings,
        physicsSystem,
        bodyInterface,
        broadPhaseLayerInterface,
        objectLayerPairFilter,
        objectVsBroadPhaseLayerFilter,
        bodies: new Map(),
        shapes: [],
      });
      writeU32(outWorldPtr, handle);
      return 1;
    },

    pj_world_destroy(worldHandle) {
      assertReady();
      const handle = worldHandle >>> 0;
      const world = worlds.get(handle);
      if (!world) return;
      worlds.delete(handle);
      destroyWorld(world);
    },

    pj_world_step(worldHandle, dt, collisionSteps, outStepMsPtr, outBodyCountPtr, outActiveBodyCountPtr) {
      assertReady();
      const world = getWorld(worldHandle);
      const start = performance.now();
      world.joltInterface.Step(dt, collisionSteps);
      const elapsed = performance.now() - start;
      if (outStepMsPtr) writeF32(outStepMsPtr, elapsed);
      if (outBodyCountPtr) writeU32(outBodyCountPtr, world.physicsSystem.GetNumBodies());
      if (outActiveBodyCountPtr) {
        const active =
          world.physicsSystem.GetNumActiveBodies(Jolt.EBodyType_RigidBody) +
          world.physicsSystem.GetNumActiveBodies(Jolt.EBodyType_SoftBody);
        writeU32(outActiveBodyCountPtr, active);
      }
      return 1;
    },

    pj_body_create(
      worldHandle,
      descPtr,
      meshVerticesPtr,
      meshVertexCount,
      meshIndicesPtr,
      meshIndexCount,
      heightSamplesPtr,
      heightSampleCount,
      outBodyIdPtr,
    ) {
      assertReady();
      if (!descPtr || !outBodyIdPtr) return 0;
      if (descPtr + bodyDescSize > view().byteLength) return 0;

      const world = getWorld(worldHandle);
      const desc = readBodyDesc(descPtr);
      const shape = makeShape(
        desc,
        meshVerticesPtr,
        meshVertexCount,
        meshIndicesPtr,
        meshIndexCount,
        heightSamplesPtr,
        heightSampleCount,
      );
      if (!shape) return 0;

      const motionType = motionTypeFromDesc(desc.motion_type);
      const position = joltRVec3(desc.position);
      const rotation = joltQuat(desc.rotation);
      const linearVelocity = joltVec3(desc.linear_velocity);
      const angularVelocity = joltVec3(desc.angular_velocity);

      try {
        const settings = new Jolt.BodyCreationSettings(
          shape,
          position,
          rotation,
          motionType,
          desc.object_layer,
        );
        try {
          settings.mLinearVelocity = linearVelocity;
          settings.mAngularVelocity = angularVelocity;
          settings.mUserData = desc.user_data;
          settings.mAllowedDOFs = allowedDofsFromMask(desc.allowed_dofs_mask);
          settings.mIsSensor = desc.is_sensor;
          settings.mAllowSleeping = desc.allow_sleep;
          settings.mMotionQuality = desc.use_ccd ? Jolt.EMotionQuality_LinearCast : Jolt.EMotionQuality_Discrete;
          settings.mCollideKinematicVsNonDynamic = desc.collide_kinematic_vs_non_dynamic;
          settings.mEnhancedInternalEdgeRemoval = desc.use_enhanced_internal_edge_removal;
          settings.mFriction = desc.friction;
          settings.mRestitution = desc.restitution;
          settings.mLinearDamping = desc.linear_damping;
          settings.mAngularDamping = desc.angular_damping;
          settings.mGravityFactor = desc.gravity_scale;

          if (motionType !== Jolt.EMotionType_Static) {
            if (desc.override_mass) {
              settings.mOverrideMassProperties = Jolt.EOverrideMassProperties_CalculateInertia;
              const massProps = settings.mMassPropertiesOverride;
              massProps.mMass = desc.mass;
              settings.mMassPropertiesOverride = massProps;
            } else {
              settings.mOverrideMassProperties = Jolt.EOverrideMassProperties_CalculateMassAndInertia;
            }
          }

          if (
            (desc.shape_kind === pjShapeKind.triangle_mesh || desc.shape_kind === pjShapeKind.height_field) &&
            motionType !== Jolt.EMotionType_Static
          ) {
            return 0;
          }

          setCollisionMask(world, desc.object_layer, desc.collision_mask);

          const activation =
            motionType === Jolt.EMotionType_Static ? Jolt.EActivation_DontActivate : Jolt.EActivation_Activate;
          const bodyId = world.bodyInterface.CreateAndAddBody(settings, activation);
          const bodyValue = bodyId.GetIndexAndSequenceNumber();
          world.bodies.set(bodyValue, bodyValue);
          world.shapes.push(shape);
          writeU32(outBodyIdPtr, bodyValue);
          Jolt.destroy(bodyId);
          return 1;
        } finally {
          Jolt.destroy(settings);
        }
      } finally {
        Jolt.destroy(position);
        Jolt.destroy(rotation);
        Jolt.destroy(linearVelocity);
        Jolt.destroy(angularVelocity);
      }
    },

    pj_body_remove_destroy(worldHandle, bodyIdValue) {
      assertReady();
      const world = getWorld(worldHandle);
      const bodyId = new Jolt.BodyID(bodyIdValue >>> 0);
      try {
        if (world.bodyInterface.IsAdded(bodyId)) {
          world.bodyInterface.RemoveBody(bodyId);
        }
        world.bodyInterface.DestroyBody(bodyId);
      } finally {
        world.bodies.delete(bodyIdValue >>> 0);
        Jolt.destroy(bodyId);
      }
      return 1;
    },

    pj_body_set_transform(worldHandle, bodyIdValue, positionPtr, rotationPtr, activate) {
      assertReady();
      if (!positionPtr || !rotationPtr) return 0;
      const world = getWorld(worldHandle);
      const bodyId = new Jolt.BodyID(bodyIdValue >>> 0);
      const position = joltRVec3(readVec3(positionPtr));
      const rotation = joltQuat(readQuat(rotationPtr));
      const activation = activate ? Jolt.EActivation_Activate : Jolt.EActivation_DontActivate;
      try {
        world.bodyInterface.SetPositionAndRotationWhenChanged(bodyId, position, rotation, activation);
      } finally {
        Jolt.destroy(bodyId);
        Jolt.destroy(position);
        Jolt.destroy(rotation);
      }
      return 1;
    },

    pj_body_set_velocities(worldHandle, bodyIdValue, linearVelocityPtr, angularVelocityPtr) {
      assertReady();
      if (!linearVelocityPtr || !angularVelocityPtr) return 0;
      const world = getWorld(worldHandle);
      const bodyId = new Jolt.BodyID(bodyIdValue >>> 0);
      const linearVelocity = joltVec3(readVec3(linearVelocityPtr));
      const angularVelocity = joltVec3(readVec3(angularVelocityPtr));
      try {
        world.bodyInterface.SetLinearAndAngularVelocity(bodyId, linearVelocity, angularVelocity);
      } finally {
        Jolt.destroy(bodyId);
        Jolt.destroy(linearVelocity);
        Jolt.destroy(angularVelocity);
      }
      return 1;
    },

    pj_body_move_kinematic(worldHandle, bodyIdValue, positionPtr, rotationPtr, dt) {
      assertReady();
      if (!positionPtr || !rotationPtr) return 0;
      const world = getWorld(worldHandle);
      const bodyId = new Jolt.BodyID(bodyIdValue >>> 0);
      const position = joltRVec3(readVec3(positionPtr));
      const rotation = joltQuat(readQuat(rotationPtr));
      try {
        world.bodyInterface.MoveKinematic(bodyId, position, rotation, dt);
      } finally {
        Jolt.destroy(bodyId);
        Jolt.destroy(position);
        Jolt.destroy(rotation);
      }
      return 1;
    },

    pj_body_get_state(worldHandle, bodyIdValue, outStatePtr) {
      assertReady();
      if (!outStatePtr) return 0;
      const world = getWorld(worldHandle);
      const bodyId = new Jolt.BodyID(bodyIdValue >>> 0);
      let position = null;
      let rotation = null;
      let linearVelocity = null;
      let angularVelocity = null;
      try {
        position = new Jolt.RVec3();
        rotation = new Jolt.Quat();
        linearVelocity = new Jolt.Vec3();
        angularVelocity = new Jolt.Vec3();

        world.bodyInterface.GetPositionAndRotation(bodyId, position, rotation);
        world.bodyInterface.GetLinearAndAngularVelocity(bodyId, linearVelocity, angularVelocity);

        writeVec3(outStatePtr + 0, vec3FromJolt(position));
        writeQuat(outStatePtr + 12, quatFromJolt(rotation));
        writeVec3(outStatePtr + 28, vec3FromJolt(linearVelocity));
        writeVec3(outStatePtr + 40, vec3FromJolt(angularVelocity));
        writeU64(outStatePtr + 56, world.bodyInterface.GetUserData(bodyId));
        return 1;
      } finally {
        Jolt.destroy(bodyId);
        if (position) Jolt.destroy(position);
        if (rotation) Jolt.destroy(rotation);
        if (linearVelocity) Jolt.destroy(linearVelocity);
        if (angularVelocity) Jolt.destroy(angularVelocity);
      }
    },

    pj_world_cast_ray(worldHandle, originPtr, directionPtr, maxDistance, sourceLayer, collisionMask, outHitPtr) {
      assertReady();
      if (!originPtr || !directionPtr || !outHitPtr) return 0;
      const world = getWorld(worldHandle);

      const origin = joltRVec3(readVec3(originPtr));
      let direction = joltVec3(readVec3(directionPtr));
      const length = direction.Length();
      if (length > 0.0) {
        const normalized = direction.Div(length);
        Jolt.destroy(direction);
        direction = normalized.Mul(maxDistance);
        Jolt.destroy(normalized);
      }

      const ray = new Jolt.RRayCast(origin, direction);
      const settings = new Jolt.RayCastSettings();
      const collector = new Jolt.CastRayClosestHitCollisionCollector();
      const broadPhaseFilter = new Jolt.DefaultBroadPhaseLayerFilter(
        world.objectVsBroadPhaseLayerFilter,
        sourceLayer >>> 0,
      );
      class MaskObjectLayerFilter extends Jolt.ObjectLayerFilterJS {
        constructor(mask) {
          super();
          this.mask = mask >>> 0;
        }
        ShouldCollide(layer) {
          if (layer >= 32) return false;
          return (this.mask & (1 << layer)) !== 0;
        }
      }
      const objectLayerFilter = new MaskObjectLayerFilter(collisionMask >>> 0);
      const bodyFilter = new Jolt.BodyFilter();
      const shapeFilter = new Jolt.ShapeFilter();
      let didHit = false;
      try {
        world.physicsSystem.GetNarrowPhaseQuery().CastRay(
          ray,
          settings,
          collector,
          broadPhaseFilter,
          objectLayerFilter,
          bodyFilter,
          shapeFilter,
        );

        didHit = collector.HadHit();
        writeBool(outHitPtr + 0, didHit);
        if (!didHit) return 1;

        const hit = collector.mHit;
        const hitBody = hit.mBodyID;
        const bodyValue = hitBody.GetIndexAndSequenceNumber();
        const hitPosition = ray.GetPointOnRay(hit.mFraction);
        const transformedShape = world.bodyInterface.GetTransformedShape(hitBody);
        const hitNormal = transformedShape.GetWorldSpaceSurfaceNormal(hit.mSubShapeID2, hitPosition);
        try {
          writeU32(outHitPtr + 4, bodyValue);
          writeU64(outHitPtr + 8, world.bodyInterface.GetUserData(hitBody));
          writeVec3(outHitPtr + 16, vec3FromJolt(hitPosition));
          writeVec3(outHitPtr + 28, vec3FromJolt(hitNormal));
          writeF32(outHitPtr + 40, hit.mFraction * maxDistance);
        } finally {
          Jolt.destroy(hitPosition);
          Jolt.destroy(hitNormal);
          Jolt.destroy(transformedShape);
        }
        return 1;
      } finally {
        Jolt.destroy(origin);
        Jolt.destroy(direction);
        Jolt.destroy(ray);
        Jolt.destroy(settings);
        Jolt.destroy(collector);
        Jolt.destroy(broadPhaseFilter);
        Jolt.destroy(objectLayerFilter);
        Jolt.destroy(bodyFilter);
        Jolt.destroy(shapeFilter);
      }
    },
  };

  return {
    init,
    imports,
  };
}
