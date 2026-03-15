#include "physics_jolt_c.h"

#include <algorithm>
#include <chrono>
#include <mutex>
#include <new>
#include <thread>
#include <vector>

#include <Jolt/Jolt.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Geometry/IndexedTriangle.h>
#include <Jolt/Physics/Body/AllowedDOFs.h>
#include <Jolt/Physics/Body/BodyActivationListener.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyInterface.h>
#include <Jolt/Physics/Collision/BroadPhase/BroadPhaseLayer.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/CollisionCollectorImpl.h>
#include <Jolt/Physics/Collision/NarrowPhaseQuery.h>
#include <Jolt/Physics/Collision/ObjectLayer.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/CylinderShape.h>
#include <Jolt/Physics/Collision/Shape/HeightFieldShape.h>
#include <Jolt/Physics/Collision/Shape/MeshShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/PhysicsSystem.h>

using namespace JPH;

struct pj_world;

namespace {

constexpr uint32_t kMaxLayers = 32;

struct JoltGlobals {
    std::mutex mutex;
    uint32_t ref_count = 0;
};

JoltGlobals &globals() {
    static JoltGlobals g;
    return g;
}

bool ensure_jolt_initialized() {
    auto &g = globals();
    std::scoped_lock lock(g.mutex);
    if (g.ref_count == 0) {
        RegisterDefaultAllocator();
        Factory::sInstance = new Factory();
        if (Factory::sInstance == nullptr) {
            return false;
        }
        RegisterTypes();
    }
    g.ref_count += 1;
    return true;
}

void release_jolt_initialized() {
    auto &g = globals();
    std::scoped_lock lock(g.mutex);
    if (g.ref_count == 0) {
        return;
    }
    g.ref_count -= 1;
    if (g.ref_count == 0) {
        UnregisterTypes();
        delete Factory::sInstance;
        Factory::sInstance = nullptr;
    }
}

Vec3 to_vec3(const float value[3]) {
    return Vec3(value[0], value[1], value[2]);
}

RVec3 to_rvec3(const float value[3]) {
    return RVec3(value[0], value[1], value[2]);
}

Quat to_quat(const float value[4]) {
    return Quat(value[0], value[1], value[2], value[3]);
}

void from_rvec3(RVec3Arg src, float out[3]) {
    out[0] = static_cast<float>(src.GetX());
    out[1] = static_cast<float>(src.GetY());
    out[2] = static_cast<float>(src.GetZ());
}

void from_vec3(Vec3Arg src, float out[3]) {
    out[0] = src.GetX();
    out[1] = src.GetY();
    out[2] = src.GetZ();
}

void from_quat(QuatArg src, float out[4]) {
    out[0] = src.GetX();
    out[1] = src.GetY();
    out[2] = src.GetZ();
    out[3] = src.GetW();
}

EAllowedDOFs allowed_dofs_from_mask(uint32_t mask) {
    EAllowedDOFs out = EAllowedDOFs::None;
    if ((mask & (1u << 0)) != 0) out |= EAllowedDOFs::TranslationX;
    if ((mask & (1u << 1)) != 0) out |= EAllowedDOFs::TranslationY;
    if ((mask & (1u << 2)) != 0) out |= EAllowedDOFs::TranslationZ;
    if ((mask & (1u << 3)) != 0) out |= EAllowedDOFs::RotationX;
    if ((mask & (1u << 4)) != 0) out |= EAllowedDOFs::RotationY;
    if ((mask & (1u << 5)) != 0) out |= EAllowedDOFs::RotationZ;
    return out == EAllowedDOFs::None ? EAllowedDOFs::All : out;
}

EMotionType motion_type_from_desc(pj_motion_type motion_type) {
    switch (motion_type) {
        case PJ_MOTION_STATIC: return EMotionType::Static;
        case PJ_MOTION_KINEMATIC: return EMotionType::Kinematic;
        case PJ_MOTION_DYNAMIC:
        default:
            return EMotionType::Dynamic;
    }
}

class LayerPairFilter final : public ObjectLayerPairFilter {
public:
    uint32_t masks[kMaxLayers] = {};

