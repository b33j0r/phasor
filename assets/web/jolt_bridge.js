import initJolt from "./vendor/jolt/jolt-physics.wasm-compat.js";

const kMaxLayers = 32;
const kJoltGlobalStateKey = "__phasorJoltGlobalState";

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
const characterDescSize = 152;
const characterStateSize = 88;
const raycastHitSize = 48;
const shapecastHitSize = 48;

export function createJoltEnv(getMemoryView) {
  const globalState = globalThis[kJoltGlobalStateKey] ??= {
    Jolt: null,
    initPromise: null,
  };
  let Jolt = globalState.Jolt;
  let nextWorldHandle = 1;
  const worlds = new Map();

  function assertReady() {
    if (!Jolt) {
      throw new Error("JoltPhysics.js is not initialized");
    }
  }

  async function init() {
    if (globalState.Jolt) {
      Jolt = globalState.Jolt;
      return globalState.Jolt;
    }
    if (!globalState.initPromise) {
      globalState.initPromise = initJolt().then((loaded) => {
        globalState.Jolt = loaded;
        Jolt = loaded;
        return loaded;
      }).catch((err) => {
        globalState.initPromise = null;
        throw err;
      });
    }
    return globalState.initPromise;
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
    return new globalState.Jolt.Vec3(value.x, value.y, value.z);
  }

  function joltRVec3(value) {
    return new globalState.Jolt.RVec3(value.x, value.y, value.z);
  }

  function joltQuat(value) {
    return new globalState.Jolt.Quat(value.x, value.y, value.z, value.w);
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

  function writeShapeCastHit(ptr, didHit, bodyValue, userData, position, normal, fraction) {
    writeBool(ptr + 0, didHit);
    if (!didHit) return;
    writeU32(ptr + 4, bodyValue >>> 0);
    writeU64(ptr + 8, userData);
    writeVec3(ptr + 16, position);
    writeVec3(ptr + 28, normal);
    writeF32(ptr + 40, fraction);
  }

  function motionTypeFromDesc(motionType) {
    switch (motionType) {
      case pjMotionType.static:
        return globalState.Jolt.EMotionType_Static;
      case pjMotionType.kinematic:
        return globalState.Jolt.EMotionType_Kinematic;
      case pjMotionType.dynamic:
      default:
        return globalState.Jolt.EMotionType_Dynamic;
    }
  }

  function allowedDofsFromMask(mask) {
    let out = 0;
    if ((mask & (1 << 0)) !== 0) out |= globalState.Jolt.EAllowedDOFs_TranslationX;
    if ((mask & (1 << 1)) !== 0) out |= globalState.Jolt.EAllowedDOFs_TranslationY;
    if ((mask & (1 << 2)) !== 0) out |= globalState.Jolt.EAllowedDOFs_TranslationZ;
    if ((mask & (1 << 3)) !== 0) out |= globalState.Jolt.EAllowedDOFs_RotationX;
    if ((mask & (1 << 4)) !== 0) out |= globalState.Jolt.EAllowedDOFs_RotationY;
    if ((mask & (1 << 5)) !== 0) out |= globalState.Jolt.EAllowedDOFs_RotationZ;
    return out === 0 ? globalState.Jolt.EAllowedDOFs_All : out;
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

  function readCharacterDesc(ptr) {
    if (!ptr) return null;
    return {
      user_data: readU64(ptr + 0),
      shape_kind: readI32(ptr + 8),
      object_layer: readU32(ptr + 12),
      collision_mask: readU32(ptr + 16),
      position: readVec3(ptr + 20),
      rotation: readQuat(ptr + 32),
      linear_velocity: readVec3(ptr + 48),
      half_extents: readVec3(ptr + 60),
      radius: readF32(ptr + 72),
      half_height: readF32(ptr + 76),
      mass: readF32(ptr + 80),
      max_strength: readF32(ptr + 84),
      max_slope_angle_radians: readF32(ptr + 88),
      padding: readF32(ptr + 92),
      penetration_recovery_speed: readF32(ptr + 96),
      predictive_contact_distance: readF32(ptr + 100),
      max_collision_iterations: readU32(ptr + 104),
      max_constraint_iterations: readU32(ptr + 108),
      min_time_remaining: readF32(ptr + 112),
      collision_tolerance: readF32(ptr + 116),
      max_hits: readU32(ptr + 120),
      hit_reduction_cos_max_angle: readF32(ptr + 124),
      enhanced_internal_edge_removal: readBool(ptr + 128),
      stick_to_floor_distance: readF32(ptr + 132),
      step_up_height: readF32(ptr + 136),
      step_forward_min_distance: readF32(ptr + 140),
      step_forward_test_distance: readF32(ptr + 144),
      step_down_extra_distance: readF32(ptr + 148),
    };
  }

  function writeCharacterState(ptr, character, world) {
    const position = character.GetPosition();
    const rotation = character.GetRotation();
    const linearVelocity = character.GetLinearVelocity();
    const groundNormal = character.GetGroundNormal();
    const groundVelocity = character.GetGroundVelocity();
    const groundBodyId = character.GetGroundBodyID();
    try {
      writeVec3(ptr + 0, vec3FromJolt(position));
      writeQuat(ptr + 12, quatFromJolt(rotation));
      writeVec3(ptr + 28, vec3FromJolt(linearVelocity));
      writeU32(ptr + 40, character.GetGroundState());
      writeVec3(ptr + 44, vec3FromJolt(groundNormal));
      writeVec3(ptr + 56, vec3FromJolt(groundVelocity));
      const groundBodyValue = bodyIdValueOrZero(groundBodyId);
      writeU32(ptr + 68, groundBodyValue);
      writeU64(ptr + 72, groundBodyValue === 0 ? 0 : character.GetGroundUserData());
      writeBool(ptr + 80, character.GetMaxHitsExceeded());
    } finally {}
  }

  function bodyIdValueOrZero(bodyId) {
    if (!bodyId) return 0;
    if (typeof bodyId.IsInvalid === "function") {
      return bodyId.IsInvalid() ? 0 : bodyId.GetIndexAndSequenceNumber();
    }
    if (typeof bodyId.isInvalid === "function") {
      return bodyId.isInvalid() ? 0 : bodyId.GetIndexAndSequenceNumber();
    }
    if (typeof bodyId.GetIndexAndSequenceNumber === "function") {
      const value = bodyId.GetIndexAndSequenceNumber() >>> 0;
      if (value === 0 || value === 0xffffffff) return 0;
      return value;
    }
    return 0;
  }

  function getWorld(handle) {
    const world = worlds.get(handle >>> 0);
    if (!world) throw new Error(`invalid Jolt world handle ${handle}`);
    return world;
  }

  function encodeObjectLayer(world, objectLayer, mask) {
    const group = 1 << (objectLayer & 31);
    return world.objectLayerPairFilter.sGetObjectLayer(group >>> 0, mask >>> 0);
  }

  function destroyWorld(world) {
    if (!world) return;
    if (world.characters) {
      for (const record of world.characters.values()) {
        try {
          world.characterVsCharacterCollision.Remove(record.character);
        } catch (_) {}
        try {
          Jolt.destroy(record.character);
        } catch (_) {}
        try {
          Jolt.destroy(record.updateSettings);
        } catch (_) {}
        if (record.updateVectors) {
          for (const value of record.updateVectors) {
            try {
              Jolt.destroy(value);
            } catch (_) {}
          }
        }
      }
      world.characters.clear();
    }
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
    Jolt.destroy(world.characterVsCharacterCollision);
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

      const broadPhaseLayerInterface = new Jolt.BroadPhaseLayerInterfaceMask(1);
      const broadPhaseLayer = new Jolt.BroadPhaseLayer(0);
      try {
        broadPhaseLayerInterface.ConfigureLayer(broadPhaseLayer, 0xffff_ffff, 0);
      } finally {
        Jolt.destroy(broadPhaseLayer);
      }

      const objectLayerPairFilter = new Jolt.ObjectLayerPairFilterMask();
      const objectVsBroadPhaseLayerFilter = new Jolt.ObjectVsBroadPhaseLayerFilterMask(broadPhaseLayerInterface);
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
        characterVsCharacterCollision: new Jolt.CharacterVsCharacterCollisionSimple(),
        bodies: new Map(),
        characters: new Map(),
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
        const objectLayer = encodeObjectLayer(world, desc.object_layer, desc.collision_mask);
        const settings = new Jolt.BodyCreationSettings(
          shape,
          position,
          rotation,
          motionType,
          objectLayer,
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

    pj_character_create(worldHandle, descPtr, outCharacterIdPtr) {
      assertReady();
      if (!descPtr || !outCharacterIdPtr) return 0;
      if (descPtr + characterDescSize > view().byteLength) return 0;

      const world = getWorld(worldHandle);
      const desc = readCharacterDesc(descPtr);
      const shape = makeShape(desc, 0, 0, 0, 0, 0, 0);
      if (!shape) return 0;

      const settings = new Jolt.CharacterVirtualSettings();
      const position = joltRVec3(desc.position);
      const rotation = joltQuat(desc.rotation);
      const linearVelocity = joltVec3(desc.linear_velocity);
      const stickToFloorStepDown = new Jolt.Vec3(0.0, -desc.stick_to_floor_distance, 0.0);
      const walkStairsStepUp = new Jolt.Vec3(0.0, desc.step_up_height, 0.0);
      const walkStairsStepDownExtra = new Jolt.Vec3(0.0, -desc.step_down_extra_distance, 0.0);

      try {
        settings.mShape = shape;
        settings.mMass = desc.mass;
        settings.mMaxStrength = desc.max_strength;
        settings.mMaxSlopeAngle = desc.max_slope_angle_radians;
        settings.mCharacterPadding = desc.padding;
        settings.mPenetrationRecoverySpeed = desc.penetration_recovery_speed;
        settings.mPredictiveContactDistance = desc.predictive_contact_distance;
        settings.mMaxCollisionIterations = desc.max_collision_iterations;
        settings.mMaxConstraintIterations = desc.max_constraint_iterations;
        settings.mMinTimeRemaining = desc.min_time_remaining;
        settings.mCollisionTolerance = desc.collision_tolerance;
        settings.mMaxNumHits = desc.max_hits;
        settings.mHitReductionCosMaxAngle = desc.hit_reduction_cos_max_angle;
        settings.mEnhancedInternalEdgeRemoval = desc.enhanced_internal_edge_removal;

        const character = new Jolt.CharacterVirtual(settings, position, rotation, world.physicsSystem);
        try {
          character.SetUserData(desc.user_data);
          character.SetLinearVelocity(linearVelocity);
          character.SetCharacterVsCharacterCollision(world.characterVsCharacterCollision);
          world.characterVsCharacterCollision.Add(character);
          world.shapes.push(shape);

          const updateSettings = new Jolt.ExtendedUpdateSettings();
          updateSettings.mStickToFloorStepDown = stickToFloorStepDown;
          updateSettings.mWalkStairsStepUp = walkStairsStepUp;
          updateSettings.mWalkStairsMinStepForward = desc.step_forward_min_distance;
          updateSettings.mWalkStairsStepForwardTest = desc.step_forward_test_distance;
          updateSettings.mWalkStairsStepDownExtra = walkStairsStepDownExtra;

          let handle = 1;
          while (world.characters.has(handle)) handle += 1;
          world.characters.set(handle, {
            character,
            collisionMask: desc.collision_mask >>> 0,
            updateSettings,
            updateVectors: [stickToFloorStepDown, walkStairsStepUp, walkStairsStepDownExtra],
          });
          writeU32(outCharacterIdPtr, handle);
          return 1;
        } catch (err) {
          try {
            Jolt.destroy(character);
          } catch (_) {}
          throw err;
        }
      } finally {
        Jolt.destroy(settings);
        Jolt.destroy(position);
        Jolt.destroy(rotation);
        Jolt.destroy(linearVelocity);
      }
    },

    pj_character_remove_destroy(worldHandle, characterIdValue) {
      assertReady();
      const world = getWorld(worldHandle);
      const record = world.characters.get(characterIdValue >>> 0);
      if (!record) return 0;
      world.characters.delete(characterIdValue >>> 0);
      try {
        world.characterVsCharacterCollision.Remove(record.character);
      } catch (_) {}
      try {
        Jolt.destroy(record.character);
      } catch (_) {}
      try {
        Jolt.destroy(record.updateSettings);
      } catch (_) {}
      for (const value of record.updateVectors) {
        try {
          Jolt.destroy(value);
        } catch (_) {}
      }
      return 1;
    },

    pj_character_set_transform(worldHandle, characterIdValue, positionPtr, rotationPtr) {
      assertReady();
      if (!positionPtr || !rotationPtr) return 0;
      const world = getWorld(worldHandle);
      const record = world.characters.get(characterIdValue >>> 0);
      if (!record) return 0;
      const position = joltRVec3(readVec3(positionPtr));
      const rotation = joltQuat(readQuat(rotationPtr));
      try {
        record.character.SetPosition(position);
        record.character.SetRotation(rotation);
      } finally {
        Jolt.destroy(position);
        Jolt.destroy(rotation);
      }
      return 1;
    },

    pj_character_set_linear_velocity(worldHandle, characterIdValue, linearVelocityPtr) {
      assertReady();
      if (!linearVelocityPtr) return 0;
      const world = getWorld(worldHandle);
      const record = world.characters.get(characterIdValue >>> 0);
      if (!record) return 0;
      const linearVelocity = joltVec3(readVec3(linearVelocityPtr));
      try {
        record.character.SetLinearVelocity(linearVelocity);
      } finally {
        Jolt.destroy(linearVelocity);
      }
      return 1;
    },

    pj_character_extended_update(worldHandle, characterIdValue, dt, gravityPtr) {
      assertReady();
      if (!gravityPtr) return 0;
      const world = getWorld(worldHandle);
      const record = world.characters.get(characterIdValue >>> 0);
      if (!record) return 0;

      const gravity = joltVec3(readVec3(gravityPtr));
      const sourceObjectLayer = world.objectLayerPairFilter.sGetObjectLayer(1, record.collisionMask);
      const broadPhaseFilter = new Jolt.DefaultBroadPhaseLayerFilter(
        world.objectVsBroadPhaseLayerFilter,
        sourceObjectLayer,
      );
      const objectLayerFilter = new Jolt.DefaultObjectLayerFilter(
        world.objectLayerPairFilter,
        sourceObjectLayer,
      );
      const bodyFilter = new Jolt.BodyFilter();
      const shapeFilter = new Jolt.ShapeFilter();
      const velocity = record.character.CancelVelocityTowardsSteepSlopes(record.character.GetLinearVelocity());
      try {
        record.character.SetLinearVelocity(velocity);
        record.character.ExtendedUpdate(
          dt,
          gravity,
          record.updateSettings,
          broadPhaseFilter,
          objectLayerFilter,
          bodyFilter,
          shapeFilter,
          world.joltInterface.GetTempAllocator(),
        );
      } finally {
        Jolt.destroy(gravity);
        Jolt.destroy(broadPhaseFilter);
        Jolt.destroy(objectLayerFilter);
        Jolt.destroy(bodyFilter);
        Jolt.destroy(shapeFilter);
        Jolt.destroy(velocity);
      }
      return 1;
    },

    pj_character_get_state(worldHandle, characterIdValue, outStatePtr) {
      assertReady();
      if (!outStatePtr) return 0;
      if (outStatePtr + characterStateSize > view().byteLength) return 0;
      const world = getWorld(worldHandle);
      const record = world.characters.get(characterIdValue >>> 0);
      if (!record) return 0;
      writeCharacterState(outStatePtr, record.character, world);
      return 1;
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
      const sourceObjectLayer = encodeObjectLayer(world, sourceLayer >>> 0, collisionMask >>> 0);
      const broadPhaseFilter = new Jolt.DefaultBroadPhaseLayerFilter(
        world.objectVsBroadPhaseLayerFilter,
        sourceObjectLayer,
      );
      const objectLayerFilter = new Jolt.DefaultObjectLayerFilter(
        world.objectLayerPairFilter,
        sourceObjectLayer,
      );
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

    pj_world_cast_shape(worldHandle, descPtr, translationPtr, sourceLayer, collisionMask, outHitPtr) {
      assertReady();
      if (!descPtr || !translationPtr || !outHitPtr) return 0;
      if (descPtr + bodyDescSize > view().byteLength) return 0;
      if (outHitPtr + shapecastHitSize > view().byteLength) return 0;

      const world = getWorld(worldHandle);
      const desc = readBodyDesc(descPtr);
      const shape = makeShape(desc, 0, 0, 0, 0, 0, 0);
      if (!shape) return 0;

      const rotation = joltQuat(desc.rotation);
      const position = joltRVec3(desc.position);
      const direction = joltVec3(readVec3(translationPtr));
      const unitScale = new Jolt.Vec3(1.0, 1.0, 1.0);
      const start = new Jolt.RMat44().sRotationTranslation(rotation, position);
      const settings = new Jolt.ShapeCastSettings();
      settings.mReturnDeepestPoint = true;
      const collector = new Jolt.CastShapeClosestHitCollisionCollector();
      const sourceObjectLayer = encodeObjectLayer(world, sourceLayer >>> 0, collisionMask >>> 0);
      const broadPhaseFilter = new Jolt.DefaultBroadPhaseLayerFilter(
        world.objectVsBroadPhaseLayerFilter,
        sourceObjectLayer,
      );
      const objectLayerFilter = new Jolt.DefaultObjectLayerFilter(
        world.objectLayerPairFilter,
        sourceObjectLayer,
      );
      const bodyFilter = new Jolt.BodyFilter();
      const shapeFilter = new Jolt.ShapeFilter();
      const shapeCast = new Jolt.RShapeCast(shape, unitScale, start, direction);
      const baseOffset = new Jolt.RVec3().sZero();
      let didHit = false;
      try {
        world.physicsSystem.GetNarrowPhaseQuery().CastShape(
          shapeCast,
          settings,
          baseOffset,
          collector,
          broadPhaseFilter,
          objectLayerFilter,
          bodyFilter,
          shapeFilter,
        );

        didHit = collector.HadHit();
        if (!didHit) {
          writeShapeCastHit(outHitPtr, false, 0, 0, { x: 0, y: 0, z: 0 }, { x: 0, y: 0, z: 0 }, 0);
          return 1;
        }

        const hit = collector.mHit;
        const hitBody = hit.mBodyID2;
        const bodyValue = hitBody.GetIndexAndSequenceNumber();
        const userData = world.bodyInterface.GetUserData(hitBody);
        const hitPosition = hit.mContactPointOn2;
        const hitNormal = hit.mPenetrationAxis.NormalizedOr(new Jolt.Vec3().sAxisY());
        try {
          writeShapeCastHit(
            outHitPtr,
            true,
            bodyValue,
            userData,
            vec3FromJolt(hitPosition),
            vec3FromJolt(hitNormal),
            hit.mFraction,
          );
        } finally {
          Jolt.destroy(hitNormal);
        }
        return 1;
      } finally {
        Jolt.destroy(shape);
        Jolt.destroy(rotation);
        Jolt.destroy(position);
        Jolt.destroy(direction);
        Jolt.destroy(unitScale);
        Jolt.destroy(start);
        Jolt.destroy(settings);
        Jolt.destroy(collector);
        Jolt.destroy(broadPhaseFilter);
        Jolt.destroy(objectLayerFilter);
        Jolt.destroy(bodyFilter);
        Jolt.destroy(shapeFilter);
        Jolt.destroy(shapeCast);
        Jolt.destroy(baseOffset);
      }
    },
  };

  return {
    init,
    imports,
  };
}
