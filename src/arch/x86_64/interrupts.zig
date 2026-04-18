const serial = @import("../../serial.zig");
const cpu = @import("cpu.zig");

pub const InterruptFrame = extern struct {
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rdi: u64,
    rsi: u64,
    rbp: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
    vector: u64,
    error_code: u64,
    rip: u64,
    cs: u64,
    rflags: u64,
};

pub fn init() void {
    @import("idt.zig").init();
}

fn exceptionName(vector: u64) []const u8 {
    return switch (vector) {
        0 => "Divide Error",
        1 => "Debug",
        2 => "NMI",
        3 => "Breakpoint",
        4 => "Overflow",
        5 => "BOUND Range Exceeded",
        6 => "Invalid Opcode",
        7 => "Device Not Available",
        8 => "Double Fault",
        9 => "Coprocessor Segment Overrun",
        10 => "Invalid TSS",
        11 => "Segment Not Present",
        12 => "Stack-Segment Fault",
        13 => "General Protection Fault",
        14 => "Page Fault",
        16 => "x87 Floating-Point Exception",
        17 => "Alignment Check",
        18 => "Machine Check",
        19 => "SIMD Floating-Point Exception",
        20 => "Virtualization Exception",
        21 => "Control Protection Exception",
        28 => "Hypervisor Injection Exception",
        29 => "VMM Communication Exception",
        30 => "Security Exception",
        else => "Unknown Exception",        
    };
}

export fn isr_dispatch(frame: *const InterruptFrame) void {
    serial.writeString("\r\n=== EXCEPTION ===\r\n");
    serial.writeString("vector: ");
    serial.writeDecU64(frame.vector);
    serial.writeString(" (");
    serial.writeString(exceptionName(frame.vector));
    serial.writeString(")\r\n");

    serial.writeString("error: 0x");
    serial.writeHex64(frame.error_code);
    serial.writeString("\r\n");

    serial.writeString("rip: 0x");
    serial.writeHex64(frame.rip);
    serial.writeString("\r\n");

    serial.writeString("cs: 0x");
    serial.writeHex64(frame.cs);
    serial.writeString("\r\n");

    serial.writeString("rflags: 0x");
    serial.writeHex64(frame.rflags);
    serial.writeString("\r\n");

    if (frame.vector == 14) {
        serial.writeString("cr2: 0x");
        serial.writeHex64(cpu.readCr2());
        serial.writeString("\r\n");
    }

    serial.writeString("rax: 0x");
    serial.writeHex64(frame.rax);
    serial.writeString("\r\n");

    serial.writeString("rbx: 0x");
    serial.writeHex64(frame.rbx);
    serial.writeString("\r\n");

    serial.writeString("rcx: 0x");
    serial.writeHex64(frame.rcx);
    serial.writeString("\r\n");

    serial.writeString("rdx: 0x");
    serial.writeHex64(frame.rdx);
    serial.writeString("\r\n");

    serial.writeString("system halted\r\n");
    cpu.haltLoop();
}
