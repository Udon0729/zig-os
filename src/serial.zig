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

pub fn writeByte(byte: u8) void {
    while (!txReady()) {}
    io.out8(g_base + 0, byte);
}

pub fn writeString(msg: []const u8) void {
    for (msg) |c| {
        if (c == 0x0A) {
            writeByte(0x0D);
        }
        writeByte(c);
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
