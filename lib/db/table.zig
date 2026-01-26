/// Creates a table with the specified column specification.
///
/// ```
/// const Position = struct {
///     x: f32,
///     y: f32,
/// };
/// const State = enum {
///     Idle,
///     Running,
/// };
/// fn main() void {
///     const table = Table(.{Position, State});
/// }
/// ```
pub fn Table(_: anytype) type {
    return struct {
        const Self = @This();
    };
}
