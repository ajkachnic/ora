const std = @import("std");
const xev = @import("xev");

const main = @import("main.zig");

const Pattern = @import("search.zig").Pattern;

const application = @import("tools/application.zig");
const Task = @import("Task.zig");

pub const Candidate = struct {
    text: []const u8,
    action: []const u8,
    score: f64,
};

pub const Launcher = struct {
    ready: bool = false,
    applications: []const application.Application = &.{},
    job: *Task.Job(std.mem.Allocator, []application.Application) = undefined,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Launcher {
        return Launcher{ .allocator = allocator };
    }

    fn callback(self: *Launcher, output: []application.Application) void {
        self.applications = output;
    }

    pub fn deinit(self: *Launcher) void {
        for (self.applications) |app| {
            app.deinit(self.allocator);
        }

        self.allocator.free(self.applications);
    }

    pub fn runTasks(
        self: *Launcher,
    ) !void {
        self.job = try Task.spawnBlocking(
            self.allocator,
            std.mem.Allocator,
            []application.Application,
            application.indexApplications,
            self.allocator,
        );

        try self.job.wait(*Launcher, self, &callback);
    }

    pub fn generate(self: *Launcher, query: []const u8, candidates: *std.ArrayList(Candidate)) !void {
        const q = if (query.len > 63) query[0..63] else query;
        const pattern = Pattern.init(q, .{ .case_sensitive = false });

        for (self.applications) |app| {
            try candidates.append(.{
                .text = app.name,
                .action = app.exec,
                .score = pattern.matchExact(app.name),
            });
        }
    }
};

/// Search through files
pub const Finder = struct {};
