const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

/// Machine-word size
const MAX_BITS = 63;

// pub const Options = struct {
//     /// At what point does the algorithm give up. A threshold of
//     /// `0.0` requires a perfect match, `1.0` would match anything.
//     threshold: f64 = 0,
//     location: usize = 0,
//     distance: usize = 100,
// };

const Alphabet = struct {};

// pub const PatternA = struct {
//     length: usize,
//     masks: std.AutoHashMap(u8, usize),

//     pub fn init(pattern: []const u8) !Pattern {
//         if (pattern.len == 0 or pattern.len >= MAX_BITS) {
//             return error.InvalidPattern;
//         }

//         var length: usize = 0;
//         var masks = std.AutoHashMap(u8, usize).init(std.heap.c_allocator);

//         var i: usize = 0;
//         for (pattern) |ch| {
//             if (masks.get(ch)) |mask| {
//                 masks.put(ch, mask & (1 << i));
//             } else {
//                 masks.put(ch, !(1 << i));
//             }

//             length += 1;
//             i += 1;
//         }

//         return Pattern{ .length = length, .masks = masks };
//     }

//     pub fn deinit(self: *Pattern) void {
//         self.masks.deinit();
//     }
// };

// pub fn levenstein(mask: usize, pattern_length: usize, max_distance: usize) !void {
//     _ = max_distance;
//     _ = pattern_length;
//     _ = mask;
// }

pub const Pattern = CustomPattern(u8, 63);

pub fn CustomPattern(
    comptime T: type,
    comptime max_pattern_length: comptime_int,
) type {
    assert(@typeInfo(T) == .Int);

    const Int = std.meta.Int(.unsigned, max_pattern_length + 1);
    const Log2Int = std.meta.Int(.unsigned, std.math.log2(max_pattern_length + 1));
    const possible_values = std.math.maxInt(T) - std.math.minInt(T) + 1;

    const one: Int = 1;

    return struct {
        const Self = @This();
        const Options = struct {
            case_sensitive: bool = true,
        };

        mask: [possible_values]Int,
        pattern: []const u8,
        options: Options,

        pub fn init(pattern: []const u8, options: Options) Self {
            assert(pattern.len <= max_pattern_length);
            var pattern_mask = [_]Int{std.math.maxInt(Int)} ** possible_values;

            for (pattern, 0..) |_x, i| {
                const x = if (options.case_sensitive) _x else std.ascii.toLower(_x);
                pattern_mask[x] &= ~(one << @as(Log2Int, @intCast(i)));
            }

            return Self{
                .mask = pattern_mask,
                .pattern = pattern,
                .options = options,
            };
        }

        pub fn findExact(self: *const Self, text: []const T) ?usize {
            const len = @as(Log2Int, @intCast(self.pattern.len));
            if (len == 0) return 0;

            var R: Int = ~one;
            for (text, 0..) |_x, i| {
                const x = if (self.options.case_sensitive) _x else std.ascii.toLower(_x);
                R |= self.mask[x];
                R <<= 1;

                if ((R & (one << len)) == 0) {
                    return if (i < len) 0 else i - len + 1;
                }
            }

            return null;
        }

        /// Score the match from 0 (no match) to 1 (exact match)
        pub fn matchExact(self: *const Self, text: []const u8) f64 {
            if (self.findExact(text)) |position| {
                return @as(f64, @floatFromInt(text.len - position)) / @as(f64, @floatFromInt(text.len)) - 0.2;
            }

            return 0.0;
        }
    };
}

test "blank" {
    var pattern = Pattern.init("", .{});
    try testing.expectEqual(pattern.findExact("zig"), 0);
    try testing.expectEqual(pattern.findExact(""), 0);
    try testing.expectEqual(pattern.findExact("lang"), 0);
}

test "short" {
    var pattern = Pattern.init("a", .{});
    try testing.expectEqual(pattern.findExact("zig"), null);
    try testing.expectEqual(pattern.findExact("abc"), 0);
    try testing.expectEqual(pattern.findExact("lang"), 1);
}

test "simple case insensitive" {
    var pattern = Pattern.init("a", .{ .case_sensitive = false });
    try testing.expectEqual(pattern.findExact("the quick brown fox jumps over the LAZY dog"), 36);
    try testing.expectEqual(pattern.findExact("zAg"), 1);
    try testing.expectEqual(pattern.findExact("abc"), 0);
    try testing.expectEqual(pattern.findExact("lang"), 1);
}

test "complex case insensitive" {
    var pattern = Pattern.init("I love SeaRches", .{ .case_sensitive = false });
    try testing.expectEqual(pattern.findExact("i like searches, in fact I LOVe SEarcHes"), 25);
    try testing.expectEqual(pattern.findExact("I love search"), null);
    try testing.expectEqual(pattern.findExact("abc"), null);
}
