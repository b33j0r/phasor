pub const std_options = @import("common").logging.moduleStdOptions();

test "import tests" {
    _ = common;
    _ = db;
    _ = ecs;
    _ = graph;
    _ = metrics;
    _ = lighting;
    _ = modules;
    _ = particles;
    _ = platform;
    _ = renderer;
    _ = gui;
    _ = assets;
    _ = audio;
}

// Imports
pub const common = @import("common");
pub const db = @import("db");
pub const ecs = @import("ecs");
pub const graph = @import("graph");
pub const metrics = @import("metrics");
pub const lighting = @import("lighting");
pub const modules = @import("modules");
pub const particles = @import("particles");
pub const platform = @import("platform");
pub const renderer = @import("render");
pub const gui = @import("gui");
pub const assets = @import("assets");
pub const audio = @import("audio");

pub const App = platform.RuntimeApp;
pub const AppCommands = ecs.AppCommands;
pub const Commands = ecs.Commands;
pub const Entity = ecs.Entity;
pub const Exit = ecs.resources.Exit;

pub const Query = ecs.system_params.Query;
pub const GroupBy = ecs.system_params.GroupBy;
pub const Res = ecs.system_params.Res;
pub const ResMut = ecs.system_params.ResMut;
pub const ResOpt = ecs.system_params.ResOpt;
pub const ResMutOpt = ecs.system_params.ResMutOpt;
pub const HasResource = ecs.system_params.HasResource;
pub const WorldRef = ecs.system_params.WorldRef;
pub const Without = ecs.system_params.Without;
pub const EventReader = ecs.events.EventReader;
pub const EventWriter = ecs.events.EventWriter;

pub const Vec2 = common.Vec2;
pub const Vec3 = common.Vec3;
pub const Mat4 = common.Mat4;
pub const Quat = common.Quat;
pub const Color = common.Color;
pub const ClearColor = common.ClearColor;
pub const Transform = common.Transform;
pub const LocalTransform = common.LocalTransform;
pub const Parent = common.Parent;
pub const Camera3d = common.Camera3d;
pub const ViewportLayout = common.ViewportLayout;
pub const LayoutValue = common.LayoutValue;
pub const WindowFlags = common.WindowFlags;
pub const WindowSettings = common.WindowSettings;
pub const WindowBounds = common.WindowBounds;
pub const RenderBounds = common.RenderBounds;
pub const ContentScale = common.ContentScale;
pub const WindowResized = common.WindowResized;
pub const ContentScaleChanged = common.ContentScaleChanged;
pub const Paused = common.Paused;

pub const TimeModule = modules.TimeModule;
pub const TimerModule = modules.TimerModule;
pub const ParentModule = modules.ParentModule;
pub const PhasesModule = modules.PhasesModule;
pub const InputModule = modules.InputModule;
pub const NoiseModule = modules.NoiseModule;
pub const NoiseResource = modules.NoiseResource;
pub const FastNoise = modules.FastNoise;

pub const RenderModule = renderer.RenderModule;
pub const LayoutModule = renderer.LayoutModule;
pub const SkyModule = renderer.SkyModule;
pub const AssetsModule = assets.AssetsModule;
pub const AudioModule = audio.AudioModule;
pub const GuiModule = gui.GuiModule;
pub const MetricsModule = metrics.MetricsModule;
pub const MetricsModuleLayered = metrics.MetricsModuleLayered;
pub const DebugModule = metrics.DebugModule;
pub const DebugModuleLayered = metrics.DebugModuleLayered;
pub const DebugSettings = metrics.DebugSettings;
pub const CrashDumpModule = metrics.CrashDumpModule;
pub const SoakMonitorModule = metrics.SoakMonitorModule;

pub const DeltaTime = modules.TimeModule.DeltaTime;
pub const ElapsedTime = modules.TimeModule.ElapsedTime;
pub const RunTime = modules.TimeModule.RunTime;
pub const SimulationDeltaTime = modules.TimeModule.SimulationDeltaTime;

pub const MeshInstance = renderer.MeshInstance;
pub const MeshHandle = renderer.MeshHandle;
pub const Material = renderer.Material;
pub const MaterialHandle = renderer.MaterialHandle;
pub const MeshFactory = renderer.MeshFactory;
pub const BuildContext = renderer.BuildContext;
pub const AssetsContext = renderer.AssetsContext;
pub const VSync = renderer.VSync;
pub const Text = renderer.Text;
pub const Sprite = renderer.Sprite;
pub const ShapesModule = renderer.ShapesModule;
pub const Circle = renderer.Circle;
pub const Rectangle = renderer.Rectangle;
pub const Layer = renderer.Layer;
pub const LayerN = renderer.LayerN;
pub const LayerOverride = renderer.LayerOverride;
pub const CameraLayer = renderer.CameraLayer;
pub const CameraLayerN = renderer.CameraLayerN;
pub const RenderSurface = renderer.RenderSurface;
pub const RenderState = renderer.RenderState;
pub const ViewportSize = renderer.ViewportSize;
pub const FramebufferSize = renderer.FramebufferSize;
pub const LayerCameras = renderer.LayerCameras;
pub const LayerViewports = renderer.LayerViewports;
pub const CoreShaders = renderer.CoreShaders;
pub const DefaultFont = renderer.DefaultFont;

pub const Sound = assets.Sound;
pub const Scene = assets.Scene;
pub const Texture = assets.Texture;
pub const Mesh = assets.Mesh;
pub const Shader = assets.Shader;
pub const PostProcessShader = assets.PostProcessShader;
pub const Font = assets.Font;
pub const SoundPlayer = audio.SoundPlayer;

pub const Light = lighting.Light;
pub const LightVisibility = lighting.LightVisibility;
pub const DirectionalLight = lighting.DirectionalLight;
pub const PointLight = lighting.PointLight;
pub const SpotLight = lighting.SpotLight;
pub const AmbientLight = lighting.AmbientLight;
pub const EnvironmentLight = lighting.EnvironmentLight;
pub const ExposureSettings = lighting.ExposureSettings;

pub const Keyboard = modules.InputModule.Keyboard;
pub const Mouse = modules.InputModule.Mouse;
pub const MouseDelta = modules.InputModule.MouseDelta;
pub const MouseMoved = modules.InputModule.MouseMoved;
pub const MouseButton = modules.InputModule.MouseButton;
pub const Key = modules.InputModule.Key;
pub const KeyDown = modules.InputModule.KeyDown;
pub const KeyPressed = modules.InputModule.KeyPressed;
pub const KeyReleased = modules.InputModule.KeyReleased;

pub const GuiBuilder = gui.Builder;
pub const GuiBox = gui.Box;
pub const GuiNode = gui.Node;
pub const GuiPlacement = gui.Placement;
