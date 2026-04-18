const cpu = @import("cpu.zig");

pub const KERNEL_CODE_SELECTOR: u16 = 0x08;
pub const KERNEL_DATA_SELECTOR: u16 = 0x10;

const GDT = [3]u64{
    0x0000000000000000, // null
    0x00af9a000000ffff, // kernel code
    0x00af92000000ffff, // kernel data
};

extern fn gdt_flush(code_selector: u16, data_selector: u16) void;

pub fn loadTable() void {
    cpu.lgdt(@sizeOf(@TypeOf(GDT)) - 1, @intFromPtr(&GDT));
}

pub fn reloadSegments() void {
    gdt_flush(KERNEL_CODE_SELECTOR, KERNEL_DATA_SELECTOR);
}

pub fn init() void {
    loadTable();
    reloadSegments();
}
