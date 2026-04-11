const limine = @import("../boot/limine.zig");
const hhdm = @import("hhdm.zig");

const PAGE_SIZE: u64 = 4096;

var g_memmap: ?*const limine.MemmapResponse = null;
var g_region_index: usize = 0;
var g_next_page: u64 = 0;
var g_region_end: u64 = 0;

fn alignUp(value: u64, alignment: u64) u64 {
    return (value + alignment - 1) & ~(alignment - 1);
}

fn algignDown(value: u64, alignment: u64) u64 {
    return value & ~(alignment - 1);    
}

pub fn init(memmap: *const limine.MemmapResponse) void {
    g_memmap = memmap;
    g_region_index = 0;
    g_next_page = 0;
    g_region_end = 0;
}

fn advanceRegion() bool {
    const memmap = g_memmap orelse return false;

    while(g_region_index < memmap.entry_count) {
        const entry = memmap.entries[g_region_index];
        g_region_index += 1;

        if (entry.type != limine.MEMMAP_USABLE) continue;

        const start = alignUp(entry.base, PAGE_SIZE);
        const end = algignDown(entry.base + entry.length, PAGE_SIZE);

        if (end <= start) continue;

        g_next_page = start;
        g_region_end = end;
        return true;
    }

    return false;
}

pub fn allocPage() ?*align(4096) u8 {
    while (true) {
        if (g_next_page == 0 or g_next_page >= g_region_end) {
            if (!advanceRegion()) return null;
        }

        const phys_addr = g_next_page;
        g_next_page += PAGE_SIZE;

        const virt_addr = hhdm.physToVirt(phys_addr);
        return @as(*align(4096) u8, @ptrFromInt(virt_addr));
    }
}
