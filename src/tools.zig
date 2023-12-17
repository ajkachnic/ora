const std = @import("std");
const xev = @import("xev");

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
    // job: *application.Job = undefined,
    job: *Task.Job(void, []application.Application) = undefined,
    // completion: xev.Completion = undefined,

    fn callback(self: *Launcher, output: []application.Application) void {
        self.applications = output;
    }

    pub fn runTasks(
        self: *Launcher,
    ) !void {
        self.job = try Task.spawnBlocking(
            std.heap.c_allocator,
            void,
            []application.Application,
            application._indexApplications,
            {},
        );

        try self.job.wait(*Launcher, self, &callback);
        // self.job = try application.indexApplications(std.heap.c_allocator, pool);

        // self.job.wg.wait(loop, &self.completion, Launcher, self, callback);
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
