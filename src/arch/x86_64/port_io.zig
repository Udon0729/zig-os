pub inline fn out8(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        :   [value] "{al}" (value),
            [port] "{dx}" (port),
        :   .{ .memory = true }
    );
}

pub inline fn in8(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        :   [result] "={al}" (-> u8),
        :   [port] "{dx}" (port),
        :   .{ .memory = true }
    );
}

pub inline fn haltLoop() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}
