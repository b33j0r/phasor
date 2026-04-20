test "import tests" {
    _ = FpsControlInput;
    _ = FpsPhysicsModule;
    _ = FpsKeyBindings;
    _ = FpsKeyBindingModule;
}

pub const FpsControlInput = @import("fps_physics").FpsControlInput;
pub const FpsPhysicsModule = @import("fps_physics").FpsPhysicsModule;
pub const FpsKeyBindings = @import("fps_key_binding").FpsKeyBindings;
pub const FpsKeyBindingModule = @import("fps_key_binding").FpsKeyBindingModule;
