var g_offset: u64 = 0;

pub fn init(offset: u64) void {
    g_offset = offset;
}

pub fn physToVirt(addr: u64) u64 {
    return addr + g_offset;
}

pub fn virtToPhys(addr: u64) u64 {
    return addr - g_offset;
}
