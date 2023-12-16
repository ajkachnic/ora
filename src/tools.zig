const std = @import("std");
const xev = @import("xev");

const Pattern = @import("search.zig").Pattern;

pub const Candidate = struct {
    text: []const u8,
    action: []const u8,
    score: f64,
};

fn levenstein(a: []const u8, b: []const u8) f64 {
    if (b.len == 0) return @floatFromInt(a.len);
    if (a.len == 0) return @floatFromInt(b.len);

    if (a[0] == b[0]) return levenstein(a[1..], b[1..]);

    return 1 + @min(
        @min(
            levenstein(a[1..], b),
            levenstein(a, b[1..]),
        ),
        levenstein(a[1..], b[1..]),
    );
    // var matrix = .{.{0} ** tar.len} ** src.len;

    // var i: usize = 1;
    // while (i < src.len + 1) : (i += 1) {
    //     matrix[i][0] = i;
    // }

    // i = 1;
    // while (i < tar.len + 1) : (i += 1) {
    //     matrix[0][1] = i;
    // }

    // i = 0;
    // for (src) |s| {
    //     var j: usize = 0;
    //     for (tar) |t| {
    //         const substitutionCost = if (s == t) 0 else 1;
    //         const minimum = @min(
    //             matrix[i][j + 1] + 1,
    //             @min(
    //                 matrix[i + 1][j] + 1,
    //                 matrix[i][j] + substitutionCost,
    //             ),
    //         );

    //         matrix[i + 1][j + 1] = minimum;
    //         j += 1;
    //     }
    //     i += 1;
    // }

    // return matrix[src.len][tar.len];
}

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
