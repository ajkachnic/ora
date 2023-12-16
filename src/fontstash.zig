const sokol = @import("sokol");
const std = @import("std");
const fons = sokol.fontstash;

pub const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("string.h");
    @cInclude("fontstash.h");
});

pub const Font = struct {
    id: c_int,
};

pub const VerticalMetrics = struct {
    ascender: f32,
    descender: f32,
    lineh: f32,
};

pub const Context = struct {
    inner: ?*c.FONScontext,

    pub fn init(desc: fons.Desc) Context {
        const inner: ?*c.FONScontext = @ptrCast(fons.create(desc));
        std.log.info("\ncreated context: 0x{x}", .{@intFromPtr(inner)});
        return Context{ .inner = inner };
    }

    pub fn deinit(ctx: *Context) void {
        fons.destroy(ctx.inner);
    }

    pub fn flush(ctx: *Context) void {
        fons.flush(ctx.inner);
    }

    pub fn setFont(ctx: *Context, font: Font) void {
        c.fonsSetFont(ctx.inner, font.id);
    }

    pub fn setSize(ctx: *Context, size: f32) void {
        c.fonsSetSize(ctx.inner, size);
    }

    pub fn setColor(ctx: *Context, color: u32) void {
        c.fonsSetColor(ctx.inner, color);
    }

    pub fn verticalMetrics(ctx: *Context) VerticalMetrics {
        var as: f32 = 0;
        var de: f32 = 0;
        var lh: f32 = 0;
        c.fonsVertMetrics(ctx.inner, &as, &de, &lh);

        return .{ .ascender = as, .descender = de, .lineh = lh };
    }

    /// Load a font file from disk
    pub fn load(ctx: *Context, name: [*:0]const u8, path: [*:0]const u8) ?Font {
        const id = c.fonsAddFont(ctx.inner, name, path);
        if (id == c.FONS_INVALID) {
            return null;
        }

        return Font{ .id = id };
    }

    /// Add a font from memory
    pub fn add(ctx: *Context, name: [*:0]const u8, data: []const u8, free: bool) ?Font {
        const id = c.fonsAddFontMem(ctx.inner, name, data.ptr, data.len, free);
        if (id == c.FONS_INVALID) {
            return null;
        }

        return Font{ .id = id };
    }

    /// Draw some text
    pub fn drawText(self: *const Context, dx: f32, dy: f32, text: []const u8) f32 {
        // fun pointer magic. expect bugs here
        return c.fonsDrawText(self.inner, dx, dy, text.ptr, @ptrFromInt(
            @intFromPtr(text.ptr) + text.len,
        ));
    }

    pub fn clearState(ctx: *const Context) void {
        c.fonsClearState(ctx.inner);
    }
};

pub fn encode_rgba(r: u8, g: u8, b: u8, a: u8) u32 {
    return fons.rgba(r, g, b, a);
}
