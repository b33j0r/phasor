#ifndef PHASOR_PHYSICS_JOLT_C_H
#define PHASOR_PHYSICS_JOLT_C_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct pj_world pj_world;

typedef enum pj_motion_type {
    PJ_MOTION_STATIC = 0,
    PJ_MOTION_DYNAMIC = 1,
    PJ_MOTION_KINEMATIC = 2,
} pj_motion_type;

typedef enum pj_shape_kind {
    PJ_SHAPE_SPHERE = 0,
    PJ_SHAPE_CAPSULE = 1,
    PJ_SHAPE_BOX = 2,
    PJ_SHAPE_CYLINDER = 3,
    PJ_SHAPE_TRIANGLE_MESH = 4,
    PJ_SHAPE_HEIGHT_FIELD = 5,
} pj_shape_kind;

typedef struct pj_world_config {
    float gravity[3];
    uint32_t max_bodies;
    uint32_t max_body_pairs;
    uint32_t max_contact_constraints;
    uint32_t temp_allocator_bytes;
    uint32_t max_jobs;
    uint32_t max_barriers;
} pj_world_config;

typedef struct pj_body_desc {
    uint64_t user_data;
    pj_motion_type motion_type;
    pj_shape_kind shape_kind;
    uint32_t object_layer;
    uint32_t collision_mask;
    uint32_t allowed_dofs_mask;
    bool is_sensor;
    bool allow_sleep;
    bool use_ccd;
    bool collide_kinematic_vs_non_dynamic;
    bool use_enhanced_internal_edge_removal;
    bool override_mass;
    float friction;
    float restitution;
    float linear_damping;
    float angular_damping;
    float gravity_scale;
    float density;
    float mass;
    float position[3];
    float rotation[4];
    float linear_velocity[3];
    float angular_velocity[3];
    float half_extents[3];
    float radius;
    float half_height;
    float heightfield_offset[3];
    float heightfield_scale[3];
    uint32_t heightfield_sample_count;
} pj_body_desc;

typedef struct pj_body_state {
    float position[3];
    float rotation[4];
    float linear_velocity[3];
    float angular_velocity[3];
    uint64_t user_data;
} pj_body_state;

typedef struct pj_raycast_hit {
    bool hit;
    uint32_t body_id;
    uint64_t user_data;
    float position[3];
    float normal[3];
    float distance;
} pj_raycast_hit;

typedef struct pj_shapecast_hit {
    bool hit;
    uint32_t body_id;
    uint64_t user_data;
    float position[3];
    float normal[3];
    float fraction;
} pj_shapecast_hit;

bool pj_world_create(const pj_world_config *config, pj_world **out_world);
void pj_world_destroy(pj_world *world);
bool pj_world_step(pj_world *world, float dt, int collision_steps, float *out_step_ms, uint32_t *out_body_count, uint32_t *out_active_body_count);

bool pj_body_create(
    pj_world *world,
    const pj_body_desc *desc,
    const float *mesh_vertices_xyz,
    uint32_t mesh_vertex_count,
    const uint32_t *mesh_indices,
    uint32_t mesh_index_count,
    const float *height_samples,
    uint32_t height_sample_count,
    uint32_t *out_body_id
);
bool pj_body_remove_destroy(pj_world *world, uint32_t body_id);
bool pj_body_set_transform(pj_world *world, uint32_t body_id, const float position[3], const float rotation[4], bool activate);
bool pj_body_set_velocities(pj_world *world, uint32_t body_id, const float linear_velocity[3], const float angular_velocity[3]);
bool pj_body_move_kinematic(pj_world *world, uint32_t body_id, const float position[3], const float rotation[4], float dt);
bool pj_body_get_state(pj_world *world, uint32_t body_id, pj_body_state *out_state);
bool pj_world_cast_ray(
    pj_world *world,
    const float origin[3],
    const float direction[3],
    float max_distance,
    uint32_t source_layer,
    uint32_t collision_mask,
    pj_raycast_hit *out_hit
);
bool pj_world_cast_shape(
    pj_world *world,
    const pj_body_desc *desc,
    const float translation[3],
    uint32_t source_layer,
    uint32_t collision_mask,
    pj_shapecast_hit *out_hit
);

#ifdef __cplusplus
}
#endif

#endif
