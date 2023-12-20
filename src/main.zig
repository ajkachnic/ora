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
const runtime = @import("runtime/runtime.zig");
const TextBuffer = @import("TextBuffer.zig");
const tools = @import("tools.zig");
const ImageView = @import("views/image.zig");

pub const io_mode = .blocking;

pub const state = struct {
    var pass_action = sg.PassAction{};

    var ctx: DrawingContext = undefined;
    var font: fontstash.Font = undefined;

    var buffer: TextBuffer = undefined;

    var launcher: tools.Launcher = undefined;
    var candidates: std.ArrayList(tools.Candidate) = undefined;
    var selection: usize = 0;
    var blink_timer: f32 = 0;

    var pool: xev.ThreadPool = undefined;
    var loop: xev.Loop = undefined;
    pub var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

    var icons: std.StringHashMap(*ImageView) = undefined;
};

fn oom() noreturn {
    @panic("oom");
}

fn init() !void {
    sg.setup(.{ .logger = .{ .func = slog.func } });
    sgl.setup(.{ .logger = .{ .func = slog.func } });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.01, .g = 0.01, .b = 0.01, .a = 0.95 },
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

    state.icons = std.StringHashMap(*ImageView).init(state.gpa.allocator());
}

fn sort(_: void, lhs: tools.Candidate, rhs: tools.Candidate) bool {
    return lhs.score > rhs.score;
}

const blink_period = 1.2;

fn frame(w: glfw.Window, frame_time: i64) !void {
    if (state.buffer.dirty) {
        state.candidates.clearRetainingCapacity();

        const start = std.time.nanoTimestamp();
        try state.launcher.generate(state.buffer.buffer.items, &state.candidates);
        std.log.debug("generated candiates: {d}ms", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start)) / 100_000});
    }

    if (state.blink_timer > blink_period) state.blink_timer = 0;
    state.blink_timer += @as(f32, @floatFromInt(frame_time)) / 1000;
    if (state.blink_timer > blink_period) state.blink_timer = 0;

    std.sort.block(tools.Candidate, state.candidates.items, {}, sort);

    const dpis = 1;
    const size = w.getSize();
    var ctx = state.ctx;
    const white = fontstash.encode_rgba(255, 255, 255, 255);
    const gray = fontstash.encode_rgba(80, 80, 80, 255);

    const metrics = ctx.text.verticalMetrics();

    ctx.shape.beginFrame(size.width, size.height);
    ctx.shape.setBlendMode(.blend);

    ctx.text.clearState();
    ctx.text.setAlign(.left, .middle);

    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.ortho(0.0, @floatFromInt(size.width), @floatFromInt(size.height), 0.0, -1, 1);

    ctx.text.setFont(state.font);
    ctx.text.setSize(24 * dpis);

    const dx = 24;
    var dy: f32 = 32;

    // draw cursor
    if (state.blink_timer > blink_period / 2.0) {
        const cursor_position = ctx.text.textBounds(state.buffer.buffer.items[0..state.buffer.cursor]) + dx;
        ctx.shape.setColor(1.0, 1.0, 1.0, 1.0);
        ctx.shape.line(cursor_position, dy - metrics.lineh * 0.5, cursor_position + 1, dy + metrics.lineh * 0.5);
    }

    // TODO: load icons immediately, don't wait for user input
    for (state.candidates.items) |candidate| {
        if (!state.icons.contains(candidate.icon) and candidate.icon.len != 0) {
            try state.icons.put(candidate.icon, try ImageView.init(
                state.gpa.allocator(),
                candidate.icon,
                .{ .width = 32, .height = 32 },
            ));
        }
    }

    if (state.buffer.buffer.items.len > 0) {
        ctx.text.setColor(white);
        _ = ctx.text.drawText(dx, dy, state.buffer.buffer.items);

        dy += metrics.lineh * 1.25;

        const temp_selection = std.math.clamp(state.selection, 0, @min(10, state.candidates.items.len -| 1));

        for (state.candidates.items, 0..) |candidate, i| {
            const inner_padding = metrics.lineh * 2;

            if (temp_selection == i) {
                ctx.shape.setColor(1, 1, 1, 0.1);
                ctx.shape.fillRect(
                    dx,
                    dy,
                    @floatFromInt(size.width - dx * 2),
                    inner_padding,
                );
            }

            if (state.icons.get(candidate.icon)) |icon| {
                ctx.shape.setColor(1.0, 1.0, 1.0, 1.0);
                icon.frame(&ctx, dx + 8, dy + inner_padding * 0.5 - 16);
            }

            _ = ctx.text.drawText(dx + 48, dy + inner_padding * 0.5, candidate.text);
            dy += inner_padding + metrics.lineh * 0.125;

            if (i >= 9) break;
        }
    } else {
        // placeholder
        ctx.text.setColor(gray);
        _ = ctx.text.drawText(dx, dy, "Search for applications...");
    }

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
    _ = scancode;
    _ = mods;

    if (action == .release) return;
    switch (key) {
        .backspace => {
            _ = state.buffer.removeBeforeCursor();
        },
        .left => state.buffer.moveCursor(.left),
        .right => state.buffer.moveCursor(.right),
        .down => state.selection = std.math.clamp(state.selection + 1, 0, state.candidates.items.len -| 1),
        .up => state.selection -|= 1,
        .escape => w.setShouldClose(true),
        else => {},
    }
}

