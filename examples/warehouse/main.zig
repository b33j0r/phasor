const Player = struct {};

const FpsController = struct {
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    move_speed: f32 = 8.0,
    look_sensitivity: f32 = 0.003,
    jump_speed: f32 = 6.5,
    gravity: f32 = -18.0,
    velocity_y: f32 = 0.0,
    move_x: f32 = 0.0,
    move_z: f32 = 0.0,
    radius: f32 = 0.35,
    height: f32 = 1.8,
    grounded: bool = false,
    coyote_time: f32 = 0.1,
    coyote_timer: f32 = 0.0,
    jump_buffer_time: f32 = 0.12,
    jump_buffer_timer: f32 = 0.0,
};

const StaticAabb = struct {
    min: Vec3,
    max: Vec3,
};

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
            .title = "Phasor Lite - Warehouse",
            .width = 1440,
            .height = 900,
        },
    };

    pub fn configure(app: *ecs.App) !void {
        try app.installModule(modules.TimeModule);
        try app.installModule(modules.InputModule);
        try app.installModule(modules.RenderModule);
        try app.installModule(modules.AudioModule);
        try app.installModule(modules.SkyModule);
        try app.installModule(modules.AssetsModule(Assets));
        try app.installModule(modules.MetricsModuleLayered(render.Layer(1000)){
            .font_size = 24.0,
            .text_color = Color.WHITE,
        });

        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("Update", updateMouseCaptureToggle);
        try app.addSystemTo("Update", updateFpsControllerIntent);
        try app.addSystemTo("Update", movePlayerAndCollide);
    }
};

pub const main = platform.main(App);