    bool ShouldCollide(ObjectLayer layer1, ObjectLayer layer2) const override {
        if (layer1 >= kMaxLayers || layer2 >= kMaxLayers) {
            return false;
        }
        const uint32_t bit1 = 1u << layer1;
        const uint32_t bit2 = 1u << layer2;
        return (masks[layer1] & bit2) != 0 && (masks[layer2] & bit1) != 0;
    }
};

class BroadPhaseInterface final : public BroadPhaseLayerInterface {
public:
    uint GetNumBroadPhaseLayers() const override {
        return kMaxLayers;
    }

    BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer layer) const override {
        return BroadPhaseLayer(layer);
    }

#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
    const char *GetBroadPhaseLayerName(BroadPhaseLayer layer) const override {
        (void)layer;
        return "phasor";
    }
#endif
};

class LayerVsBroadPhaseFilter final : public ObjectVsBroadPhaseLayerFilter {
public:
    explicit LayerVsBroadPhaseFilter(const LayerPairFilter &pair_filter) : mPairFilter(pair_filter) {}

    bool ShouldCollide(ObjectLayer layer1, BroadPhaseLayer layer2) const override {
        return mPairFilter.ShouldCollide(layer1, layer2.GetValue());
    }

private:
    const LayerPairFilter &mPairFilter;
};

class MaskObjectLayerFilter final : public ObjectLayerFilter {
public:
    explicit MaskObjectLayerFilter(uint32_t mask) : mMask(mask) {}

    bool ShouldCollide(ObjectLayer layer) const override {
        if (layer >= 32) return false;
        return (mMask & (1u << layer)) != 0;
    }

private:
    uint32_t mMask;
};

bool make_shape(
    const pj_body_desc &desc,
    const float *mesh_vertices_xyz,
    uint32_t mesh_vertex_count,
    const uint32_t *mesh_indices,
    uint32_t mesh_index_count,
    const float *height_samples,
    uint32_t height_sample_count,
    RefConst<Shape> &out_shape
) {
    switch (desc.shape_kind) {
        case PJ_SHAPE_SPHERE:
            out_shape = new SphereShape(desc.radius);
            return true;

        case PJ_SHAPE_CAPSULE:
            out_shape = new CapsuleShape(desc.half_height, desc.radius);
            return true;

        case PJ_SHAPE_BOX:
            out_shape = new BoxShape(to_vec3(desc.half_extents));
            return true;

        case PJ_SHAPE_CYLINDER:
            out_shape = new CylinderShape(desc.half_height, desc.radius);
            return true;

        case PJ_SHAPE_TRIANGLE_MESH: {
            if (mesh_vertices_xyz == nullptr || mesh_indices == nullptr || mesh_vertex_count == 0 || mesh_index_count < 3) {
                return false;
            }

            VertexList vertices;
            vertices.reserve(mesh_vertex_count);
            for (uint32_t i = 0; i < mesh_vertex_count; ++i) {
                const float *v = mesh_vertices_xyz + i * 3;
                vertices.push_back(Float3(v[0], v[1], v[2]));
            }

            IndexedTriangleList triangles;
            triangles.reserve(mesh_index_count / 3);
            for (uint32_t i = 0; i + 2 < mesh_index_count; i += 3) {
                triangles.emplace_back(mesh_indices[i], mesh_indices[i + 1], mesh_indices[i + 2], 0);
            }

            MeshShapeSettings settings(std::move(vertices), std::move(triangles));
            settings.mBuildQuality = MeshShapeSettings::EBuildQuality::FavorRuntimePerformance;
            Shape::ShapeResult result = settings.Create();
            if (result.HasError()) {
                return false;
            }
            out_shape = result.Get();
            return true;
        }

        case PJ_SHAPE_HEIGHT_FIELD: {
            if (height_samples == nullptr || desc.heightfield_sample_count == 0 || height_sample_count != desc.heightfield_sample_count * desc.heightfield_sample_count) {
                return false;
            }

            HeightFieldShapeSettings settings(
                height_samples,
                to_vec3(desc.heightfield_offset),
                to_vec3(desc.heightfield_scale),
                desc.heightfield_sample_count
            );
            Shape::ShapeResult result = settings.Create();
            if (result.HasError()) {
                return false;
            }
            out_shape = result.Get();
            return true;
        }
    }

    return false;
}

} // namespace

