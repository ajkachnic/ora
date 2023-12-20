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
const tools = @import("tools.zig");
const ui = @import("ui.zig");

const ImageView = @import("views/image.zig");
const EditorView = @import("views/editor.zig");

const Color = DrawingContext.Color;

const geist_regular = @embedFile("assets/Geist-Regular.ttf");
const geist_semibold = @embedFile("assets/Geist-SemiBold.ttf");

pub const state = struct {
    var pass_action = sg.PassAction{};

    var ctx: DrawingContext = undefined;
    var font_regular: fontstash.Font = undefined;
    var font_bold: fontstash.Font = undefined;

    var editor: EditorView = undefined;

    var launcher: tools.Launcher = undefined;
    var candidates: std.ArrayList(tools.Candidate) = undefined;
    var selection: usize = 0;

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
    state.font_regular = state.ctx.text.add("regular", geist_regular, false) orelse @panic("failed to load font!");
    state.font_bold = state.ctx.text.add("bold", geist_semibold, false) orelse @panic("failed to load font!");

    state.editor = EditorView.init(state.gpa.allocator());

    state.icons = std.StringHashMap(*ImageView).init(state.gpa.allocator());
}

fn sort(_: void, lhs: tools.Candidate, rhs: tools.Candidate) bool {
    return lhs.score > rhs.score;
}

fn frame(w: glfw.Window) !void {
    var cx = state.ctx;
    ui.beginFrame(w, &cx);

    if (state.editor.buffer.dirty) {
        state.candidates.clearRetainingCapacity();
        try state.launcher.generate(state.editor.buffer.text(), &state.candidates);
        std.sort.block(tools.Candidate, state.candidates.items, {}, sort);
    }

    const dpis = 1.0;
    const size = w.getSize();

    cx.text.clearState();
    cx.text.setAlign(.left, .middle);

    cx.text.setFont(state.font_regular);
    cx.text.setSize(24 * dpis);

    const metrics = cx.text.verticalMetrics();

    const dx = 24;
    var dy: f32 = 32;

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

    state.editor.frame(&cx, dx, dy);
    dy += metrics.lineh * 1.75;

    if (!state.editor.isEmpty()) {
        const temp_selection = std.math.clamp(state.selection, 0, @min(10, state.candidates.items.len -| 1));

        cx.setColor(ui.colors.white.withAlpha(0.5));
        cx.text.setSize(20 * dpis);
        _ = cx.drawText(dx, dy, "Applications");

        dy += metrics.lineh * 1.125;

        for (state.candidates.items, 0..) |candidate, i| {
            cx.text.setFont(state.font_regular);
            cx.text.setSize(24 * dpis);
            cx.setColor(ui.colors.white);
            const inner_padding = metrics.lineh * 2;

            cx.setColor(ui.colors.white.withAlpha(0.5));
            if (temp_selection == i) {
                cx.setColor(ui.colors.white.withAlpha(0.03));
                cx.shape.fillRect(
                    dx,
                    dy,
                    @floatFromInt(size.width - dx * 2),
                    inner_padding,
                );
                cx.setColor(ui.colors.white);
            }

            _ = cx.drawText(dx + 48, dy + inner_padding * 0.5, candidate.text);

            if (state.icons.get(candidate.icon)) |icon| {
                cx.setColor(ui.colors.white);
                icon.frame(&cx, dx + 8, dy + inner_padding * 0.5 - 16);
            }
            dy += inner_padding + metrics.lineh * 0.125;

            if (i >= 9) break;
        }
    }

    ui.endFrame(w, &cx, state.pass_action);
    state.editor.buffer.dirty = false;
}

fn handleChar(w: glfw.Window, codepoint: u21) void {
    _ = w;
    if (codepoint < 0xff) {
        state.editor.buffer.insertChar(@intCast(codepoint)) catch oom();
        state.selection = 0;
    }
}

fn handleKey(w: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    _ = scancode;
    _ = mods;

    if (action == .release) return;
    switch (key) {
        .backspace => {
            _ = state.editor.buffer.removeBeforeCursor();
        },
        .left => state.editor.buffer.moveCursor(.left),
        .right => state.editor.buffer.moveCursor(.right),
        .down => state.selection = std.math.clamp(state.selection + 1, 0, state.candidates.items.len -| 1),
        .up => state.selection -|= 1,
        .escape => w.setShouldClose(true),
        .enter => runCommand() catch |err| {
            std.log.err("failed to run command: {}", .{err});
            std.process.exit(1);
        },
        else => {},
    }
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn runCommand() !void {
    const selection = std.math.clamp(
        state.selection,
        0,
        state.candidates.items.len,
    );
    const exec = state.candidates.items[selection].action;
    var argv = std.ArrayList([]const u8).init(state.gpa.allocator());
    defer argv.deinit();

    // FIXME: this is a half-assed implementation of the rules. it will defintely break
    // ref: https://specifications.freedesktop.org/desktop-entry-spec/desktop-entry-spec-1.1.html#exec-variables
    var iterator = std.mem.splitScalar(u8, exec, ' ');
    while (iterator.next()) |segment| {
        if (eq(segment, "%f") or eq(segment, "%F")) continue;
        if (eq(segment, "%u") or eq(segment, "%U")) continue;
        if (eq(segment, "%d") or eq(segment, "%D")) continue;
        if (eq(segment, "%n") or eq(segment, "%N")) continue;

        if (std.mem.startsWith(u8, segment, "\"")) {
            try argv.append(segment[1 .. segment.len - 1]);
        } else {
            try argv.append(segment);
        }
    }

    const err = std.process.execv(state.gpa.allocator(), argv.items);
    std.process.cleanExit();

    return err;
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
    state.editor.deinit();
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

    while (!window.shouldClose()) {
        try state.loop.run(.no_wait);
        try frame(window);
        window.swapBuffers();
        glfw.pollEvents();
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
