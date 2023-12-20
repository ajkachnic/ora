pub const Color = @import("DrawingContext.zig").Color;

pub const colors = struct {
    pub const white = Color.rgb(255, 255, 255);
    pub const black = Color.rgb(0, 0, 0);
};
