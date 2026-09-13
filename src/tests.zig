const std = @import("std");
const tar = @import("tar.zig");
const fs = @import("rootfs.zig");
const testing = std.testing;

fn checksum(header: []u8) void {
    @memset(header[148..156], ' ');
    var sum: usize = 0;
    for (header) |byte| sum += byte;
    _ = std.fmt.bufPrint(header[148..155], "{o:0>6}\x00", .{sum}) catch unreachable;
}

fn member(header: []u8, name: []const u8, prefix: []const u8, size: usize, kind: u8) void {
    @memset(header, 0);
    @memcpy(header[0..name.len], name);
    @memcpy(header[345..][0..prefix.len], prefix);
    @memcpy(header[257..265], "ustar\x0000");
    _ = std.fmt.bufPrint(header[124..136], "{o:0>11}\x00", .{size}) catch unreachable;
    header[156] = kind;
    checksum(header);
}

test "ustar prefix uses caller storage and data respects padding" {
    var archive = [_]u8{0} ** 2048;
    member(archive[0..512], "hello", "docs", 3, '0');
    @memcpy(archive[512..515], "abc");
    var iterator = tar.Iterator{ .archive = &archive };
    const entry = (try iterator.next()).?;
    var name: [256]u8 = undefined;
    try testing.expectEqualStrings("docs/hello", try entry.name(&name));
    try testing.expectEqualStrings("abc", entry.data);
    try testing.expectEqual(@as(?tar.Entry, null), try iterator.next());
    try testing.expectEqual(@as(?tar.Entry, null), try iterator.next());
}

test "reject corrupt checksum, invalid size, truncated data and terminator" {
    var archive = [_]u8{0} ** 2048;
    member(archive[0..512], "file", "", 3, '0');
    archive[0] ^= 1;
    var iterator = tar.Iterator{ .archive = &archive };
    try testing.expectError(error.InvalidChecksum, iterator.next());
    archive[124] = '9';
    checksum(archive[0..512]);
    try testing.expectError(error.InvalidNumber, iterator.next());
    member(archive[0..512], "file", "", 4096, '0');
    try testing.expectError(error.TruncatedArchive, iterator.next());
    var short = tar.Iterator{ .archive = archive[1536..] };
    try testing.expectError(error.TruncatedArchive, short.next());
}

test "path normalization and traversal bounds" {
    var buffer: [256]u8 = undefined;
    try testing.expectEqualStrings("docs/info.txt", try fs.normalize("/./docs//sub/../info.txt", &buffer));
    try testing.expectEqualStrings("", try fs.normalize("./docs/..", &buffer));
    try testing.expectError(error.InvalidPath, fs.normalize("../hello", &buffer));
    try testing.expectError(error.NameTooLong, fs.normalize("long", buffer[0..2]));
}

test "rootfs handles archive order, canonical lookup and resets on failure" {
    var archive = [_]u8{0} ** 2560;
    member(archive[0..512], "info.txt", "./docs", 3, '0');
    @memcpy(archive[512..515], "abc");
    member(archive[1024..1536], "./docs/", "", 0, '5');
    var root: fs.Rootfs = .{};
    try root.init(&archive);
    try testing.expectEqual(@as(usize, 2), root.count);
    try testing.expect(root.find("").?.is_dir);
    try testing.expectEqualStrings("abc", root.find("docs/info.txt").?.data);
    try testing.expectEqualStrings("docs", fs.parentPath("docs/info.txt"));
    // A parent directory is required, even when it appears after the file.
    member(archive[1024..1536], "./other/", "", 0, '5');
    try testing.expectError(error.MissingParent, root.init(&archive));
    try testing.expectEqual(@as(usize, 0), root.count);
}

test "duplicate paths and exhausted index are reported" {
    var archive = [_]u8{0} ** (512 * (fs.max_entries + 3));
    var name: [32]u8 = undefined;
    for (0..fs.max_entries + 1) |i| {
        const path = try std.fmt.bufPrint(&name, "file{d}", .{i});
        member(archive[i * 512 ..][0..512], path, "", 0, '0');
    }
    var root: fs.Rootfs = .{};
    try testing.expectError(error.TooManyEntries, root.init(&archive));
    member(archive[512..1024], "./file0", "", 0, '0');
    try testing.expectError(error.DuplicatePath, root.init(&archive));
    try testing.expectEqual(@as(usize, 0), root.count);
}