fn setupScene(commands: *ecs.Commands, res_state: ResMut(RenderState), res_mesh_library: ResMut(MeshLibrary), res_scene_assets: ResMut(Assets)) !void {
    const state = res_state.deref();
    const scene_assets = res_scene_assets.deref();
    const mesh_library = res_mesh_library.deref();

    if (!scene_assets.floor_tex.material_handle.isValid()) return error.FloorTextureMissing;
    if (!scene_assets.wall_tex.material_handle.isValid()) return error.WallTextureMissing;
    if (!scene_assets.catwalk_tex.material_handle.isValid()) return error.CatwalkTextureMissing;
    if (!scene_assets.crate_tex.material_handle.isValid()) return error.CrateTextureMissing;
    if (!scene_assets.panorama_tex.material_handle.isValid()) return error.PanoramaTextureMissing;
    if (scene_assets.music.bytesSlice() == null) return error.MusicMissing;
    if (!scene_assets.color_shader.handle.isValid()) return error.ColorShaderMissing;

    try commands.insertResource(ClearColor{ .color = Color.rgb(13, 15, 20) });
    try commands.insertResource(MouseCapture{ .enabled = true });

    const cyl_mesh = try createCylinderMesh(commands.allocator, mesh_library, &state.renderer, 0.45, 1.2, 18);
    const sphere_mesh = try createSphereMesh(commands.allocator, mesh_library, &state.renderer, 0.55, 10, 18);

    try spawnWarehouseShell(commands, mesh_library, &state.renderer, scene_assets);
    try spawnWarehouseProps(commands, mesh_library, &state.renderer, scene_assets);
    try spawnWarehousePrimitives(commands, cyl_mesh, sphere_mesh, scene_assets);

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
    });

    _ = try commands.createEntity(.{
        audio.SoundPlayer{
            .source = &scene_assets.music,
            .volume = 0.55,
            .one_shot = false,
            .loop = true,
        },
    });

    _ = try commands.createEntity(.{
        Player{},
        FpsController{},
        Transform{
            .translation = .{ .x = 0.0, .y = 1.4, .z = 10.5 },
        },
        Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.0,
            .near = 0.2,
            .far = 120.0,
        } },
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
    mesh_library: *MeshLibrary,
    renderer_state: *render.Renderer,
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

    try spawnTexturedQuad(commands, mesh_library, renderer_state, scene_assets.floor_tex.material, .{
        .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .rotation = quatFromEuler(-std.math.pi * 0.5, 0.0, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, floor_w, floor_d, tiling);
    try addStaticCollider(commands, .{ .x = 0.0, .y = -0.5, .z = 0.0 }, .{ .x = shell_half.x, .y = 0.5, .z = shell_half.z });

    try spawnTexturedQuad(commands, mesh_library, renderer_state, scene_assets.wall_tex.material, .{
        .position = .{ .x = 0.0, .y = shell_half.y * 2.0, .z = 0.0 },
        .rotation = quatFromEuler(std.math.pi * 0.5, 0.0, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, floor_w, floor_d, tiling);

    try spawnTexturedQuad(commands, mesh_library, renderer_state, scene_assets.wall_tex.material, .{
        .position = .{ .x = 0.0, .y = shell_half.y, .z = -shell_half.z },
        .rotation = quatFromEuler(0.0, 0.0, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, wall_w, wall_h, tiling);
    try addStaticCollider(commands, .{ .x = 0.0, .y = shell_half.y, .z = -shell_half.z - 0.5 }, .{ .x = shell_half.x, .y = shell_half.y, .z = 0.5 });

    try spawnTexturedQuad(commands, mesh_library, renderer_state, scene_assets.wall_tex.material, .{
        .position = .{ .x = -shell_half.x, .y = shell_half.y, .z = 0.0 },
        .rotation = quatFromEuler(0.0, std.math.pi * 0.5, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, side_w, side_h, tiling);
    try addStaticCollider(commands, .{ .x = -shell_half.x - 0.5, .y = shell_half.y, .z = 0.0 }, .{ .x = 0.5, .y = shell_half.y, .z = shell_half.z });

    try spawnTexturedQuad(commands, mesh_library, renderer_state, scene_assets.wall_tex.material, .{
        .position = .{ .x = shell_half.x, .y = shell_half.y, .z = 0.0 },
        .rotation = quatFromEuler(0.0, -std.math.pi * 0.5, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, side_w, side_h, tiling);
    try addStaticCollider(commands, .{ .x = shell_half.x + 0.5, .y = shell_half.y, .z = 0.0 }, .{ .x = 0.5, .y = shell_half.y, .z = shell_half.z });

    const doorway_half_w = 4.0;
    const doorway_h = 3.4;
    const front_wall_y = shell_half.y;
    const front_z = shell_half.z;
    try spawnTexturedQuad(commands, mesh_library, renderer_state, scene_assets.wall_tex.material, .{
        .position = .{ .x = -(shell_half.x + doorway_half_w) * 0.5, .y = front_wall_y, .z = front_z },
        .rotation = quatFromEuler(0.0, std.math.pi, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, shell_half.x - doorway_half_w, wall_h, tiling);
    try spawnTexturedQuad(commands, mesh_library, renderer_state, scene_assets.wall_tex.material, .{
        .position = .{ .x = (shell_half.x + doorway_half_w) * 0.5, .y = front_wall_y, .z = front_z },
        .rotation = quatFromEuler(0.0, std.math.pi, 0.0),
        .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    }, shell_half.x - doorway_half_w, wall_h, tiling);
    try spawnTexturedQuad(commands, mesh_library, renderer_state, scene_assets.wall_tex.material, .{
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
    mesh_library: *MeshLibrary,
    renderer_state: *render.Renderer,
    scene_assets: *const Assets,
) !void {
    const crate_material = scene_assets.crate_tex.material;
    const catwalk_material = scene_assets.catwalk_tex.material;
    const crate_y_bias: f32 = 0.01;

    try spawnTexturedBox(
        commands,
        mesh_library,
        renderer_state,
        crate_material,
        .{ .x = -8.0, .y = 1.5 + crate_y_bias, .z = -6.0 },
        .{ .x = 0.75, .y = 1.5, .z = 0.75 },
        .FollowUv,
        BoxFaceMask{ .bottom = false },
    );
    try spawnTexturedBox(
        commands,
        mesh_library,
        renderer_state,
        crate_material,
        .{ .x = 5.5, .y = 0.75 + crate_y_bias, .z = -4.0 },
        .{ .x = 0.75, .y = 0.75, .z = 0.75 },
        .FollowUv,
        BoxFaceMask{ .bottom = false },
    );
    try spawnTexturedBox(
        commands,
        mesh_library,
        renderer_state,
        crate_material,
        .{ .x = 7.2, .y = 0.75 + crate_y_bias, .z = -3.2 },
        .{ .x = 0.75, .y = 0.75, .z = 0.75 },
        .FollowUv,
        BoxFaceMask{ .bottom = false },
    );
    try spawnTexturedBox(
        commands,
        mesh_library,
        renderer_state,
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
            mesh_library,
            renderer_state,
            catwalk_material,
            center,
            half,
            UvSamplingMode{ .TileByScale = .{ .u_per_unit = 0.7, .v_per_unit = 0.7 } },
            BoxFaceMask{ .bottom = false },
        );
    }

    try spawnTexturedBox(
        commands,
        mesh_library,
        renderer_state,
        catwalk_material,
        .{ .x = -1.6, .y = 4.6, .z = 3.5 },
        .{ .x = 4.2, .y = 0.35, .z = 3.0 },
        UvSamplingMode{ .TileByScale = .{ .u_per_unit = 0.6, .v_per_unit = 0.6 } },
        .{},
    );
    try spawnTexturedBox(
        commands,
        mesh_library,
        renderer_state,
        catwalk_material,
        .{ .x = 0.8, .y = 1.5, .z = 8.8 },
        .{ .x = 2.8, .y = 0.25, .z = 1.2 },
        UvSamplingMode{ .TileByScale = .{ .u_per_unit = 0.6, .v_per_unit = 0.6 } },
        .{},
    );
}

fn spawnWarehousePrimitives(
    commands: *ecs.Commands,
    cylinder_mesh: MeshHandle,
    sphere_mesh: MeshHandle,
    scene_assets: *const Assets,
) !void {
    const shader_material = render.Material.withShader(scene_assets.color_shader.handle);

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

fn updateFpsControllerIntent(
    dt: Res(DeltaTime),
    keyboard_opt: ResOpt(Keyboard),
    mouse_opt: ResOpt(Mouse),
    query: Query(.{ Transform, FpsController, Player }),
) void {
    const keyboard = keyboard_opt.ptr;
    const mouse = mouse_opt.ptr;
    const raw_step: f32 = @floatCast(dt.deref().seconds);
    const step: f32 = @min(raw_step, 1.0 / 30.0);
    if (!(step > 0.0)) return;

    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const controller = row.get(FpsController) orelse continue;

        var yaw_delta: f32 = 0.0;
        var pitch_delta: f32 = 0.0;

        if (mouse) |m| {
            yaw_delta -= m.delta_x * controller.look_sensitivity;
            pitch_delta -= m.delta_y * controller.look_sensitivity;
        }

        if (keyboard) |keys| {
            if (keys.isKeyDown(.left)) yaw_delta += 1.6 * step;
            if (keys.isKeyDown(.right)) yaw_delta -= 1.6 * step;
            if (keys.isKeyDown(.up)) pitch_delta += 1.2 * step;
            if (keys.isKeyDown(.down)) pitch_delta -= 1.2 * step;
        }

        controller.yaw += yaw_delta;
        controller.pitch = std.math.clamp(controller.pitch + pitch_delta, -1.45, 1.45);

        const yaw_rot = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, controller.yaw);
        const pitch_rot = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, controller.pitch);
        transform.rotation = yaw_rot.mul(pitch_rot).normalize();

        const forward_world = yaw_rot.rotateVec3(.{ .x = 0.0, .y = 0.0, .z = -1.0 });
        const right_world = yaw_rot.rotateVec3(.{ .x = 1.0, .y = 0.0, .z = 0.0 });

        var desired = Vec3{};
        if (keyboard) |keys| {
            if (keys.isKeyDown(.w)) desired = desired.add(forward_world);
            if (keys.isKeyDown(.s)) desired = desired.sub(forward_world);
            if (keys.isKeyDown(.d)) desired = desired.add(right_world);
            if (keys.isKeyDown(.a)) desired = desired.sub(right_world);
            if (keys.isKeyPressed(.space)) controller.jump_buffer_timer = controller.jump_buffer_time;
        }

        desired.y = 0.0;
        if (desired.length_squared() > 0.0001) {
            const normalized = desired.normalize();
            controller.move_x = normalized.x * controller.move_speed;
            controller.move_z = normalized.z * controller.move_speed;
        } else {
            controller.move_x = 0.0;
            controller.move_z = 0.0;
        }

        controller.velocity_y += controller.gravity * step;
        controller.jump_buffer_timer = @max(controller.jump_buffer_timer - step, 0.0);
        controller.coyote_timer = @max(controller.coyote_timer - step, 0.0);
    }
}

fn movePlayerAndCollide(
    dt: Res(DeltaTime),
    players: Query(.{ Transform, FpsController, Player }),
    colliders: Query(.{StaticAabb}),
) void {
    const raw_step: f32 = @floatCast(dt.deref().seconds);
    const step: f32 = @min(raw_step, 1.0 / 15.0);
    if (!(step > 0.0)) return;

    const skin: f32 = 0.001;

    var pit = players.iterator();
    while (pit.next()) |prow| {
        const transform = prow.get(Transform) orelse continue;
        const controller = prow.get(FpsController) orelse continue;

        const half = Vec3{
            .x = controller.radius,
            .y = controller.height * 0.5,
            .z = controller.radius,
        };

        var pos = transform.translation;
        var vel = Vec3{
            .x = controller.move_x,
            .y = controller.velocity_y,
            .z = controller.move_z,
        };

        if (controller.grounded) controller.coyote_timer = controller.coyote_time;

        if (controller.jump_buffer_timer > 0.0 and controller.coyote_timer > 0.0) {
            vel.y = controller.jump_speed;
            controller.velocity_y = controller.jump_speed;
            controller.grounded = false;
            controller.coyote_timer = 0.0;
            controller.jump_buffer_timer = 0.0;
        }

        controller.grounded = false;

        var remaining = step;
        var substeps: usize = 0;
        while (remaining > 0.0 and substeps < 8) : (substeps += 1) {
            const sub_dt = @min(remaining, 1.0 / 120.0);
            resolveAxis(&pos, half, vel.x * sub_dt, .x, &vel, skin, colliders, &controller.grounded);
            resolveAxis(&pos, half, vel.z * sub_dt, .z, &vel, skin, colliders, &controller.grounded);
            resolveAxis(&pos, half, vel.y * sub_dt, .y, &vel, skin, colliders, &controller.grounded);
            remaining -= sub_dt;
        }

        transform.translation = pos;
        controller.velocity_y = vel.y;
    }
}

const Axis = enum { x, y, z };

fn resolveAxis(
    pos: *Vec3,
    half: Vec3,
    delta: f32,
    comptime axis: Axis,
    velocity: *Vec3,
    skin: f32,
    colliders: Query(.{StaticAabb}),
    grounded_out: *bool,
) void {
    if (!(delta != 0.0)) return;

    switch (axis) {
        .x => pos.x += delta,
        .y => pos.y += delta,
        .z => pos.z += delta,
    }

    var player_box = aabbFromCenter(pos.*, half);

    var it = colliders.iterator();
    while (it.next()) |row| {
        const blocker = row.get(StaticAabb) orelse continue;
        if (!aabbIntersects(player_box, blocker.*)) continue;

        if (delta > 0.0) {
            switch (axis) {
                .x => pos.x = blocker.min.x - half.x - skin,
                .y => {
                    pos.y = blocker.min.y - half.y - skin;
                    velocity.y = 0.0;
                },
                .z => pos.z = blocker.min.z - half.z - skin,
            }
        } else {
            switch (axis) {
                .x => pos.x = blocker.max.x + half.x + skin,
                .y => {
                    pos.y = blocker.max.y + half.y + skin;
                    velocity.y = 0.0;
                    grounded_out.* = true;
                },
                .z => pos.z = blocker.max.z + half.z + skin,
            }
        }

        player_box = aabbFromCenter(pos.*, half);

        switch (axis) {
            .x => velocity.x = 0.0,
            .z => velocity.z = 0.0,
            .y => {},
        }
    }
}

fn spawnTexturedBox(
    commands: *ecs.Commands,
    mesh_library: *MeshLibrary,
    renderer_state: *render.Renderer,
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
        try spawnTexturedQuad(commands, mesh_library, renderer_state, material, .{
            .position = center.add(.{ .x = 0.0, .y = 0.0, .z = half.z }),
            .rotation = quatFromEuler(0.0, 0.0, 0.0),
            .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        }, face_x, face_y, uv_mode);
    }
    if (faces.back) {
        try spawnTexturedQuad(commands, mesh_library, renderer_state, material, .{
            .position = center.add(.{ .x = 0.0, .y = 0.0, .z = -half.z }),
            .rotation = quatFromEuler(0.0, std.math.pi, 0.0),
            .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        }, face_x, face_y, uv_mode);
    }
    if (faces.right) {
        try spawnTexturedQuad(commands, mesh_library, renderer_state, material, .{
            .position = center.add(.{ .x = half.x, .y = 0.0, .z = 0.0 }),
            .rotation = quatFromEuler(0.0, -std.math.pi * 0.5, 0.0),
            .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        }, face_z, face_y, uv_mode);
    }
    if (faces.left) {
        try spawnTexturedQuad(commands, mesh_library, renderer_state, material, .{
            .position = center.add(.{ .x = -half.x, .y = 0.0, .z = 0.0 }),
            .rotation = quatFromEuler(0.0, std.math.pi * 0.5, 0.0),
            .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        }, face_z, face_y, uv_mode);
    }
    if (faces.top) {
        try spawnTexturedQuad(commands, mesh_library, renderer_state, material, .{
            .position = center.add(.{ .x = 0.0, .y = half.y, .z = 0.0 }),
            .rotation = quatFromEuler(-std.math.pi * 0.5, 0.0, 0.0),
            .scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        }, face_x, face_z, uv_mode);
    }
    if (faces.bottom) {
        try spawnTexturedQuad(commands, mesh_library, renderer_state, material, .{
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
    mesh_library: *MeshLibrary,
    renderer_state: *render.Renderer,
    material: Material,
    pose: QuadPose,
    width: f32,
    height: f32,
    uv_mode: UvSamplingMode,
) !void {
    const mesh = try createQuadMesh(commands.allocator, mesh_library, renderer_state, width, height, uv_mode);
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
    mesh_library: *MeshLibrary,
    renderer_state: *render.Renderer,
    material: Material,
    pose: QuadPose,
    width: f32,
    height: f32,
    uv_rect: UvRect,
) !void {
    try spawnTexturedQuadUvRectInLayer(0, commands, mesh_library, renderer_state, material, pose, width, height, uv_rect);
}

fn spawnTexturedQuadUvRectInLayer(
    comptime layer: i32,
    commands: *ecs.Commands,
    mesh_library: *MeshLibrary,
    renderer_state: *render.Renderer,
    material: Material,
    pose: QuadPose,
    width: f32,
    height: f32,
    uv_rect: UvRect,
) !void {
    const mesh = try createQuadMeshUvRect(commands.allocator, mesh_library, renderer_state, width, height, uv_rect);
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
    _ = try commands.createEntity(.{StaticAabb{
        .min = .{ .x = center.x - half.x, .y = center.y - half.y, .z = center.z - half.z },
        .max = .{ .x = center.x + half.x, .y = center.y + half.y, .z = center.z + half.z },
    }});
}

fn aabbFromCenter(center: Vec3, half: Vec3) StaticAabb {
    return .{
        .min = .{ .x = center.x - half.x, .y = center.y - half.y, .z = center.z - half.z },
        .max = .{ .x = center.x + half.x, .y = center.y + half.y, .z = center.z + half.z },
    };
}

fn aabbIntersects(a: StaticAabb, b: StaticAabb) bool {
    return a.min.x <= b.max.x and a.max.x >= b.min.x and
        a.min.y <= b.max.y and a.max.y >= b.min.y and
        a.min.z <= b.max.z and a.max.z >= b.min.z;
}

fn quatFromEuler(pitch: f32, yaw: f32, roll: f32) Quat {
    const qx = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, pitch);
    const qy = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, yaw);
    const qz = Quat.fromAxisAngle(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, roll);
    return qy.mul(qx).mul(qz).normalize();
}

fn createQuadMesh(
    allocator: std.mem.Allocator,
    mesh_library: *MeshLibrary,
    renderer_state: *render.Renderer,
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
            return mesh_library.addMesh(renderer_state, vertices[0..], indices[0..]);
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

            return mesh_library.addMesh(renderer_state, vertices, indices);
        },
    }
}

fn createQuadMeshUvRect(
    allocator: std.mem.Allocator,
    mesh_library: *MeshLibrary,
    renderer_state: *render.Renderer,
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
    return mesh_library.addMesh(renderer_state, vertices[0..], indices[0..]);
}

fn createCylinderMesh(
    allocator: std.mem.Allocator,
    mesh_library: *MeshLibrary,
    renderer_state: *render.Renderer,
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

    return mesh_library.addMeshPos3Color(renderer_state, vertices.items, indices.items);
}

fn createSphereMesh(
    allocator: std.mem.Allocator,
    mesh_library: *MeshLibrary,
    renderer_state: *render.Renderer,
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

    return mesh_library.addMeshPos3Color(renderer_state, vertices.items, indices.items);
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
    color_shader: assets.Shader = .{
        .wgsl_source = @embedFile("shaders/cube_color.wgsl"),
    },
};

// Imports
const std = @import("std");
const phasor = @import("phasor");

const ecs = phasor.ecs;
const modules = phasor.modules;
const render = phasor.renderer;
const common = phasor.common;
const platform = phasor.platform;
const assets = phasor.assets;
const audio = phasor.audio;

const DeltaTime = modules.TimeModule.DeltaTime;
const RenderState = modules.RenderModule.RenderState;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResOpt = ecs.system_params.ResOpt;
const ResMut = ecs.system_params.ResMut;

const Keyboard = modules.InputModule.Keyboard;
const Mouse = modules.InputModule.Mouse;
const MouseCapture = modules.InputModule.MouseCapture;

const Vec3 = common.Vec3;
const Quat = common.Quat;
const Color = common.Color;
const Transform = common.Transform;
const Camera3d = common.Camera3d;
const ClearColor = common.ClearColor;

const MeshHandle = render.MeshHandle;
const Material = render.Material;
const MeshLibrary = render.MeshLibrary;
const MeshInstance = render.MeshInstance;
const CameraLayer = render.CameraLayer;
