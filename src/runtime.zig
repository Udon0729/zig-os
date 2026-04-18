export fn memcpy(dest: [*]u8, src: [*]const u8, n: usize) [*]u8 {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dest[i] = src[i];
    }
    return dest;
}

export fn memmove(dest: [*]u8, src: [*]const u8, n: usize) [*]u8 {
    const dest_addr = @intFromPtr(dest);
    const src_addr = @intFromPtr(src);

    if (dest_addr == src_addr or n == 0) {
        return dest;
    }

    if (dest_addr < src_addr) {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            dest[i] = src[i];
        }
    } else {
        var i = n;
        while (i > 0) {
            i -= 1;
            dest[i] = src[i];
        }
    }

    return dest;
}

export fn memset(dest: [*]u8, value: c_int, n: usize) [*]u8 {
    const byte: u8 = @intCast(value & 0xff);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        dest[i] = byte;
    }

    return dest;
}
