//! High-level wrapper around spawning a blocking task
const std = @import("std");
const xev = @import("xev");

const runtime = @import("runtime.zig");

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
                    _ = l;
                    r catch |err| {
                        std.log.err("read error: {}", .{err});
                    };
                    if (s) |ctx| {
                        const allocator = ctx.self.allocator;

                        allocator.destroy(c);
                        ctx.callback(ctx.user_context, ctx.self.output);
                        allocator.destroy(ctx.self);
                        allocator.destroy(ctx);
                    } else {
                        std.log.warn("wasn't passed context...", .{});
                    }
                    return .disarm;
                }
            }.wrapper;

            self.wg.wait(runtime.global.loop, completion, Context, context, cb);
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
    runtime.assertInitialized();
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
    runtime.global.pool.schedule(batch);

    return job;
}
