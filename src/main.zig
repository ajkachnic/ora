//------------------------------------------------------------------------------
//  triangle.zig
//
//  Vertex buffer, shader, pipeline state object.
//------------------------------------------------------------------------------
const sokol = @import("sokol");
const std = @import("std");
const glfw = @import("mach-glfw");
const xev = @import("xev");

const slog = sokol.log;
const sg = sokol.gfx;
const sgl = sokol.gl;
const sapp = sokol.app;
const sgapp = sokol.app_gfx_glue;
const math = std.math;

const DrawingContext = @import("DrawingContext.zig");
const fontstash = @import("fontstash.zig");
const Task = @import("Task.zig");
const TextBuffer = @import("TextBuffer.zig");
const tools = @import("tools.zig");

pub const state = struct {
    var pass_action = sg.PassAction{};

    var ctx: DrawingContext = undefined;
    var font: fontstash.Font = undefined;

    var buffer: TextBuffer = undefined;

    var launcher: tools.Launcher = undefined;
    var candidates: std.ArrayList(tools.Candidate) = undefined;

    var pool: xev.ThreadPool = undefined;
    var loop: xev.Loop = undefined;
    pub var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
};

fn oom() noreturn {
    @panic("oom");
}

fn init() !void {
    sg.setup(.{
        // .context = sgapp.context(),
        .logger = .{ .func = slog.func },
    });

    sgl.setup(.{
        .logger = .{ .func = slog.func },
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };

    state.launcher = tools.Launcher.init(state.gpa.allocator());
    try state.launcher.runTasks();

    state.candidates = std.ArrayList(tools.Candidate).init(state.gpa.allocator());

    state.ctx = try DrawingContext.init();
    state.font = state.ctx.text.load("sans", "Geist-Regular.ttf") orelse @panic("failed to load font!");

    state.buffer = TextBuffer.from(
        state.gpa.allocator(),
        "",
    ) catch oom();
}

fn sort(_: void, lhs: tools.Candidate, rhs: tools.Candidate) bool {
    return lhs.score > rhs.score;
}

fn frame(w: glfw.Window) !void {
    if (state.buffer.dirty) {
        state.candidates.clearRetainingCapacity();

        const start = std.time.nanoTimestamp();
        try state.launcher.generate(state.buffer.buffer.items, &state.candidates);
        std.log.info("generated candiates: {d}ms", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start)) / 100_000});
    }

    std.sort.block(tools.Candidate, state.candidates.items, {}, sort);

    const dpis = 1;
    const size = w.getSize();
    var ctx = state.ctx;
    const white = fontstash.encode_rgba(255, 255, 255, 255);
    const gray = fontstash.encode_rgba(80, 80, 80, 255);

    const metrics = ctx.text.verticalMetrics();

    ctx.shape.beginFrame(size.width, size.height);

    ctx.text.clearState();

    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.ortho(0.0, @floatFromInt(size.width), @floatFromInt(size.height), 0.0, -1, 1);

    ctx.text.setFont(state.font);
    ctx.text.setSize(24 * dpis);

    const dx = 24;
    var dy: f32 = 24;

    if (state.buffer.buffer.items.len > 0) {
        ctx.text.setColor(white);
        _ = ctx.text.drawText(dx, dy, state.buffer.buffer.items);

        dy += metrics.lineh;

        for (state.candidates.items) |candidate| {
            if (candidate.score == 0) continue;
            _ = ctx.text.drawText(dx, dy, candidate.text);
            dy += metrics.lineh;
        }
    } else {
        // placeholder
        ctx.text.setColor(gray);
        _ = ctx.text.drawText(24, 24, "Search for applications...");
    }

    ctx.shape.setColor(1.0, 1.0, 0.3, 1.0);
    ctx.shape.fillRect(200, 200, 150, 400);

    ctx.text.flush();

    sg.beginDefaultPass(state.pass_action, @intCast(size.width), @intCast(size.height));
    ctx.shape.endFrame();
    sgl.draw();
    sg.endPass();
    sg.commit();

    state.buffer.dirty = false;
}

fn handleChar(w: glfw.Window, codepoint: u21) void {
    _ = w;
    if (codepoint < 0xff) {
        state.buffer.insertChar(@intCast(codepoint)) catch oom();
    }
}

fn handleKey(w: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    _ = w;
    _ = scancode;
    _ = mods;

    if (action == .release) return;
    switch (key) {
        .backspace => {
            _ = state.buffer.removeBeforeCursor();
        },
        .left => state.buffer.moveCursor(.left),
        .right => state.buffer.moveCursor(.right),
        else => {},
    }
}

fn cleanup() void {
    sgl.shutdown();
    sg.shutdown();

    // de-allocate memory
    const allocator = state.gpa.allocator();
    _ = allocator;

    state.buffer.deinit();
    state.candidates.deinit();
    state.launcher.deinit();
}

/// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

pub fn setupGLFW() glfw.Window {
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    }

    const window = glfw.Window.create(640, 640, "ora", null, null, .{
        .resizable = false,
        .decorated = false,
    }) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    };

    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);
    window.show();

    return window;
}

pub fn main() !void {
    const window = setupGLFW();
    defer glfw.terminate();
    defer window.destroy();

    state.gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = state.gpa.deinit();

    state.pool = xev.ThreadPool.init(.{});
    defer state.pool.deinit();
    defer state.pool.shutdown();

    state.loop = try xev.Loop.init(.{});
    defer state.loop.deinit();

    Task.initialize(&state.loop, &state.pool);

    init() catch {
        std.log.err("Failed to initalize program", .{});
        std.process.exit(1);
    };
    defer cleanup();

    window.setCharCallback(handleChar);
    window.setKeyCallback(handleKey);

    while (!window.shouldClose()) {
        try state.loop.run(.no_wait);
        try frame(window);
        window.swapBuffers();
        glfw.pollEvents();
    }
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