struct pj_world {
    BroadPhaseInterface broad_phase_interface;
    LayerPairFilter object_layer_pair_filter;
    LayerVsBroadPhaseFilter object_vs_broad_phase_filter;
    PhysicsSystem physics_system;
    TempAllocatorImpl *temp_allocator = nullptr;
    JobSystemThreadPool *job_system = nullptr;

    pj_world() : object_vs_broad_phase_filter(object_layer_pair_filter) {}
};

extern "C" bool pj_world_create(const pj_world_config *config, pj_world **out_world) {
    if (config == nullptr || out_world == nullptr) {
        return false;
    }
    if (!ensure_jolt_initialized()) {
        return false;
    }

    pj_world *world = new pj_world();
    if (world == nullptr) {
        release_jolt_initialized();
        return false;
    }

    const uint32_t temp_allocator_bytes = config->temp_allocator_bytes > 0 ? config->temp_allocator_bytes : 10u * 1024u * 1024u;
    world->temp_allocator = new TempAllocatorImpl(temp_allocator_bytes);
    if (world->temp_allocator == nullptr) {
        delete world;
        release_jolt_initialized();
        return false;
    }

    const uint32_t max_jobs = config->max_jobs > 0 ? config->max_jobs : cMaxPhysicsJobs;
    const uint32_t max_barriers = config->max_barriers > 0 ? config->max_barriers : cMaxPhysicsBarriers;
    const uint32_t thread_count = std::max(1u, std::thread::hardware_concurrency() > 1 ? std::thread::hardware_concurrency() - 1 : 1u);
    world->job_system = new JobSystemThreadPool(max_jobs, max_barriers, thread_count);
    if (world->job_system == nullptr) {
        delete world->temp_allocator;
        delete world;
        release_jolt_initialized();
        return false;
    }

    const uint32_t max_bodies = config->max_bodies > 0 ? config->max_bodies : 65536;
    const uint32_t max_body_pairs = config->max_body_pairs > 0 ? config->max_body_pairs : 65536;
    const uint32_t max_contact_constraints = config->max_contact_constraints > 0 ? config->max_contact_constraints : 10240;
    world->physics_system.Init(
        max_bodies,
        0,
        max_body_pairs,
        max_contact_constraints,
        world->broad_phase_interface,
        world->object_vs_broad_phase_filter,
        world->object_layer_pair_filter
    );
    world->physics_system.SetGravity(to_vec3(config->gravity));

    *out_world = world;
    return true;
}

extern "C" void pj_world_destroy(pj_world *world) {
    if (world == nullptr) {
        return;
    }
    delete world->job_system;
    delete world->temp_allocator;
    delete world;
    release_jolt_initialized();
}

extern "C" bool pj_world_step(pj_world *world, float dt, int collision_steps, float *out_step_ms, uint32_t *out_body_count, uint32_t *out_active_body_count) {
    if (world == nullptr) {
        return false;
    }

    const auto start = std::chrono::steady_clock::now();
    world->physics_system.Update(dt, collision_steps, world->temp_allocator, world->job_system);
    const auto elapsed = std::chrono::steady_clock::now() - start;

    if (out_step_ms != nullptr) {
        *out_step_ms = std::chrono::duration<float, std::milli>(elapsed).count();
    }
    if (out_body_count != nullptr) {
        *out_body_count = world->physics_system.GetNumBodies();
    }
    if (out_active_body_count != nullptr) {
        *out_active_body_count =
            world->physics_system.GetNumActiveBodies(EBodyType::RigidBody) +
            world->physics_system.GetNumActiveBodies(EBodyType::SoftBody);
    }
    return true;
}

