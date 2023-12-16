//! A single-line editor implementation.
//!
//! Everything here is for a 1 dimensional editor (only a single line).
//! This makes things like cursor tracking significantly easier, and
//! allows us to get away with less efficient text representations
const std = @import("std");

/// The actual text of the buffer, represented as a dynamic array
///
/// Other data structures could be faster (ex rope or gap buffer), but
/// the performance improvement isn't high enough to justify the added
/// complexity of that implementation
buffer: std.ArrayList(u8),

/// Cursor position
cursor: usize = 0,

dirty: bool = true,

const Self = @This();

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{ .buffer = std.ArrayList(u8).init(allocator) };
}

pub fn from(allocator: std.mem.Allocator, default: []const u8) !Self {
    var buffer = std.ArrayList(u8).init(allocator);
    try buffer.appendSlice(default);

    return Self{ .buffer = buffer, .cursor = default.len };
}

pub fn deinit(self: *Self) void {
    self.buffer.deinit();
}

pub fn insertChar(self: *Self, ch: u8) !void {
    try self.buffer.insert(self.cursor, ch);
    self.cursor += 1;
    self.dirty = true;
}

pub fn remove(self: *Self, idx: usize) void {
    if (self.cursor == self.buffer.items.len) {
        self.cursor -= 1;
    }

    _ = self.buffer.orderedRemove(idx);
    self.dirty = true;
}

pub fn removeBeforeCursor(self: *Self) void {
    if (self.cursor > 0) {
        self.remove(self.cursor - 1);
    }
    self.dirty = true;
}

/// Fix the buffer from an invalid state (usually cursor position)
pub fn normalize(self: *Self) void {
    if (self.cursor > self.buffer.items.len) {
        self.cursor = self.buffer.items.len;
        self.dirty = true;
    }
}

pub const CursorMotion = enum { left, right };

pub fn moveCursor(self: *Self, m: CursorMotion) void {
    self.dirty = true;
    switch (m) {
        .left => if (self.cursor > 0) {
            self.cursor -= 1;
        },
        .right => if (self.cursor < self.buffer.items.len) {
            self.cursor += 1;
        },
    }
}
