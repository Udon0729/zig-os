const std = @import("std");

pub const BLOCK_SIZE: usize = 512;

/// tar ヘッダのオフセット定数（ustar フォーマット）
const OFF_NAME: usize = 0;
const OFF_MODE: usize = 100;
const OFF_UID: usize = 108;
const OFF_GID: usize = 116;
const OFF_SIZE: usize = 124;
const OFF_MTIME: usize = 136;
const OFF_CHKSUM: usize = 148;
const OFF_TYPEFLAG: usize = 156;
const OFF_LINKNAME: usize = 157;
const OFF_MAGIC: usize = 257;
const OFF_VERSION: usize = 263;
const OFF_UNAME: usize = 265;
const OFF_GNAME: usize = 297;
const OFF_DEVMAJOR: usize = 329;
const OFF_DEVMINOR: usize = 337;
const OFF_PREFIX: usize = 345;

pub fn parseHeader(data: []const u8) bool {
    if (data.len < BLOCK_SIZE) return false;
    // magic at offset 257: "ustar\0"
    const magic_ok = std.mem.eql(u8, data[OFF_MAGIC..OFF_MAGIC+5], "ustar") and data[OFF_MAGIC+5] == 0;
    return magic_ok;
}

fn octalToUint(buf: []const u8) usize {
    var result: usize = 0;
    for (buf) |c| {
        if (c >= '0' and c <= '7') {
            result = result * 8 + (c - '0');
        }
    }
    return result;
}

fn readCStr(buf: []const u8) []const u8 {
    for (buf, 0..) |c, i| {
        if (c == 0) {
            return buf[0..i];
        }
    }
    return buf;
}

pub fn getFileSize(data: []const u8) usize {
    return octalToUint(data[OFF_SIZE..OFF_SIZE+12]);
}

pub fn getFileName(data: []const u8) []const u8 {
    const name = readCStr(data[OFF_NAME..OFF_NAME+100]);
    const prefix = readCStr(data[OFF_PREFIX..OFF_PREFIX+155]);
    if (prefix.len > 0) {
        var full: [256]u8 = undefined;
        const slice = std.fmt.bufPrint(&full, "{s}/{s}", .{prefix, name}) catch full[0..0];
        return slice;
    }
    return name;
}

pub fn getTypeFlag(data: []const u8) u8 {
    return data[OFF_TYPEFLAG];
}

pub fn isDirectory(data: []const u8) bool {
    const tf = getTypeFlag(data);
    return tf == '5' or tf == '/';
}

pub fn isRegularFile(data: []const u8) bool {
    const tf = getTypeFlag(data);
    return tf == '0' or tf == 0;
}

/// tar アーカイブを走査し、コールバックを呼ぶ
/// 戻り値: パースしたエントリ数
pub fn iterate(
    archive_ptr: [*]const u8,
    archive_len: usize,
    callback: fn (ctx: ?*anyopaque, hdr: []const u8, data: []const u8) ?bool,
    ctx: ?*anyopaque,
) usize {
    var offset: usize = 0;
    var count: usize = 0;
    while (offset + BLOCK_SIZE <= archive_len) {
        const hdr_data = archive_ptr[offset..offset + BLOCK_SIZE];
        var all_zero = true;
        for (hdr_data) |b| {
            if (b != 0) {
                all_zero = false;
                break;
            }
        }
        if (all_zero) break;

        if (parseHeader(hdr_data)) {
            count += 1;
            const file_size = getFileSize(hdr_data);
            const data_start = offset + BLOCK_SIZE;
            const data_end = data_start + file_size;
            if (data_end <= archive_len) {
                const file_data = archive_ptr[data_start..data_end];
                const should_continue = callback(ctx, hdr_data, file_data);
                if (should_continue == false) break;
            }
            offset = (data_end + BLOCK_SIZE - 1) & ~(BLOCK_SIZE - 1);
        } else {
            break;
        }
    }
    return count;
}

pub fn findFile(archive_ptr: [*]const u8, archive_len: usize, target_name: []const u8) ?[]const u8 {
    var result: ?[]const u8 = null;
    iterate(archive_ptr, archive_len, struct {
        fn callback(ctx: *?[]const u8, hdr: []const u8, data: []const u8) ?bool {
            const name = getFileName(hdr);
            if (std.mem.eql(u8, name, target_name)) {
                ctx.* = data;
                return false;
            }
            return true;
        }
    }.callback, &result);
    return result;
}