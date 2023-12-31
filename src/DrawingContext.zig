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

pub const BlendMode = enum(c.sgp_blend_mode) {
    none = 0,
    blend,
    add,
    mod,
    mul,
};

/// RGBa where RGB are from 0-255 and alpha is from 0-1
pub const Color = struct {
    r: f32 = 255.0,
    g: f32 = 255.0,
    b: f32 = 255.0,
    a: f32 = 1.0,

    pub fn rgb(r: f32, g: f32, b: f32) Color {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn rgba(r: f32, g: f32, b: f32, a: f32) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn withAlpha(b: Color, a: f32) Color {
        return .{ .r = b.r, .g = b.g, .b = b.b, .a = a };
    }
};

/// Lightweight wrapper around sokol_gp
pub const ShapeContext = struct {
    pub fn init() !ShapeContext {
        c.sgp_setup(&.{});
        if (!c.sgp_is_valid()) {
            return error.Failed;
        }

        return ShapeContext{};
    }

    pub fn setBlendMode(_: *ShapeContext, mode: BlendMode) void {
        c.sgp_set_blend_mode(@intFromEnum(mode));
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

    pub fn setImage(_: *ShapeContext, channel: c_int, image: sokol.gfx.Image) void {
        c.sgp_set_image(channel, @bitCast(image));
    }

    pub fn unsetImage(_: *ShapeContext, channel: c_int) void {
        c.sgp_unset_image(channel);
    }

    pub fn resetImage(_: *ShapeContext, channel: c_int) void {
        c.sgp_reset_image(channel);
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

bounding_stack: [stack_size]BoundingBox,
stack_position: u8 = 0,

pub const BoundingBox = struct { x: u32 = 0, y: u32 = 0, w: u32 = 0, h: u32 = 0 };
const stack_size = 16;

pub fn init() !Self {
    const t = fontstash.Context.init(.{ .width = 512, .height = 512 });
    const shape = try ShapeContext.init();

    return Self{
        .text = t,
        .shape = shape,
        .bounding_stack = .{.{}} ** stack_size,
    };
}

pub fn pushBounds(self: *Self, box: BoundingBox) !void {
    if (self.stack_position >= stack_size) {
        return error.BoundingStackOverflow;
    }

    self.stack_position += 1;
    self.bounding_stack[self.stack_position] = box;
}

pub fn popBounds(self: *Self) !void {
    self.stack_position -|= 1;
}

/// Set the color using an RGBA color value
pub fn setColor(cx: *Self, color: Color) void {
    cx.shape.setColor(color.r / 255, color.g / 255, color.b / 255, color.a);
    cx.text.setColor(fontstash.encode_rgba(
        @intFromFloat(color.r),
        @intFromFloat(color.g),
        @intFromFloat(color.b),
        @intFromFloat(color.a * 255),
    ));
}

/// Render text using fontstash. Returns the vertical offset after drawing
pub inline fn drawText(cx: *Self, dx: f32, dy: f32, t: []const u8) f32 {
    return cx.text.drawText(dx, dy, t);
}

pub fn endFrame(cx: *Self) void {
    cx.text.flush();
    cx.shape.endFrame();
}
