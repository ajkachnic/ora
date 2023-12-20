const std = @import("std");
const xev = @import("xev");
const sokol = @import("sokol");

const sg = sokol.gfx;

const DrawingContext = @import("../DrawingContext.zig");
const TextBuffer = @import("../TextBuffer.zig");
const ui = @import("../ui.zig");

const EditorView = @This();

pub const blink_period = 1.2;

buffer: TextBuffer,
blink_timer: f32 = 0,
last_frame: i64 = 0,

pub fn isEmpty(view: *EditorView) bool {
    return view.buffer.text().len == 0;
}

pub fn init(allocator: std.mem.Allocator) EditorView {
    return EditorView{ .buffer = TextBuffer.init(allocator) };
}

pub fn deinit(view: *EditorView) void {
    view.buffer.deinit();
}

fn delta(view: *EditorView) f32 {
    if (view.last_frame == 0) {
        view.last_frame = std.time.milliTimestamp();
        return 0.0;
    }

    const current = std.time.milliTimestamp();
    const diff = current - view.last_frame;

    view.last_frame = current;

    return @floatFromInt(diff);
}

fn updateCursor(view: *EditorView) void {
    const frame_time = view.delta();

    if (view.blink_timer > blink_period) {
        view.blink_timer = 0;
    }
    view.blink_timer += frame_time / 1000;

    if (view.blink_timer > blink_period) {
        view.blink_timer = 0;
    }
}

pub fn frame(view: *EditorView, cx: *DrawingContext, dx: f32, dy: f32) void {
    view.updateCursor();
    cx.setColor(ui.colors.white);
    cx.text.setSize(24);

    const metrics = cx.text.verticalMetrics();

    // draw cursor
    if (view.blink_timer > blink_period / 2.0) {
        const cursor_position = cx.text.textBounds(
            view.buffer.text()[0..view.buffer.cursor],
        ) + dx;
        cx.shape.line(
            cursor_position,
            dy - metrics.lineh * 0.5,
            cursor_position,
            dy + metrics.lineh * 0.5,
        );
    }

    if (view.buffer.text().len > 0) {
        _ = cx.drawText(dx, dy, view.buffer.text());
    } else {
        cx.setColor(ui.colors.white.withAlpha(0.5));
        _ = cx.drawText(dx, dy, "Search for applications...");
    }
}

pub fn update() void {}
