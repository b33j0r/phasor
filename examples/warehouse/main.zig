const Player = struct {};
const PlayerCamera = struct {};
const FpsPhysics = physics.FpsPhysicsModule(Player);
const FpsController = FpsPhysics.FpsController;

const UvSamplingMode = union(enum) {
    FollowUv,
    TileByScale: struct {
        u_per_unit: f32 = 1.0,
        v_per_unit: f32 = 1.0,
    },
};

const BoxFaceMask = struct {
    front: bool = true,
    back: bool = true,
    left: bool = true,
    right: bool = true,
    top: bool = true,
    bottom: bool = true,
};

const App = struct {
    pub const options = platform.Options{
        .window = .{
            .title = "Phasor - Warehouse",
            .width = 1440,
            .height = 900,
        },
    };

    pub fn configure(app: *ecs.App) !void {
        try platform.installDefaultModules(app);
        try app.installModule(modules.SkyModule);
        try app.installModule(physics.PhysicsModule{
            .config = .{
                .backend = .Jolt,
                .fixed_dt = 1.0 / 60.0,
                .max_substeps = 8,
                .gravity = .{ .x = 0.0, .y = -18.0, .z = 0.0 },
            },
        });
        try app.installModule(FpsPhysics{});
        try app.installModule(physics.FpsKeyBindingModule{});
        try app.installModule(modules.AssetsModule(Assets));
        try app.installModule(modules.MetricsModuleLayered(render.Layer(1000)){
            .font_size = 24.0,
            .text_color = Color.WHITE,
        });

        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("Update", updateMouseCaptureToggle);
        try app.addSystemTo("Update", updatePlayerCamera);
    }
};

pub const main = platform.main(App);

fn setupScene(
    commands: *ecs.Commands,
    build_ctx: ResMut(render.BuildContext),
    res_scene_assets: ResMut(Assets),
    core_shaders: ResMut(render.CoreShaders),
) !void {
    const render_build = build_ctx.deref();
    const scene_assets = res_scene_assets.deref();
    try build_ctx.ptr.ensureCoreColorPos3Color4Shader(&core_shaders.ptr.color_pos3_color4);

    if (!scene_assets.floor_tex.material_handle.isValid()) return error.FloorTextureMissing;
    if (!scene_assets.wall_tex.material_handle.isValid()) return error.WallTextureMissing;
    if (!scene_assets.catwalk_tex.material_handle.isValid()) return error.CatwalkTextureMissing;
    if (!scene_assets.crate_tex.material_handle.isValid()) return error.CrateTextureMissing;
    if (!scene_assets.panorama_tex.material_handle.isValid()) return error.PanoramaTextureMissing;
    if (scene_assets.music.bytesSlice() == null) return error.MusicMissing;
    if (!core_shaders.ptr.color_pos3_color4.isValid()) return error.CoreColorShaderMissing;

    try commands.insertResource(ClearColor{ .color = Color.rgb(13, 15, 20) });
    try commands.insertResource(MouseCapture{ .enabled = true });

    const cyl_mesh = try createCylinderMesh(commands.allocator, render_build, 0.45, 1.2, 18);
    const sphere_mesh = try createSphereMesh(commands.allocator, render_build, 0.55, 10, 18);

    try spawnWarehouseShell(commands, render_build, scene_assets);
    try spawnWarehouseProps(commands, render_build, scene_assets);
    try spawnWarehousePrimitives(commands, cyl_mesh, sphere_mesh, core_shaders.ptr.color_pos3_color4);

    _ = try commands.createEntity(.{
        Transform{
            .translation = .{ .x = 0.0, .y = 28.0, .z = 0.0 },
        },
        modules.SkyModule.PanoramaSky{
            .material = scene_assets.panorama_tex.material,
            .size = 220.0,
            .follow_camera = true,
            .face_segments = 48,
        },
        render.Layer(-1){},
    });

    _ = try commands.createEntity(.{
        audio.SoundPlayer{
            .source = &scene_assets.music,
            .volume = 0.55,
            .one_shot = false,
            .loop = true,
        },
    });

    const controller = FpsController{ .eye_offset_y = 0.5 };

    const player_spawn = Vec3{ .x = 0.0, .y = 0.9, .z = 10.5 };

    _ = try commands.createEntity(.{
        Player{},
        controller,
        Transform{
            .translation = player_spawn,
        },
        physics.Character{},
        physics.Collider{
            .shape = .{ .Capsule = .{
                .radius = controller.radius,
                .half_height = FpsPhysics.capsuleHalfHeight(controller),
            } },
            .collision = .{
                .layer = 1,
                .mask = 1 << 0,
            },
        },
        physics.CharacterVelocity{},
        physics.CharacterState{},
    });

    _ = try commands.createEntity(.{
        PlayerCamera{},
        Transform{
            .translation = player_spawn.add(FpsPhysics.cameraOffset(controller)),
        },
        Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.0,
            .near = 0.2,
            .far = 120.0,
        } },
        CameraLayer(-1){},
        CameraLayer(0){},
    });

    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(1000){},
    });
}

