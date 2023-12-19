const std = @import("std");
const xev = @import("xev");

pub const global = struct {
    pub var loop: *xev.Loop = undefined;
    pub var pool: *xev.ThreadPool = undefined;
    var initalized = false;
};

pub fn initialize(loop: *xev.Loop, pool: *xev.ThreadPool) void {
    global.loop = loop;
    global.pool = pool;
    global.initalized = true;
}

pub fn assertInitialized() void {
    if (!global.initalized) {
        std.log.err("Task not initialized. Call Task.initialzed() in main!", .{});
        std.process.exit(1);
    }
}

pub const Task = @import("Task.zig");
pub const File = @import("File.zig");
