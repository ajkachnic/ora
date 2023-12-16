//! Widget implementation
const DrawingContext = @import("DrawingContext.zig");

pub fn Widget(T: type) type {
    _ = T;
}

pub const TextWidget = Widget(struct {
    const State = struct {
        text: []const u8,
    };

    pub fn init(text: []const u8) State {
        State{ .text = text };
    }

    pub fn frame(state: State, ctx: DrawingContext) void {
        _ = state;
        _ = ctx;
    }
});