extern "C" bool pj_body_create(
    pj_world *world,
    const pj_body_desc *desc,
    const float *mesh_vertices_xyz,
    uint32_t mesh_vertex_count,
    const uint32_t *mesh_indices,
    uint32_t mesh_index_count,
    const float *height_samples,
    uint32_t height_sample_count,
    uint32_t *out_body_id
) {
    if (world == nullptr || desc == nullptr || out_body_id == nullptr) {
        return false;
    }

    RefConst<Shape> shape;
    if (!make_shape(*desc, mesh_vertices_xyz, mesh_vertex_count, mesh_indices, mesh_index_count, height_samples, height_sample_count, shape)) {
        return false;
    }

    const EMotionType motion_type = motion_type_from_desc(desc->motion_type);
    BodyCreationSettings settings(shape.GetPtr(), to_rvec3(desc->position), to_quat(desc->rotation), motion_type, static_cast<ObjectLayer>(desc->object_layer));
    settings.mUserData = desc->user_data;
    settings.mAllowedDOFs = allowed_dofs_from_mask(desc->allowed_dofs_mask);
    settings.mIsSensor = desc->is_sensor;
    settings.mAllowSleeping = desc->allow_sleep;
    settings.mMotionQuality = desc->use_ccd ? EMotionQuality::LinearCast : EMotionQuality::Discrete;
    settings.mCollideKinematicVsNonDynamic = desc->collide_kinematic_vs_non_dynamic;
    settings.mEnhancedInternalEdgeRemoval = desc->use_enhanced_internal_edge_removal;
    settings.mFriction = desc->friction;
    settings.mRestitution = desc->restitution;
    settings.mLinearDamping = desc->linear_damping;
    settings.mAngularDamping = desc->angular_damping;
    settings.mGravityFactor = desc->gravity_scale;
    settings.mLinearVelocity = to_vec3(desc->linear_velocity);
    settings.mAngularVelocity = to_vec3(desc->angular_velocity);

    if (motion_type == EMotionType::Dynamic || motion_type == EMotionType::Kinematic) {
        if (desc->override_mass) {
            settings.mOverrideMassProperties = EOverrideMassProperties::CalculateInertia;
            settings.mMassPropertiesOverride.mMass = desc->mass;
        } else {
            settings.mOverrideMassProperties = EOverrideMassProperties::CalculateMassAndInertia;
        }
    }

    if (desc->shape_kind == PJ_SHAPE_TRIANGLE_MESH || desc->shape_kind == PJ_SHAPE_HEIGHT_FIELD) {
        if (motion_type != EMotionType::Static) {
            return false;
        }
        settings.mEnhancedInternalEdgeRemoval = true;
    }

    if (desc->object_layer < kMaxLayers) {
        world->object_layer_pair_filter.masks[desc->object_layer] |= desc->collision_mask;
    }

    BodyID body_id = world->physics_system.GetBodyInterface().CreateAndAddBody(settings, motion_type == EMotionType::Static ? EActivation::DontActivate : EActivation::Activate);
    if (body_id.IsInvalid()) {
        return false;
    }

    *out_body_id = body_id.GetIndexAndSequenceNumber();
    return true;
}

extern "C" bool pj_body_remove_destroy(pj_world *world, uint32_t body_id_value) {
    if (world == nullptr) {
        return false;
    }
    const BodyID body_id(body_id_value);
    BodyInterface &body_interface = world->physics_system.GetBodyInterface();
    if (body_interface.IsAdded(body_id)) {
        body_interface.RemoveBody(body_id);
    }
    body_interface.DestroyBody(body_id);
    return true;
}

