const glfw = @import("mach-glfw");
const sokol = @import("sokol");

const DrawingContext = @import("DrawingContext.zig");
const Color = DrawingContext.Color;

pub const colors = struct {
    pub const white = Color.rgb(255, 255, 255);
    pub const black = Color.rgb(0, 0, 0);
};

pub fn beginFrame(w: glfw.Window, cx: *DrawingContext) void {
    const size = w.getSize();

    cx.shape.beginFrame(size.width, size.height);
    cx.shape.setBlendMode(.blend);

    sokol.gl.defaults();
    sokol.gl.matrixModeProjection();
    sokol.gl.ortho(0.0, @floatFromInt(size.width), @floatFromInt(size.height), 0.0, -1, 1);
}

pub fn endFrame(
    w: glfw.Window,
    cx: *DrawingContext,
    pass_action: sokol.gfx.PassAction,
) void {
    const size = w.getSize();

    sokol.gfx.beginDefaultPass(pass_action, @intCast(size.width), @intCast(size.height));
    cx.endFrame();

    sokol.gl.draw();
    sokol.gfx.endPass();
    sokol.gfx.commit();
}
