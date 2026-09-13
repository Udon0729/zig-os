const std = @import("std");
const tar = @import("tar.zig");

pub const max_entries = 32;
pub const max_path = 256;
pub const Error = tar.Error || error{ InvalidPath, TooManyEntries, DuplicatePath, MissingParent, InvalidEntry };

// Root-relative canonical paths; no allocation and no escape above root.
pub fn normalize(path: []const u8, buffer: []u8) Error![]const u8 {
    var length: usize = 0;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (length == 0) return error.InvalidPath;
            length = std.mem.lastIndexOfScalar(u8, buffer[0..length], '/') orelse 0;
            continue;
        }
        if (std.mem.indexOfScalar(u8, part, 0) != null) return error.InvalidPath;
        const separator: usize = if (length > 0) 1 else 0;
        if (part.len + separator > buffer.len - length) return error.NameTooLong;
        if (separator != 0) {
            buffer[length] = '/';
            length += 1;
        }
        @memcpy(buffer[length..][0..part.len], part);
        length += part.len;
    }
    return buffer[0..length];
}

pub const Entry = struct {
    path: [max_path]u8 = undefined,
    path_len: usize = 0,
    data: []const u8 = &.{},
    is_dir: bool = true,

    pub fn name(self: *const Entry) []const u8 {
        return self.path[0..self.path_len];
    }
};

pub const Rootfs = struct {
    entries: [max_entries]Entry = undefined,
    count: usize = 0,
    root: Entry = .{},

    // File data borrows the archive; its storage must outlive this index.
    pub fn init(self: *Rootfs, archive: []const u8) Error!void {
        self.count = 0;
        errdefer self.count = 0;
        var iterator = tar.Iterator{ .archive = archive };
        while (try iterator.next()) |item| {
            if (!item.isDirectory() and !item.isRegularFile()) continue;
            var raw: [max_path]u8 = undefined;
            var entry: Entry = .{ .data = item.data, .is_dir = item.isDirectory() };
            const path = try normalize(try item.name(&raw), &entry.path);
            entry.path_len = path.len;
            if (path.len == 0) {
                if (!entry.is_dir) return error.InvalidEntry;
                continue;
            }
            if (self.find(path) != null) return error.DuplicatePath;
            if (self.count == max_entries) return error.TooManyEntries;
            self.entries[self.count] = entry;
            self.count += 1;
        }
        for (self.entries[0..self.count]) |*entry| {
            const parent = self.find(parentPath(entry.name())) orelse return error.MissingParent;
            if (!parent.is_dir) return error.MissingParent;
        }
    }

    pub fn find(self: *const Rootfs, canonical: []const u8) ?*const Entry {
        if (canonical.len == 0) return &self.root;
        for (self.entries[0..self.count]) |*entry| {
            if (std.mem.eql(u8, entry.name(), canonical)) return entry;
        }
        return null;
    }
};

pub fn parentPath(path: []const u8) []const u8 {
    return path[0 .. std.mem.lastIndexOfScalar(u8, path, '/') orelse 0];
}
