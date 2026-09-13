const std = @import("std");

pub const block_size = 512;
pub const Error = error{ TruncatedArchive, InvalidHeader, InvalidChecksum, InvalidNumber, SizeOverflow, NameTooLong };

pub const Entry = struct {
    header: []const u8,
    data: []const u8,

    pub fn isDirectory(self: Entry) bool {
        return self.header[156] == '5';
    }

    pub fn isRegularFile(self: Entry) bool {
        return self.header[156] == '0' or self.header[156] == 0;
    }

    // The returned name lives in the caller's buffer, never in a local array.
    pub fn name(self: Entry, buffer: []u8) Error![]const u8 {
        const leaf = std.mem.sliceTo(self.header[0..100], 0);
        const prefix = std.mem.sliceTo(self.header[345..500], 0);
        return if (prefix.len == 0)
            std.fmt.bufPrint(buffer, "{s}", .{leaf}) catch error.NameTooLong
        else
            std.fmt.bufPrint(buffer, "{s}/{s}", .{ prefix, leaf }) catch error.NameTooLong;
    }
};

fn octal(bytes: []const u8) Error!usize {
    const digits = std.mem.trim(u8, bytes, " \x00");
    if (digits.len == 0) return error.InvalidNumber;
    var value: usize = 0;
    for (digits) |digit| {
        if (digit < '0' or digit > '7') return error.InvalidNumber;
        value = std.math.mul(usize, value, 8) catch return error.SizeOverflow;
        value = std.math.add(usize, value, digit - '0') catch return error.SizeOverflow;
    }
    return value;
}

pub const Iterator = struct {
    archive: []const u8,
    offset: usize = 0,
    ended: bool = false,

    pub fn next(self: *Iterator) Error!?Entry {
        if (self.ended) return null;
        const remaining = self.archive.len - self.offset;
        if (remaining < block_size) return error.TruncatedArchive;
        const header = self.archive[self.offset..][0..block_size];
        if (std.mem.allEqual(u8, header, 0)) {
            if (remaining < 2 * block_size or !std.mem.allEqual(u8, self.archive[self.offset + block_size ..][0..block_size], 0)) return error.TruncatedArchive;
            self.ended = true;
            return null;
        }
        if (!std.mem.eql(u8, header[257..263], "ustar\x00") or !std.mem.eql(u8, header[263..265], "00")) return error.InvalidHeader;
        var checksum: usize = 0;
        for (header, 0..) |byte, i| checksum += if (i >= 148 and i < 156) @as(u8, ' ') else byte;
        if (checksum != try octal(header[148..156])) return error.InvalidChecksum;
        const size = try octal(header[124..136]);
        const padded = (std.math.add(usize, size, block_size - 1) catch return error.SizeOverflow) & ~@as(usize, block_size - 1);
        if (padded > remaining - block_size) return error.TruncatedArchive;
        const data = self.archive[self.offset + block_size ..][0..size];
        self.offset += block_size + padded;
        return .{ .header = header, .data = data };
    }
};
