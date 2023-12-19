const std = @import("std");
const xev = @import("xev");
const sokol = @import("sokol");

const sg = sokol.gfx;

const runtime = @import("../runtime/runtime.zig");
const DrawingContext = @import("../DrawingContext.zig");

const c = @cImport({
    @cInclude("stb_image.h");
});

var image_map: ?std.StringHashMap(sg.Image) = null;

const ImageView = @This();

allocator: std.mem.Allocator,
path: []const u8,
job: ?*runtime.File.ReadJob,
buffer: ?[]u8 = null,
handle: sg.Image,
is_original: bool,

width: c_int = 0,
height: c_int = 0,

pub fn init(allocator: std.mem.Allocator, path: []const u8) !*ImageView {
    if (image_map == null) {
        image_map = std.StringHashMap(sg.Image).init(allocator);
    }

    if (image_map.?.get(path)) |handle| {
        const view = try allocator.create(ImageView);
        view.* = .{
            .allocator = allocator,
            .path = path,
            .job = null,
            .handle = handle,
            .is_original = false,
        };

        return view;
    }

    const job = try runtime.File.readAll(allocator, path, 1024 * 1024 * 1024 * 1024);

    const handle = sg.allocImage();

    if (sg.queryImageState(handle) != .ALLOC) {
        return error.OutOfMemory;
    }

    const view = try allocator.create(ImageView);
    view.* = .{
        .allocator = allocator,
        .path = path,
        .job = job,
        .handle = handle,
        .is_original = true,
    };

    try job.wait(*ImageView, view, loadedCallback);

    return view;
}

fn loadedCallback(self: *ImageView, buffer: []u8) void {
    std.log.info("image loaded!", .{});
    self.buffer = buffer;

    var width: c_int = 0;
    var height: c_int = 0;
    var num_channels: c_int = 0;
    const desired_channels = 4;

    const pixels = c.stbi_load_from_memory(
        self.buffer.?.ptr,
        @intCast(self.buffer.?.len),
        &width,
        &height,
        &num_channels,
        desired_channels,
    );

    if (pixels != null) {
        var subimage = [_][16]sg.Range{[_]sg.Range{.{}} ** 16} ** 6;
        subimage[0][0] = .{
            .ptr = pixels,
            .size = @intCast(width * height * 4),
        };

        sg.initImage(self.handle, .{
            .width = width,
            .height = height,
            .pixel_format = .RGBA8,
            .data = .{
                .subimage = subimage,
            },
        });

        self.width = width;
        self.height = height;
        // is this free-ing memory the sokol needs?
        // the example showed it but i'm unsure
        c.stbi_image_free(pixels);
    } else {
        std.log.err("parsing image buffer failed", .{});
    }
}
pub fn deinit(self: *ImageView) void {
    if (self.is_original) {
        sg.destroyImage(self.handle);
    }

    if (self.buffer) |buffer| {
        self.allocator.free(buffer);
    }

    self.allocator.destroy(self);
}

pub fn frame(self: *ImageView, cx: *DrawingContext, x: f32, y: f32) void {
    if (sg.queryImageState(self.handle) != .VALID) {
        return;
    }

    cx.shape.setImage(0, self.handle);
    cx.shape.fillRect(x, y, @floatFromInt(self.width), @floatFromInt(self.height));
    cx.shape.unsetImage(0);
}

pub fn update() void {}

pub fn cleanup() void {
    if (image_map) |*map| {
        map.deinit();
    }
}
