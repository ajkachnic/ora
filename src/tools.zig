const std = @import("std");
const xev = @import("xev");

const Pattern = @import("search.zig").Pattern;

const application = @import("tools/application.zig");

pub const Candidate = struct {
    text: []const u8,
    action: []const u8,
    score: f64,
};

pub const Launcher = struct {
    const Application = struct {
        name: []const u8,
        command: []const u8,
    };

    ready: bool = false,
    applications: []const application.Application = &.{},
    job: *application.Job = undefined,
    completion: xev.Completion = undefined,

    // const applications: []const Application = &.{
    //     .{ .name = "Visual Studio Code", .command = "code" },
    //     .{ .name = "Alacritty", .command = "alacritty" },
    //     .{ .name = "Chromium", .command = "chromium" },
    // };

    fn callback(s: ?*Launcher, l: *xev.Loop, c: *xev.Completion, r: xev.ReadError!void) xev.CallbackAction {
        std.debug.print("callback!", .{});
        r catch {};
        if (s) |self| {
            _ = c;
            _ = l;
            self.applications = self.job.results;
        }
        return .disarm;
    }

    pub fn runTasks(self: *Launcher, loop: *xev.Loop, pool: *xev.ThreadPool) !void {
        self.job = try application.indexApplications(std.heap.c_allocator, pool);

        self.job.wg.wait(loop, &self.completion, Launcher, self, callback);
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
