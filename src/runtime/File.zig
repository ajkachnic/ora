//! High-level wrapper around xev File implementation
const std = @import("std");
const xev = @import("xev");
const runtime = @import("runtime.zig");

const File = @This();

inner: std.fs.File,

pub fn open(path: []const u8, flags: std.fs.File.OpenFlags) std.fs.File.OpenError!File {
    const fs = try std.fs.openFileAbsolute(path, flags);
    return .{ .inner = fs };
}

const ReadContext = struct {
    path: []const u8,
    max_bytes: usize,
    allocator: std.mem.Allocator,
};

pub const ReadJob = runtime.Task.Job(ReadContext, []u8);

pub fn readAll(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) !*ReadJob {
    const worker = struct {
        fn callback(ctx: ReadContext) []u8 {
            var file = File.open(ctx.path, .{}) catch |err| {
                std.log.err("readAll() - {}", .{err});
                return &.{};
            };
            std.log.debug("readAll() - starting reading", .{});
            const result = file.inner.readToEndAlloc(ctx.allocator, ctx.max_bytes) catch |err| {
                std.log.err("readAll() - {}", .{err});
                return &.{};
            };
            std.log.debug("readAll() - completed read", .{});
            return result;
        }
    }.callback;

    return try runtime.Task.spawnBlocking(allocator, ReadContext, []u8, worker, .{
        .path = path,
        .max_bytes = max_bytes,
        .allocator = allocator,
    });
}

// pub fn readAll(self: *File, allocator: std.mem.Allocator, max_bytes: usize) !*ReadJob {
//     const worker = struct {
//         fn callback(ctx: ReadContext) []u8 {
//             std.log.debug("readAll() - starting reading", .{});
//             const result = ctx.self.inner.readToEndAlloc(ctx.allocator, ctx.max_bytes) catch |err| {
//                 std.log.err("readAll() - {}", .{err});
//                 return &.{};
//             };
//             std.log.debug("readAll() - completed read", .{});
//             return result;
//         }
//     }.callback;

//     return try runtime.Task.spawnBlocking(allocator, ReadContext, []u8, worker, .{
//         .self = self,
//         .max_bytes = max_bytes,
//         .allocator = allocator,
//     });
// }