fn spawnWarehouseShell(
    commands: *ecs.Commands,
    build_ctx: *render.BuildContext,
    scene_assets: *const Assets,
) !void {
    const shell_half = Vec3{ .x = 20.0, .y = 6.0, .z = 16.0 };
    const floor_w = shell_half.x * 2.0;
    const floor_d = shell_half.z * 2.0;
    const wall_w = shell_half.x * 2.0;
    const wall_h = shell_half.y * 2.0;
    const side_w = shell_half.z * 2.0;
    const side_h = shell_half.y * 2.0;
    const tiling = UvSamplingMode{ .TileByScale = .{ .u_per_unit = 0.28, .v_per_unit = 0.28 } };

    try spawnTexturedQuad(commands, build_ctx, scene_assets.floor_tex.material, .{
        .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .rotation = quatFromEuler(-std.math.pi * 0.5, 0.0, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, floor_w, floor_d, tiling);
    try addStaticCollider(commands, .{ .x = 0.0, .y = -0.5, .z = 0.0 }, .{ .x = shell_half.x, .y = 0.5, .z = shell_half.z });

    try spawnTexturedQuad(commands, build_ctx, scene_assets.wall_tex.material, .{
        .position = .{ .x = 0.0, .y = shell_half.y * 2.0, .z = 0.0 },
        .rotation = quatFromEuler(std.math.pi * 0.5, 0.0, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, floor_w, floor_d, tiling);

    try spawnTexturedQuad(commands, build_ctx, scene_assets.wall_tex.material, .{
        .position = .{ .x = 0.0, .y = shell_half.y, .z = -shell_half.z },
        .rotation = quatFromEuler(0.0, 0.0, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, wall_w, wall_h, tiling);
    try addStaticCollider(commands, .{ .x = 0.0, .y = shell_half.y, .z = -shell_half.z - 0.5 }, .{ .x = shell_half.x, .y = shell_half.y, .z = 0.5 });

    try spawnTexturedQuad(commands, build_ctx, scene_assets.wall_tex.material, .{
        .position = .{ .x = -shell_half.x, .y = shell_half.y, .z = 0.0 },
        .rotation = quatFromEuler(0.0, std.math.pi * 0.5, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, side_w, side_h, tiling);
    try addStaticCollider(commands, .{ .x = -shell_half.x - 0.5, .y = shell_half.y, .z = 0.0 }, .{ .x = 0.5, .y = shell_half.y, .z = shell_half.z });

    try spawnTexturedQuad(commands, build_ctx, scene_assets.wall_tex.material, .{
        .position = .{ .x = shell_half.x, .y = shell_half.y, .z = 0.0 },
        .rotation = quatFromEuler(0.0, -std.math.pi * 0.5, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, side_w, side_h, tiling);
    try addStaticCollider(commands, .{ .x = shell_half.x + 0.5, .y = shell_half.y, .z = 0.0 }, .{ .x = 0.5, .y = shell_half.y, .z = shell_half.z });

    const doorway_half_w = 4.0;
    const doorway_h = 3.4;
    const front_wall_y = shell_half.y;
    const front_z = shell_half.z;
    try spawnTexturedQuad(commands, build_ctx, scene_assets.wall_tex.material, .{
        .position = .{ .x = -(shell_half.x + doorway_half_w) * 0.5, .y = front_wall_y, .z = front_z },
        .rotation = quatFromEuler(0.0, std.math.pi, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, shell_half.x - doorway_half_w, wall_h, tiling);
    try spawnTexturedQuad(commands, build_ctx, scene_assets.wall_tex.material, .{
        .position = .{ .x = (shell_half.x + doorway_half_w) * 0.5, .y = front_wall_y, .z = front_z },
        .rotation = quatFromEuler(0.0, std.math.pi, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, shell_half.x - doorway_half_w, wall_h, tiling);
    try spawnTexturedQuad(commands, build_ctx, scene_assets.wall_tex.material, .{
        .position = .{ .x = 0.0, .y = shell_half.y + (shell_half.y - doorway_h) * 0.5 + doorway_h, .z = front_z },
        .rotation = quatFromEuler(0.0, std.math.pi, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, doorway_half_w * 2.0, shell_half.y * 2.0 - doorway_h, tiling);

    try addStaticCollider(commands, .{ .x = -(shell_half.x + doorway_half_w) * 0.5, .y = shell_half.y, .z = front_z + 0.5 }, .{ .x = (shell_half.x - doorway_half_w) * 0.5, .y = shell_half.y, .z = 0.5 });
    try addStaticCollider(commands, .{ .x = (shell_half.x + doorway_half_w) * 0.5, .y = shell_half.y, .z = front_z + 0.5 }, .{ .x = (shell_half.x - doorway_half_w) * 0.5, .y = shell_half.y, .z = 0.5 });
    try addStaticCollider(commands, .{ .x = 0.0, .y = doorway_h + (shell_half.y * 2.0 - doorway_h) * 0.5, .z = front_z + 0.5 }, .{ .x = doorway_half_w, .y = (shell_half.y * 2.0 - doorway_h) * 0.5, .z = 0.5 });
}

fn spawnWarehouseProps(
    commands: *ecs.Commands,
    build_ctx: *render.BuildContext,
    scene_assets: *const Assets,
) !void {
    const crate_material = scene_assets.crate_tex.material;
    const catwalk_material = scene_assets.catwalk_tex.material;
    const crate_y_bias: f32 = 0.01;

    try spawnTexturedBox(
        commands,
        build_ctx,
        crate_material,
        .{ .x = -8.0, .y = 1.5 + crate_y_bias, .z = -6.0 },
        .{ .x = 0.75, .y = 1.5, .z = 0.75 },
        .FollowUv,
        BoxFaceMask{ .bottom = false },
    );
    try spawnTexturedBox(
        commands,
        build_ctx,
        crate_material,
        .{ .x = 5.5, .y = 0.75 + crate_y_bias, .z = -4.0 },
        .{ .x = 0.75, .y = 0.75, .z = 0.75 },
        .FollowUv,
        BoxFaceMask{ .bottom = false },
    );
    try spawnTexturedBox(
        commands,
        build_ctx,
        crate_material,
        .{ .x = 7.2, .y = 0.75 + crate_y_bias, .z = -3.2 },
        .{ .x = 0.75, .y = 0.75, .z = 0.75 },
        .FollowUv,
        BoxFaceMask{ .bottom = false },
    );
    try spawnTexturedBox(
        commands,
        build_ctx,
        crate_material,
        .{ .x = 9.0, .y = 0.75 + crate_y_bias, .z = -2.3 },
        .{ .x = 0.75, .y = 0.75, .z = 0.75 },
        .FollowUv,
        BoxFaceMask{ .bottom = false },
    );

    const ramp_base = Vec3{ .x = -11.0, .y = 0.0, .z = 3.5 };
    const step_h: f32 = 0.45;
    const step_d: f32 = 1.2;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const ix: f32 = @floatFromInt(i);
        const center = Vec3{
            .x = ramp_base.x + ix * step_d,
            .y = step_h * 0.5 + step_h * ix + 0.002 * ix,
            .z = ramp_base.z,
        };
        const half = Vec3{ .x = step_d * 0.5, .y = step_h * 0.5, .z = 2.2 };
        try spawnTexturedBox(
            commands,
            build_ctx,
            catwalk_material,
            center,
            half,
            UvSamplingMode{ .TileByScale = .{ .u_per_unit = 0.7, .v_per_unit = 0.7 } },
            BoxFaceMask{ .bottom = false },
        );
    }

    try spawnTexturedBox(
        commands,
        build_ctx,
        catwalk_material,
        .{ .x = -1.6 + 3.0, .y = 3.6, .z = 3.5 },
        .{ .x = 4.2, .y = 0.35, .z = 3.0 },
        UvSamplingMode{ .TileByScale = .{ .u_per_unit = 0.6, .v_per_unit = 0.6 } },
        .{},
    );
    // try spawnTexturedBox(
    //     commands,
    //     mesh_library,
    //     renderer_state,
    //     catwalk_material,
    //     .{ .x = 0.8, .y = 1.5, .z = 8.8 },
    //     .{ .x = 2.8, .y = 0.25, .z = 1.2 },
    //     UvSamplingMode{ .TileByScale = .{ .u_per_unit = 0.6, .v_per_unit = 0.6 } },
    //     .{},
    // );
}

fn spawnWarehousePrimitives(
    commands: *ecs.Commands,
    cylinder_mesh: MeshHandle,
    sphere_mesh: MeshHandle,
    color_shader: render.ShaderHandle,
) !void {
    const shader_material = render.Material.withShader(color_shader);

    _ = try commands.createEntity(.{
        Transform{
            .translation = .{ .x = 3.5, .y = 0.6, .z = 5.0 },
        },
        MeshInstance{
            .mesh_handle = cylinder_mesh,
            .material = shader_material,
            .color = Color.rgb(33, 140, 191),
        },
        render.Layer(0){},
    });
    try addStaticCollider(commands, .{ .x = 3.5, .y = 0.6, .z = 5.0 }, .{ .x = 0.5, .y = 0.6, .z = 0.5 });

    _ = try commands.createEntity(.{
        Transform{
            .translation = .{ .x = 4.9, .y = 0.6, .z = 5.4 },
        },
        MeshInstance{
            .mesh_handle = cylinder_mesh,
            .material = shader_material,
            .color = Color.rgb(28, 127, 178),
        },
        render.Layer(0){},
    });
    try addStaticCollider(commands, .{ .x = 4.9, .y = 0.6, .z = 5.4 }, .{ .x = 0.5, .y = 0.6, .z = 0.5 });

    _ = try commands.createEntity(.{
        Transform{
            .translation = .{ .x = -4.6, .y = 0.55, .z = 4.4 },
        },
        MeshInstance{
            .mesh_handle = sphere_mesh,
            .material = shader_material,
            .color = Color.rgb(178, 178, 51),
        },
        render.Layer(0){},
    });
    try addStaticCollider(commands, .{ .x = -4.6, .y = 0.55, .z = 4.4 }, .{ .x = 0.55, .y = 0.55, .z = 0.55 });
}

fn updateMouseCaptureToggle(
    keyboard_opt: ResOpt(Keyboard),
    capture_opt: ResOpt(MouseCapture),
    commands: *ecs.Commands,
) !void {
    const keyboard = keyboard_opt.ptr orelse return;
    var capture = if (capture_opt.ptr) |existing| existing.* else MouseCapture{};

    if (keyboard.isKeyPressed(.escape)) {
        capture.enabled = false;
        try commands.insertResource(capture);
        return;
    }
    if (keyboard.isKeyPressed(.enter)) {
        capture.enabled = true;
        try commands.insertResource(capture);
    }
}

fn updatePlayerCamera(
    players: ecs.system_params.Query(.{ Transform, FpsController, Player }),
    cameras: ecs.system_params.Query(.{ Transform, PlayerCamera }),
) void {
    var player_transform: ?Transform = null;
    var player_controller: ?FpsController = null;

    var pit = players.iterator();
    while (pit.next()) |row| {
        player_transform = row.get(Transform).?.*;
        player_controller = row.get(FpsController).?.*;
        break;
    }

    if (player_transform == null or player_controller == null) return;
    const controller = player_controller.?;
    const camera_rotation = quatFromEuler(controller.pitch, controller.yaw, 0.0);

    var cit = cameras.iterator();
    while (cit.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.translation = player_transform.?.translation.add(FpsPhysics.cameraOffset(controller));
        transform.rotation = camera_rotation;
    }
}

fn spawnTexturedBox(
    commands: *ecs.Commands,
    build_ctx: *render.BuildContext,
    material: Material,
    center: Vec3,
    half: Vec3,
    uv_mode: UvSamplingMode,
    faces: BoxFaceMask,
) !void {
    const face_x = half.x * 2.0;
    const face_y = half.y * 2.0;
    const face_z = half.z * 2.0;

    if (faces.front) {
        try spawnTexturedQuad(commands, build_ctx, material, .{
            .position = center.add(.{ .x = 0.0, .y = 0.0, .z = half.z }),
            .rotation = quatFromEuler(0.0, 0.0, 0.0),
            .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        }, face_x, face_y, uv_mode);
    }
    if (faces.back) {
        try spawnTexturedQuad(commands, build_ctx, material, .{
            .position = center.add(.{ .x = 0.0, .y = 0.0, .z = -half.z }),
            .rotation = quatFromEuler(0.0, std.math.pi, 0.0),
            .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        }, face_x, face_y, uv_mode);
    }
    if (faces.right) {
        try spawnTexturedQuad(commands, build_ctx, material, .{
            .position = center.add(.{ .x = half.x, .y = 0.0, .z = 0.0 }),
            .rotation = quatFromEuler(0.0, -std.math.pi * 0.5, 0.0),
            .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        }, face_z, face_y, uv_mode);
    }
    if (faces.left) {
        try spawnTexturedQuad(commands, build_ctx, material, .{
            .position = center.add(.{ .x = -half.x, .y = 0.0, .z = 0.0 }),
            .rotation = quatFromEuler(0.0, std.math.pi * 0.5, 0.0),
            .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        }, face_z, face_y, uv_mode);
    }
    if (faces.top) {
        try spawnTexturedQuad(commands, build_ctx, material, .{
            .position = center.add(.{ .x = 0.0, .y = half.y, .z = 0.0 }),
            .rotation = quatFromEuler(-std.math.pi * 0.5, 0.0, 0.0),
            .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        }, face_x, face_z, uv_mode);
    }
    if (faces.bottom) {
        try spawnTexturedQuad(commands, build_ctx, material, .{
            .position = center.add(.{ .x = 0.0, .y = -half.y, .z = 0.0 }),
            .rotation = quatFromEuler(std.math.pi * 0.5, 0.0, 0.0),
            .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        }, face_x, face_z, uv_mode);
    }

    try addStaticCollider(commands, center, half);
}

const QuadPose = struct {
    position: Vec3,
    rotation: Quat,
    scale: Vec3,
};

const UvRect = struct {
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
};

fn spawnTexturedQuad(
    commands: *ecs.Commands,
    build_ctx: *render.BuildContext,
    material: Material,
    pose: QuadPose,
    width: f32,
    height: f32,
    uv_mode: UvSamplingMode,
) !void {
    const mesh = try createQuadMesh(commands.allocator, build_ctx, width, height, uv_mode);
    _ = try commands.createEntity(.{
        Transform{
            .translation = pose.position,
            .rotation = pose.rotation,
            .scale = pose.scale,
        },
        MeshInstance{
            .mesh_handle = mesh,
            .material = material,
            .color = Color.WHITE,
        },
        render.Layer(0){},
    });
}

fn spawnTexturedQuadUvRect(
    commands: *ecs.Commands,
    build_ctx: *render.BuildContext,
    material: Material,
    pose: QuadPose,
    width: f32,
    height: f32,
    uv_rect: UvRect,
) !void {
    try spawnTexturedQuadUvRectInLayer(0, commands, build_ctx, material, pose, width, height, uv_rect);
}

fn spawnTexturedQuadUvRectInLayer(
    comptime layer: i32,
    commands: *ecs.Commands,
    build_ctx: *render.BuildContext,
    material: Material,
    pose: QuadPose,
    width: f32,
    height: f32,
    uv_rect: UvRect,
) !void {
    const mesh = try createQuadMeshUvRect(commands.allocator, build_ctx, width, height, uv_rect);
    _ = try commands.createEntity(.{
        Transform{
            .translation = pose.position,
            .rotation = pose.rotation,
            .scale = pose.scale,
        },
        MeshInstance{
            .mesh_handle = mesh,
            .material = material,
            .color = Color.WHITE,
        },
        render.Layer(layer){},
    });
}

fn addStaticCollider(commands: *ecs.Commands, center: Vec3, half: Vec3) !void {
    _ = try commands.createEntity(.{
        Transform{
            .translation = center,
        },
        physics.Body{ .kind = .Static },
        physics.Collider{
            .shape = .{ .Box = .{ .half_extents = half } },
            .material = .{ .friction = 0.85, .restitution = 0.0 },
            .collision = .{
                .layer = 0,
                .mask = 0xffff_ffff,
            },
        },
    });
}

fn quatFromEuler(pitch: f32, yaw: f32, roll: f32) Quat {
    const qx = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, pitch);
    const qy = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, yaw);
    const qz = Quat.fromAxisAngle(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, roll);
    return qy.mul(qx).mul(qz).normalize();
}

fn createQuadMesh(
    allocator: std.mem.Allocator,
    build_ctx: *render.BuildContext,
    width: f32,
    height: f32,
    uv_mode: UvSamplingMode,
) !MeshHandle {
    const half_w = width * 0.5;
    const half_h = height * 0.5;

    switch (uv_mode) {
        .FollowUv => {
            const vertices = [_]render.VertexUv{
                .{ .position = .{ -half_w, -half_h }, .uv = .{ 0.0, 1.0 } },
                .{ .position = .{ half_w, -half_h }, .uv = .{ 1.0, 1.0 } },
                .{ .position = .{ half_w, half_h }, .uv = .{ 1.0, 0.0 } },
                .{ .position = .{ -half_w, half_h }, .uv = .{ 0.0, 0.0 } },
            };
            const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };
            return build_ctx.addMesh(vertices[0..], indices[0..]);
        },
        .TileByScale => |cfg| {
            const u_per_unit = @max(0.001, cfg.u_per_unit);
            const v_per_unit = @max(0.001, cfg.v_per_unit);
            const tiles_u_f = @max(1.0, width * u_per_unit);
            const tiles_v_f = @max(1.0, height * v_per_unit);
            const tiles_u: u32 = @intFromFloat(@ceil(tiles_u_f));
            const tiles_v: u32 = @intFromFloat(@ceil(tiles_v_f));

            const tile_w = width / @as(f32, @floatFromInt(tiles_u));
            const tile_h = height / @as(f32, @floatFromInt(tiles_v));

            const quad_count: usize = @intCast(tiles_u * tiles_v);
            const vertex_count = quad_count * 4;
            const index_count = quad_count * 6;

            if (vertex_count > std.math.maxInt(u16)) return error.TooManyVertices;

            var vertices = try allocator.alloc(render.VertexUv, vertex_count);
            defer allocator.free(vertices);
            var indices = try allocator.alloc(u16, index_count);
            defer allocator.free(indices);

            var q: usize = 0;
            var y: u32 = 0;
            while (y < tiles_v) : (y += 1) {
                var x: u32 = 0;
                while (x < tiles_u) : (x += 1) {
                    const x0 = -half_w + @as(f32, @floatFromInt(x)) * tile_w;
                    const x1 = x0 + tile_w;
                    const y0 = -half_h + @as(f32, @floatFromInt(y)) * tile_h;
                    const y1 = y0 + tile_h;

                    const vi = q * 4;
                    vertices[vi + 0] = .{ .position = .{ x0, y0 }, .uv = .{ 0.0, 1.0 } };
                    vertices[vi + 1] = .{ .position = .{ x1, y0 }, .uv = .{ 1.0, 1.0 } };
                    vertices[vi + 2] = .{ .position = .{ x1, y1 }, .uv = .{ 1.0, 0.0 } };
                    vertices[vi + 3] = .{ .position = .{ x0, y1 }, .uv = .{ 0.0, 0.0 } };

                    const ii = q * 6;
                    const base: u16 = @intCast(vi);
                    indices[ii + 0] = base + 0;
                    indices[ii + 1] = base + 1;
                    indices[ii + 2] = base + 2;
                    indices[ii + 3] = base + 2;
                    indices[ii + 4] = base + 3;
                    indices[ii + 5] = base + 0;

                    q += 1;
                }
            }

            return build_ctx.addMesh(vertices, indices);
        },
    }
}

fn createQuadMeshUvRect(
    allocator: std.mem.Allocator,
    build_ctx: *render.BuildContext,
    width: f32,
    height: f32,
    uv: UvRect,
) !MeshHandle {
    _ = allocator;
    const half_w = width * 0.5;
    const half_h = height * 0.5;
    const vertices = [_]render.VertexUv{
        .{ .position = .{ -half_w, -half_h }, .uv = .{ uv.u0, uv.v1 } },
        .{ .position = .{ half_w, -half_h }, .uv = .{ uv.u1, uv.v1 } },
        .{ .position = .{ half_w, half_h }, .uv = .{ uv.u1, uv.v0 } },
        .{ .position = .{ -half_w, half_h }, .uv = .{ uv.u0, uv.v0 } },
    };
    const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };
    return build_ctx.addMesh(vertices[0..], indices[0..]);
}

fn createCylinderMesh(
    allocator: std.mem.Allocator,
    build_ctx: *render.BuildContext,
    radius: f32,
    height: f32,
    segments: u32,
) !MeshHandle {
    if (segments < 3) return error.InvalidSegments;

    var vertices: std.ArrayListUnmanaged(render.VertexPos3Color) = .empty;
    defer vertices.deinit(allocator);

    var indices: std.ArrayListUnmanaged(u16) = .empty;
    defer indices.deinit(allocator);

    const half_h = height * 0.5;
    const white = [4]f32{ 1.0, 1.0, 1.0, 1.0 };

    var i: u32 = 0;
    while (i < segments) : (i += 1) {
        const t = 2.0 * std.math.pi * (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments)));
        const x = @cos(t) * radius;
        const z = @sin(t) * radius;
        try vertices.append(allocator, .{ .position = .{ x, -half_h, z }, .color = white });
        try vertices.append(allocator, .{ .position = .{ x, half_h, z }, .color = white });
    }

    const top_center: u16 = @intCast(vertices.items.len);
    try vertices.append(allocator, .{ .position = .{ 0.0, half_h, 0.0 }, .color = white });
    const bottom_center: u16 = @intCast(vertices.items.len);
    try vertices.append(allocator, .{ .position = .{ 0.0, -half_h, 0.0 }, .color = white });

    i = 0;
    while (i < segments) : (i += 1) {
        const next = (i + 1) % segments;

        const b0: u16 = @intCast(i * 2);
        const t0: u16 = b0 + 1;
        const b1: u16 = @intCast(next * 2);
        const t1: u16 = b1 + 1;

        try indices.append(allocator, b0);
        try indices.append(allocator, t0);
        try indices.append(allocator, t1);
        try indices.append(allocator, b0);
        try indices.append(allocator, t1);
        try indices.append(allocator, b1);

        try indices.append(allocator, top_center);
        try indices.append(allocator, t1);
        try indices.append(allocator, t0);

        try indices.append(allocator, bottom_center);
        try indices.append(allocator, b0);
        try indices.append(allocator, b1);
    }

    return build_ctx.addMeshPos3Color(vertices.items, indices.items);
}

fn createSphereMesh(
    allocator: std.mem.Allocator,
    build_ctx: *render.BuildContext,
    radius: f32,
    lat_segments: u32,
    lon_segments: u32,
) !MeshHandle {
    if (lat_segments < 2 or lon_segments < 3) return error.InvalidSegments;

    var vertices: std.ArrayListUnmanaged(render.VertexPos3Color) = .empty;
    defer vertices.deinit(allocator);

    var indices: std.ArrayListUnmanaged(u16) = .empty;
    defer indices.deinit(allocator);

    const white = [4]f32{ 1.0, 1.0, 1.0, 1.0 };

    var lat: u32 = 0;
    while (lat <= lat_segments) : (lat += 1) {
        const v = @as(f32, @floatFromInt(lat)) / @as(f32, @floatFromInt(lat_segments));
        const theta = v * std.math.pi;
        const y = @cos(theta) * radius;
        const ring_r = @sin(theta) * radius;

        var lon: u32 = 0;
        while (lon <= lon_segments) : (lon += 1) {
            const u = @as(f32, @floatFromInt(lon)) / @as(f32, @floatFromInt(lon_segments));
            const phi = u * 2.0 * std.math.pi;
            const x = @cos(phi) * ring_r;
            const z = @sin(phi) * ring_r;
            try vertices.append(allocator, .{ .position = .{ x, y, z }, .color = white });
        }
    }

    const stride = lon_segments + 1;
    lat = 0;
    while (lat < lat_segments) : (lat += 1) {
        var lon: u32 = 0;
        while (lon < lon_segments) : (lon += 1) {
            const idx0: u16 = @intCast(lat * stride + lon);
            const idx1: u16 = idx0 + 1;
            const idx2: u16 = @intCast((lat + 1) * stride + lon);
            const idx3: u16 = idx2 + 1;

            try indices.append(allocator, idx0);
            try indices.append(allocator, idx2);
            try indices.append(allocator, idx3);

            try indices.append(allocator, idx0);
            try indices.append(allocator, idx3);
            try indices.append(allocator, idx1);
        }
    }

    return build_ctx.addMeshPos3Color(vertices.items, indices.items);
}

const Assets = struct {
    floor_tex: assets.Texture = assets.Texture.embedded(@embedFile("assets/textures/Concrete011_Color.png")).asOpaque().tiledLinear(),
    wall_tex: assets.Texture = assets.Texture.embedded(@embedFile("assets/textures/MetalPlates001_Color.png")).asOpaque(),
    catwalk_tex: assets.Texture = assets.Texture.embedded(@embedFile("assets/textures/MetalWalkway001_Color.png")).asOpaque().tiledLinear(),
    crate_tex: assets.Texture = assets.Texture.embedded(@embedFile("assets/textures/Wood049_Color.png")).asOpaque(),
    panorama_tex: assets.Texture = assets.Texture.embedded(@embedFile("assets/textures/panorama_autumn_field_puresky.jpg")).asBlended().equirectangularLinear(),
    music: assets.Sound = .{
        .data = @embedFile("assets/music/Programmed it on my own.mp3"),
    },
};

// Imports
const std = @import("std");
const phasor = @import("phasor");

const ecs = phasor.ecs;
const modules = phasor.modules;
const physics = @import("phasor_physics");
const render = phasor.renderer;
const common = phasor.common;
const platform = phasor.platform;
const assets = phasor.assets;
const audio = phasor.audio;

const ResOpt = ecs.system_params.ResOpt;
const ResMut = ecs.system_params.ResMut;

const Keyboard = modules.InputModule.Keyboard;
const MouseCapture = modules.InputModule.MouseCapture;

const Vec3 = common.Vec3;
const Quat = common.Quat;
const Color = common.Color;
const Transform = common.Transform;
const Camera3d = common.Camera3d;
const ClearColor = common.ClearColor;

const MeshHandle = render.MeshHandle;
const Material = render.Material;
const MeshInstance = render.MeshInstance;
const CameraLayer = render.CameraLayer;