extern "C" bool pj_body_set_transform(pj_world *world, uint32_t body_id_value, const float position[3], const float rotation[4], bool activate) {
    if (world == nullptr || position == nullptr || rotation == nullptr) {
        return false;
    }
    world->physics_system.GetBodyInterface().SetPositionAndRotationWhenChanged(
        BodyID(body_id_value),
        to_rvec3(position),
        to_quat(rotation),
        activate ? EActivation::Activate : EActivation::DontActivate
    );
    return true;
}

extern "C" bool pj_body_set_velocities(pj_world *world, uint32_t body_id_value, const float linear_velocity[3], const float angular_velocity[3]) {
    if (world == nullptr || linear_velocity == nullptr || angular_velocity == nullptr) {
        return false;
    }
    world->physics_system.GetBodyInterface().SetLinearAndAngularVelocity(BodyID(body_id_value), to_vec3(linear_velocity), to_vec3(angular_velocity));
    return true;
}

extern "C" bool pj_body_move_kinematic(pj_world *world, uint32_t body_id_value, const float position[3], const float rotation[4], float dt) {
    if (world == nullptr || position == nullptr || rotation == nullptr) {
        return false;
    }
    world->physics_system.GetBodyInterface().MoveKinematic(BodyID(body_id_value), to_rvec3(position), to_quat(rotation), dt);
    return true;
}

extern "C" bool pj_body_get_state(pj_world *world, uint32_t body_id_value, pj_body_state *out_state) {
    if (world == nullptr || out_state == nullptr) {
        return false;
    }

    const BodyID body_id(body_id_value);
    BodyInterface &body_interface = world->physics_system.GetBodyInterface();
    RVec3 position;
    Quat rotation;
    body_interface.GetPositionAndRotation(body_id, position, rotation);
    Vec3 linear_velocity;
    Vec3 angular_velocity;
    body_interface.GetLinearAndAngularVelocity(body_id, linear_velocity, angular_velocity);

    from_rvec3(position, out_state->position);
    from_quat(rotation, out_state->rotation);
    from_vec3(linear_velocity, out_state->linear_velocity);
    from_vec3(angular_velocity, out_state->angular_velocity);
    out_state->user_data = body_interface.GetUserData(body_id);
    return true;
}

extern "C" bool pj_world_cast_ray(
    pj_world *world,
    const float origin[3],
    const float direction[3],
    float max_distance,
    uint32_t source_layer,
    uint32_t collision_mask,
    pj_raycast_hit *out_hit
) {
    if (world == nullptr || origin == nullptr || direction == nullptr || out_hit == nullptr) {
        return false;
    }

    const Vec3 dir = to_vec3(direction);
    const RRayCast ray(to_rvec3(origin), dir.Normalized() * max_distance);
    RayCastResult hit;
    MaskObjectLayerFilter object_filter(collision_mask);
    const bool did_hit = world->physics_system.GetNarrowPhaseQuery().CastRay(ray, hit, {}, object_filter);

    out_hit->hit = did_hit;
    if (!did_hit) {
        return true;
    }

    const BodyLockRead lock(world->physics_system.GetBodyLockInterface(), hit.mBodyID);
    if (!lock.Succeeded()) {
        out_hit->hit = false;
        return false;
    }

    const Body &body = lock.GetBody();
    const RVec3 point = ray.GetPointOnRay(hit.mFraction);
    const Vec3 normal = body.GetWorldSpaceSurfaceNormal(hit.mSubShapeID2, point);

    out_hit->body_id = hit.mBodyID.GetIndexAndSequenceNumber();
    out_hit->user_data = body.GetUserData();
    from_rvec3(point, out_hit->position);
    from_vec3(normal, out_hit->normal);
    out_hit->distance = hit.mFraction * max_distance;
    (void)source_layer;
    return true;
}
