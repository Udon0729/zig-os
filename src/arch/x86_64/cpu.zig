extern fn cpu_lidt(limit: u16, base: u64) void;
extern fn cpu_lgdt(limit: u16, base: u64) void;

pub inline fn cli() void {
    asm volatile ("cli");
}

pub inline fn sti() void {
    asm volatile ("sti");
}

pub inline fn hlt() void {
    asm volatile ("hlt");
}

pub inline fn haltLoop() noreturn {
    while (true) {
        hlt();
    }
}

pub inline fn lidt(limit: u16, base: u64) void {
    cpu_lidt(limit, base);
}

pub inline fn lgdt(limit: u16, base: u64) void {
    cpu_lgdt(limit, base);
}

pub inline fn readCr2() u64 {
    return asm volatile ("mov %%cr2, %[value]"
        : [value] "=r" (-> u64),
        :
        : .{}
    );
}
