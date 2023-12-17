//! High-level wrapper around spawning a blocking task
const std = @import("std");
const xev = @import("xev");

const global = struct {
    var loop: *xev.Loop = undefined;
    var pool: *xev.ThreadPool = undefined;
    var initalized = false;
};

pub fn initialize(loop: *xev.Loop, pool: *xev.ThreadPool) void {
    global.loop = loop;
    global.pool = pool;
    global.initalized = true;
}

fn assertInitialized() void {
    if (!global.initalized) {
        std.log.err("Task not initialized. Call Task.initialzed() in main!", .{});
        std.process.exit(1);
    }
}

pub fn Job(comptime I: type, comptime O: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        task: xev.ThreadPool.Task,
        wg: xev.Async,

        input: I,
        output: O,

        pub fn wait(
            self: *Self,
            comptime C: type,
            user_context: C,
            callback: *const fn (C, O) void,
        ) !void {
            const completion = try self.allocator.create(xev.Completion);
            const Context = struct {
                user_context: C,
                callback: *const fn (C, O) void,
                self: *Self,
            };
            const context = try self.allocator.create(Context);
            context.* = .{
                .user_context = user_context,
                .callback = callback,
                .self = self,
            };

            const cb = struct {
                fn wrapper(
                    s: ?*Context,
                    l: *xev.Loop,
                    c: *xev.Completion,
                    r: xev.ReadError!void,
                ) xev.CallbackAction {
                    r catch {};
                    _ = l;
                    if (s) |ctx| {
                        const allocator = ctx.self.allocator;

                        allocator.destroy(c);
                        ctx.callback(ctx.user_context, ctx.self.output);
                        allocator.destroy(ctx.self);
                        allocator.destroy(ctx);
                    }
                    return .disarm;
                }
            }.wrapper;

            self.wg.wait(global.loop, completion, Context, context, cb);
        }
    };
}

/// Spawn a blocking task, executed in a thread pool.
/// Allocates memory for the job structure (owned by caller)
pub fn spawnBlocking(
    allocator: std.mem.Allocator,
    comptime I: type,
    comptime O: type,
    comptime func: fn (I) O,
    input: I,
) !*Job(I, O) {
    assertInitialized();
    const callback = struct {
        fn callback(task: *xev.ThreadPool.Task) void {
            var job = @fieldParentPtr(Job(I, O), "task", task);
            job.output = func(job.input);
            job.wg.notify() catch |err| {
                // TODO: How do should we handle errors here
                std.log.err("failed to notify: {}", .{err});
            };
        }
    }.callback;
    const wg = try xev.Async.init();
    const task = xev.ThreadPool.Task{ .callback = &callback };

    var job = try allocator.create(Job(I, O));
    job.allocator = allocator;
    job.task = task;
    job.wg = wg;
    job.input = input;

    const batch = xev.ThreadPool.Batch.from(&job.task);
    global.pool.schedule(batch);

    return job;
}
