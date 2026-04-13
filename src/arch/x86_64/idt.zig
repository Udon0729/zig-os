const std = @import("std");
const cpu = @import("cpu.zig");
const gdt = @import("gdt.zig");

pub const IdtEntry = packed struct {
    offset_low: u16,
    selector: u16,
    ist: u8,
    type_attr: u8,
    offset_mid: u16,
    offset_high: u32,
    zero: u32,
};

pub const INTERRUPT_GATE: u8 = 0x8e;
pub const EXCEPTION_CONST: usize = 32;

var idt: [256]IdtEntry = [_]IdtEntry{emptyEntry()} ** 256;

const idtr = cpu.Idtr{
    .limit = @sizeOf(@TypeOf(idt)) - 1,
    .base = @intFromPtr(&idt),
};

extern const isr_stub_table: [EXCEPTION_CONST]usize;

fn emptyEntry() IdtEntry {
    return .{
        .offset_low = 0,
        .selector = 0,
        .ist = 0,
        .type_attr = 0,
        .offset_mid = 0,
        .offset_high = 0,
        .zero = 0,
    };
}

pub fn setGate(vector: u8, handler: usize, type_attr: u8) void {
    idt[vector] = .{
        .offset_low = @truncate(handler),
        .selector = gdt.KERNEL_CODE_SELECTOR,
        .ist = 0,
        .type_attr = type_attr,
        .offset_mid = @truncate(handler >> 16),
        .offset_high = @truncate(handler >> 32),
        .zero = 0,
    };
}

pub fn init() void {
    var i: usize = 0;
    while (i < EXCEPTION_CONST) : (i += 1) {
        setGate(@intCast(i), isr_stub_table[i], INTERRUPT_GATE);
    }
    cpu.lidt(&idtr);
}
