pub const Gdtr = packed struct {
    limit: u16,
    base: u64,
};

pub const Idtr = packed struct {
    limit: u16,
    base: u64,
};

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

pub inline fn lidt(idtr: *const Idtr) void {
    asm volatile ("lidt (%[ptr])"
        :
        : [ptr] "r" (idtr),
        : .{ .memory = true }
    );
}

pub inline fn lgdt(gdtr: *const Gdtr) void {
    asm volatile ("lgdt (%[ptr])"
        :
        : [ptr] "r" (gdtr),
        : .{ .memory = true }
    );
}

pub inline fn readCr2() u64 {
    return asm volatile ("mov %%cr2, %[value]"
        : [value] "=r" (-> u64),
        :
        : .{}
    );
}

