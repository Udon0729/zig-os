const io = @import("arch/x86_64/port_io.zig");

pub const COM1: u16 = 0x3f8;

var g_base: u16 = COM1;

pub fn init(base: u16) void {
    g_base = base;

    io.out8(base + 1, 0x00); // disable interrupts
    io.out8(base + 3, 0x80); // enable DLAB
    io.out8(base + 0, 0x03); // divisor low  = 3
    io.out8(base + 1, 0x00); // divisor high = 0
    io.out8(base + 3, 0x03); // 8 bits, no parity, one stop bit
    io.out8(base + 2, 0xC7); // enable FIFO, clear queues
    io.out8(base + 4, 0x0B); // IRQs enabled, RTS/DSR set
}

fn txReady() bool {
    return (io.in8(g_base + 5) & 0x20) != 0;
}

fn rxReady() bool {
    return (io.in8(g_base + 5) & 0x01) != 0;
}

pub fn readByte() u8 {
    while (!rxReady()) {}
    return io.in8(g_base + 0);
}

var skip_lf = false;

pub fn readLine(buf: []u8) error{LineTooLong}!usize {
    var length: usize = 0;
    var overflow = false;
    while (true) {
        const c = readByte();
        if (skip_lf) {
            skip_lf = false;
            if (c == '\n') continue;
        }
        if (c == '\r' or c == '\n') {
            skip_lf = c == '\r';
            writeLine("");
            if (overflow) return error.LineTooLong;
            return length;
        }
        // Drain an oversized line completely; never execute its truncated prefix.
        if (overflow) continue;
        if (c == 0x08 or c == 0x7f) {
            if (length > 0) {
                length -= 1;
                writeString("\x08 \x08");
            }
        } else if ((c >= 0x20 and c <= 0x7e) or c == '\t') {
            if (length == buf.len) {
                overflow = true;
                continue;
            }
            buf[length] = c;
            length += 1;
            writeByte(c);
        }
    }
}

pub fn writeByte(byte: u8) void {
    while (!txReady()) {}
    io.out8(g_base + 0, byte);
}

var last_was_cr = false;

pub fn writeString(msg: []const u8) void {
    for (msg) |c| {
        if (c == 0x0A and !last_was_cr) {
            writeByte(0x0D);
        }
        writeByte(c);
        last_was_cr = c == '\r';
    }
}

pub fn writeLine(msg: []const u8) void {
    writeString(msg);
    writeString("\r\n");
}

pub fn writeHex64(value: u64) void {
    const digits = "0123456789abcdef";
    var shift: u6 = 60;

    while (true) {
        const nibble: u4 = @truncate(value >> shift);
        writeByte(digits[nibble]);

        if (shift == 0) break;
        shift -= 4;
    }
}

pub fn writeDecU64(value: u64) void {
    if (value == 0) {
        writeByte('0');
        return;
    }

    var buf: [20]u8 = undefined;
    var i: usize = buf.len;
    var n = value;

    while (n > 0) {
        i -= 1;
        buf[i] = '0' + @as(u8, @intCast(n % 10));
        n /= 10;
    }

    writeString(buf[i..]);
}
