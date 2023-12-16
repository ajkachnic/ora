const std = @import("std");
const xev = @import("xev");

const Pattern = @import("search.zig").Pattern;

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

    const applications: []const Application = &.{
        .{ .name = "Visual Studio Code", .command = "code" },
        .{ .name = "Alacritty", .command = "alacritty" },
        .{ .name = "Chromium", .command = "chromium" },
    };

    pub fn generate(_: *Launcher, query: []const u8, candidates: *std.ArrayList(Candidate)) !void {
        const q = if (query.len > 63) query[0..63] else query;
        const pattern = Pattern.init(q, .{ .case_sensitive = false });
        var apps: [3]Application = undefined;

        std.mem.copyForwards(Application, &apps, applications);

        for (apps) |app| {
            try candidates.append(.{
                .text = app.name,
                .action = app.command,
                .score = pattern.matchExact(app.name),
            });
        }
    }
};

/// Search through files
pub const Finder = struct {};
