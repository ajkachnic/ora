const fontstash = @import("fontstash.zig");
const sokol = @import("sokol");
const std = @import("std");

const c = @cImport({
    @cInclude("sokol_gfx.h");
    @cInclude("sokol_gp.h");
});

pub const Rect = struct {
    w: u32,
    h: u32,
    x: i32,
    y: i32,
};

pub const ShapeContext = struct {
    pub fn init() !ShapeContext {
        std.log.info("initalizing shape", .{});
        c.sgp_setup(&.{});
        if (!c.sgp_is_valid()) {
            return error.Failed;
        }

        return ShapeContext{};
    }

    pub fn beginFrame(_: *ShapeContext, width: u32, height: u32) void {
        // const ratio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

        c.sgp_begin(@intCast(width), @intCast(height));
        c.sgp_viewport(0, 0, @intCast(width), @intCast(height));
        // c.sgp_project(-ratio, ratio, 1.0, -1.0);
    }

    pub fn setColor(_: *ShapeContext, r: f32, g: f32, b: f32, a: f32) void {
        c.sgp_set_color(r, g, b, a);
    }

    pub fn fillRect(_: *ShapeContext, x: f32, y: f32, w: f32, h: f32) void {
        c.sgp_draw_filled_rect(x, y, w, h);
    }

    pub fn line(_: *ShapeContext, ax: f32, ay: f32, bx: f32, by: f32) void {
        c.sgp_draw_line(ax, ay, bx, by);
    }

    pub fn reset(_: *ShapeContext) void {
        c.sgp_reset_state();
    }

    /// Render a frame. Must be called after `beginPass` and before `endPass`
    pub fn endFrame(_: *ShapeContext) void {
        c.sgp_flush();
        c.sgp_end();
    }
};

const Self = @This();

text: fontstash.Context,
shape: ShapeContext,

pub fn init() !Self {
    const text = fontstash.Context.init(.{ .width = 512, .height = 512 });
    const shape = try ShapeContext.init();

    return Self{ .text = text, .shape = shape };
}