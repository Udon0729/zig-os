const cpu = @import("cpu.zig")

pub const KERNEL_CODE_SELECTOR: u16 = 0x08;
pub const KERNEL_DATA_SELECTOR: u16 = 0x10;

const GDT = [3]u64{
    0x0000000000000000, // null
    0x00af9a000000ffff, // kernel code
    0x00af92000000ffff, // kernel data
};

const gdtr = cpu.Gdtr{
    .limit = @sizeOf(@TypeOf(GDT)) - 1,
    .base = @intFromPtr(&GDT),
};

extern fn gdt_flush(code_selector: u16, data_selector: u16) callconv(.C) void;

pub fn init() void {
    cpu.lgdt(&gdtr);
    gdt_flush(KERNEL_CODE_SELECTOR, KERNEL_DATA_SELECTOR);
}