fn cleanup() void {
    const allocator = state.gpa.allocator();
    _ = allocator;
    var iter = state.icons.iterator();
    while (iter.next()) |entry| {
        // allocator.free(entry.key_ptr.*);
        entry.value_ptr.*.deinit();
    }

    state.icons.deinit();
    ImageView.cleanup();

    sgl.shutdown();
    sg.shutdown();

    // de-allocate memory
    state.buffer.deinit();
    state.candidates.deinit();
    state.launcher.deinit();
}

/// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

fn centerWindow(w: glfw.Window) void {
    const size = w.getSize();

    if (glfw.Monitor.getPrimary()) |primary| {
        const workarea = primary.getWorkarea();

        w.setPos(.{
            .x = @intCast(@divFloor(workarea.width, 2) - @divFloor(size.width, 2)),
            .y = @intCast(@divFloor(workarea.height, 2) - @divFloor(size.height, 2)),
        });
    }
}

pub fn setupGLFW() glfw.Window {
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    }

    const window = glfw.Window.create(640, 640, "ora", null, null, .{
        .resizable = false,
        .decorated = false,
        .floating = true,
        .focus_on_show = true,
        .transparent_framebuffer = true,
    }) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    };

    centerWindow(window);

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

    runtime.initialize(&state.loop, &state.pool);

    init() catch {
        std.log.err("Failed to initalize program", .{});
        std.process.exit(1);
    };
    defer cleanup();

    window.setCharCallback(handleChar);
    window.setKeyCallback(handleKey);

    var time = std.time.milliTimestamp();

    while (!window.shouldClose()) {
        const new_time = std.time.milliTimestamp();
        try state.loop.run(.no_wait);
        try frame(window, new_time - time);
        window.swapBuffers();
        glfw.pollEvents();

        time = new_time;
    }
}

pub const std_options = struct {
    pub const logFn = log;
};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // Ignore all non-error logging from sources other than
    // .my_project, .nice_library and the default
    const scope_prefix = switch (scope) {
        std.log.default_log_scope => "",
        else => if (@intFromEnum(level) <= @intFromEnum(std.log.Level.err))
            "(" ++ @tagName(scope) ++ "): "
        else
            return,
    };

    const level_text = comptime switch (level) {
        .info => "\x1b[34m" ++ "INFO  " ++ "\x1b[0m",
        .err => "\x1b[31m" ++ "ERROR " ++ "\x1b[0m",
        .debug => "\x1b[36m" ++ "DEBUG " ++ "\x1b[0m",
        .warn => "\x1b[33m" ++ "WARN  " ++ "\x1b[0m",
    };

    const prefix = level_text ++ " " ++ scope_prefix;

    // Print the message to stderr, silently ignoring any errors
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
