const std = @import("std");
const phasor = @import("phasor");
const loading = @import("example_shared").loading;

const ReadyCard = struct {};
const ReadyLabel = struct {};

const LoadStep = struct {
    label: []const u8,
    duration_seconds: f32,
};

const load_steps = [_]LoadStep{
    .{ .label = "Discovering fake bundle", .duration_seconds = 0.35 },
    .{ .label = "Loading placeholder textures", .duration_seconds = 0.55 },
    .{ .label = "Preparing synthetic meshes", .duration_seconds = 0.45 },
    .{ .label = "Uploading demo scene", .duration_seconds = 0.4 },
};

const FakeLoader = struct {
    active_step: usize = 0,
    step_elapsed: f32 = 0.0,
    complete: bool = false,

    fn totalSteps(_: *const FakeLoader) usize {
        return load_steps.len;
    }

    fn completedSteps(self: *const FakeLoader) usize {
        return @min(self.active_step, self.totalSteps());
    }

    fn progress01(self: *const FakeLoader) f32 {
        if (self.complete) return 1.0;
        const total = @as(f32, @floatFromInt(self.totalSteps()));
        const finished = @as(f32, @floatFromInt(self.completedSteps()));
        const current = load_steps[self.active_step];
        const step_progress = std.math.clamp(self.step_elapsed / current.duration_seconds, 0.0, 1.0);
        return (finished + step_progress) / total;
    }

    fn activeLabel(self: *const FakeLoader) []const u8 {
        if (self.complete) return "Ready";
        return load_steps[self.active_step].label;
    }
};

pub fn main(init: std.process.Init) !u8 {
    var app = try App.init(&init, .{
        .command_queue_capacity = 128,
        .parallel_systems = true,
    });
    defer app.deinit();

    try app.insertResource(WindowSettings{
        .title = "Loading",
        .width = 800,
        .height = 600,
    });
    try app.insertResource(VSync{ .enabled = false });
    try app.insertResource(ClearColor{ .color = Color.rgb(10, 12, 18) });

    try app.installDefaultModules();
    try app.installModule(MetricsModuleLayered(Layer(1000)){
        .font_size = 24.0,
        .text_color = Color.WHITE,
    });

    try app.addSystem("Startup", setup);
    try app.addSystem("Startup", loading.setup);
    try app.addSystem("Update", simulateLoading);
    try app.addSystem("Update", loading.sync);
    try app.addSystem("Update", revealLoadedScene);

    return try app.run();
}

fn setup(commands: *Commands) !void {
    try commands.insertResource(FakeLoader{});

    _ = try commands.createEntity(.{
        Transform{},
        Camera{ .Viewport = .{ .mode = .Center } },
        CameraLayer(0){},
    });

    _ = try commands.createEntity(.{
        Transform{},
        Camera{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(1000){},
    });

    _ = try commands.createEntity(.{
        ReadyCard{},
        Transform{
            .translation = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            .scale = Vec3.splat(0.0),
        },
        Rectangle{
            .width = 220.0,
            .height = 220.0,
            .color = Color.rgb(227, 84, 34),
        },
        Layer(0){},
    });

    _ = try commands.createEntity(.{
        ReadyLabel{},
        Transform{ .translation = .{ .x = 0.0, .y = 150.0, .z = 0.0 } },
        Text{
            .font_size = 28.0,
            .color = Color.rgb(241, 242, 244),
            .content = "",
            .horizontal_alignment = .Center,
            .vertical_alignment = .Center,
        },
        Layer(0){},
    });
}

fn simulateLoading(
    delta: Res(DeltaTime),
    loader: ResMut(FakeLoader),
    ui: ResMut(loading.Model),
) !void {
    if (loader.ptr.complete) {
        ui.ptr.visible = false;
        ui.ptr.progress01 = 1.0;
        ui.ptr.clearStatus();
        return;
    }

    loader.ptr.step_elapsed += delta.deref().clampedSeconds32(0.1);
    const current = load_steps[loader.ptr.active_step];
    if (loader.ptr.step_elapsed >= current.duration_seconds) {
        loader.ptr.step_elapsed -= current.duration_seconds;
        loader.ptr.active_step += 1;
        if (loader.ptr.active_step >= load_steps.len) {
            loader.ptr.active_step = load_steps.len;
            loader.ptr.complete = true;
            ui.ptr.visible = false;
            ui.ptr.progress01 = 1.0;
            ui.ptr.clearStatus();
            return;
        }
    }

    ui.ptr.visible = true;
    ui.ptr.progress01 = loader.ptr.progress01();
    try ui.ptr.setStatusFmt(
        "{s}\n{d}% complete ({d}/{d})",
        .{
            loader.ptr.activeLabel(),
            @as(usize, @intFromFloat(ui.ptr.progress01 * 100.0)),
            loader.ptr.completedSteps(),
            loader.ptr.totalSteps(),
        },
    );
}

fn revealLoadedScene(
    elapsed: Res(ElapsedTime),
    loader: Res(FakeLoader),
    card_query: Query(.{ Transform, ReadyCard }),
    label_query: Query(.{ Text, ReadyLabel }),
) void {
    const visible = loader.ptr.complete;
    const seconds = @as(f32, @floatCast(elapsed.deref().seconds));

    var card_it = card_query.iterator();
    while (card_it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.scale = Vec3.splat(if (visible) 1.0 else 0.0);
        transform.rotation = if (visible)
            Quat.fromAxisAngle(.{ .z = 1.0 }, seconds * 0.5)
        else
            Quat.identity();
    }

    var label_it = label_query.iterator();
    while (label_it.next()) |row| {
        const text = row.get(Text) orelse continue;
        text.content = if (visible) "Fake bundle loaded" else "";
    }
}

const App = phasor.App;
const Camera = phasor.Camera;
const CameraLayer = phasor.CameraLayer;
const ClearColor = phasor.ClearColor;
const Color = phasor.Color;
const Commands = phasor.Commands;
const DeltaTime = phasor.DeltaTime;
const ElapsedTime = phasor.ElapsedTime;
const Layer = phasor.Layer;
const MetricsModuleLayered = phasor.MetricsModuleLayered;
const Query = phasor.Query;
const Quat = phasor.Quat;
const Rectangle = phasor.Rectangle;
const Res = phasor.Res;
const ResMut = phasor.ResMut;
const Text = phasor.Text;
const Transform = phasor.Transform;
const Vec3 = phasor.Vec3;
const VSync = phasor.VSync;
const WindowSettings = phasor.WindowSettings;
