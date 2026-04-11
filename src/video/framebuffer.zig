const limine = @import("../boot/limine.zig");

var g_fb: ?*const limine.Framebuffer = null;

pub fn init(raw: *const limine.Framebuffer) void {
    g_fb = raw;
}

pub fn putPixel(x: u64, y: u64, color: u32) void {
    const fb = g_fb orelse return;

    if (fb.bpp != 32) return;
    if (fb.memory_model != limine.FRAMEBUFFER_RGB) return;
    if (x >= fb.width or y >= fb.height) return;
    
    const addr = @intFromPtr(fb.address.?);
    const row_addr = addr + y * fb.pitch;
    const pixel_addr = row_addr + x * 4;

    const ptr = @as(*volatile u32, @ptrFromInt(pixel_addr));
    ptr.* = color;
}

pub fn clear(color: u32) void {
    const fb = g_fb orelse return;

    var y: u64 = 0;
    while (y < fb.height) : (y += 1) {
        var x: u64 = 0;
        while(x < fb.width) : (x += 1) {
            putPixel(x, y, color);
        }
    }
}
