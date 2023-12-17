const std = @import("std");
const xev = @import("xev");

const Task = xev.ThreadPool.Task;

pub const Job = struct {
    task: Task,
    results: []Application = &.{},
    allocator: std.mem.Allocator,
    wg: xev.Async,
    done: bool = false,
};

// pub fn indexApplications(
//     allocator: std.mem.Allocator,
//     pool: *xev.ThreadPool,
// ) !*Job {
//     const wg = try xev.Async.init();
//     const task = Task{ .callback = &wrapper };

//     var job = try allocator.create(Job);
//     job.* = Job{
//         .task = task,
//         .allocator = allocator,
//         .wg = wg,
//     };

//     const batch = xev.ThreadPool.Batch.from(&job.task);
//     pool.schedule(batch);

//     return job;
// }

// fn wrapper(task: *Task) void {
//     var job = @fieldParentPtr(Job, "task", task);

//     job.results = _indexApplications() catch |err| {
//         std.log.err("failed to index: {}", .{err});
//         return;
//     };
//     std.log.info("completed search", .{});
//     job.done = true;
//     job.wg.notify() catch |err| {
//         std.log.err("failed to notify: {}", .{err});
//     };
// }

pub fn _indexApplications(_: void) []Application {
    const allocator = std.heap.c_allocator;
    const data_dirs = std.os.getenv("XDG_DATA_DIRS") orelse {
        std.log.warn("couldn't find XDG_DATA_DIRS", .{});
        return &.{};
    };
    var applications = std.ArrayList(Application).init(allocator);
    var iter = std.mem.splitScalar(u8, data_dirs, ':');
    var map = std.StringHashMap(Icon).init(allocator);
    defer map.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    while (iter.next()) |path| {
        getApplications(allocator, path, &applications) catch {};
        resolveIcons(arena.allocator(), path, &map) catch {};
    }

    for (applications.items) |*app| {
        app.*.icon = if (map.get(app.*.icon)) |i| i.path else "";
    }

    return applications.toOwnedSlice() catch {
        @panic("out of memory");
    };
}

pub const DesiredSize = 32;

pub const Icon = struct {
    size: u16,
    path: []const u8,
};

pub fn resolveIcons(
    allocator: std.mem.Allocator,
    path: []const u8,
    map: *std.StringHashMap(Icon),
) !void {
    const parent = try std.fs.openDirAbsolute(path, .{});
    const icons = try parent.openDir("icons", .{ .iterate = true });

    var walker = try icons.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;

        const extension = std.fs.path.extension(entry.path);
        if (!std.mem.eql(u8, extension, ".png")) continue;

        const stem = std.fs.path.stem(entry.basename);
        const fullPath = try std.fs.path.resolve(
            allocator,

            &.{ path, "icons", entry.path },
        );
        const size = try getSize(fullPath);

        if (map.get(stem)) |v| {
            if (v.size < DesiredSize and size > v.size) {
                try map.put(try allocator.dupe(u8, stem), Icon{
                    .size = size,
                    .path = fullPath,
                });
            }
        } else {
            try map.put(try allocator.dupe(u8, stem), Icon{
                .size = size,
                .path = fullPath,
            });
        }
    }
}

fn getSize(path: []const u8) !u16 {
    const parent = std.fs.path.dirname(path);
    if (parent) |p| {
        if (std.ascii.isDigit(std.fs.path.basename(p)[0])) {
            return convertSize(std.fs.path.basename(p));
        } else if (std.fs.path.dirname(p)) |buffer| {
            const base = std.fs.path.basename(buffer);
            return convertSize(base);
        }
    }
    return 0;
}

fn convertSize(base: []const u8) !u16 {
    var split = std.mem.splitScalar(u8, base, 'x');
    const size = split.next();

    if (size == null) return error.EmptyDirectory;
    return try std.fmt.parseUnsigned(u16, size.?, 10);
}

pub fn getApplications(allocator: std.mem.Allocator, path: []const u8, list: *std.ArrayList(Application)) !void {
    const parent = try std.fs.openDirAbsolute(path, .{});
    const applications = try parent.openDir("applications", .{ .iterate = true });

    var walker = try applications.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file or entry.kind == .sym_link) {
            const extension = std.fs.path.extension(entry.path);
            if (!std.mem.eql(u8, extension, ".desktop")) continue;

            if (parseApplication(allocator, applications, entry.path) catch continue) |application| {
                try list.append(application);
            }
        }
    }
}

pub const Application = struct {
    name: []const u8 = "",
    exec: []const u8 = "",
    icon: []const u8 = "",
};

// crude parser for the .desktop format
fn parseApplication(allocator: std.mem.Allocator, dir: std.fs.Dir, path: []const u8) !?Application {
    var file = try dir.openFile(path, .{});
    const contents = try file.readToEndAlloc(
        allocator,
        1024 * 1024 * 1024,
    );

    var application = Application{};
    if (std.mem.indexOf(u8, contents, "[Desktop Entry]")) |start| {
        var lines = std.mem.splitScalar(u8, contents[start..], '\n');

        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "#")) continue;
            // if (std.mem.startsWith(u8, line, "[")) break;

            var split = std.mem.splitScalar(u8, line, '=');

            const key = split.next();
            const value = split.next();

            if (key == null or value == null) continue;

            if (std.mem.eql(u8, key.?, "Name")) {
                application.name = value.?;
            } else if (std.mem.eql(u8, key.?, "Exec")) {
                application.exec = value.?;
            } else if (std.mem.eql(u8, key.?, "Icon")) {
                application.icon = value.?;
            } else if (std.mem.eql(u8, key.?, "Type")) {
                if (!std.mem.eql(u8, std.mem.trim(
                    u8,
                    value.?,
                    " \r",
                ), "Application")) return null;
            } else if (std.mem.eql(u8, key.?, "NoDisplay")) {
                if (std.mem.eql(u8, value.?, "true")) return null;
            }
        }
    }

    const app = .{
        .name = try allocator.dupe(u8, application.name),
        .icon = try allocator.dupe(u8, application.icon),
        .exec = try allocator.dupe(u8, application.exec),
    };

    allocator.free(contents);

    return app;
}

test "parse format" {
    // try getApplications(std.heap.c_allocator, "/home/andrew/.nix-profile/share/");
    _ = _indexApplications({});
}
