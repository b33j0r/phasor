const phasor = @import("phasor");

const ecs = phasor.ecs;
const modules = phasor.modules;
const render = phasor.renderer;
const common = phasor.common;
const platform = phasor.platform;

const App = struct {
    pub fn configure(app: *ecs.App) !void {
        try app.installModule(modules.RenderModule);
        try app.addSystemTo("Startup", setupScene);
    }
};

pub const main = platform.main(App);

fn setupScene(commands: *ecs.Commands) !void {
    _ = try commands.createEntity(.{
        render.Triangle{
            .vertices = .{
                .{ .position = .{ 0.0, 160.0 }, .color = .{ 1.0, 0.2, 0.2 } },
                .{ .position = .{ -160.0, -140.0 }, .color = .{ 0.2, 1.0, 0.2 } },
                .{ .position = .{ 160.0, -140.0 }, .color = .{ 0.2, 0.4, 1.0 } },
            },
        },
    });

    try commands.insertResource(common.ClearColor{ .color = common.Color.BLACK });
    try commands.insertResource(common.Camera3d{ .Viewport = .{ .mode = .Center } });
}
