const std = @import("std");
const limine = @import("boot/limine.zig");
const serial = @import("serial.zig");
const io = @import("arch/x86_64/port_io.zig");
const hhdm_mod = @import("memory/hhdm.zig");
const phys = @import("memory/phys.zig");

export var requests_start: limine.RequestsStartMarker = .{};
export var base_revision: limine.BaseRevision = .{};
export var hhdm_request: limine.HhdmRequest = .{};
export var memmap_request: limine.MemmapRequest = .{};
export var framebuffer_request: limine.FramebufferRequest = .{};
export var requests_end: limine.RequestsEndMarker = .{};

export fn _start() noreturn {
    serial.init(0x3f8);
    serial.writeString("boot: entered _start\r\n");

    const hhdm = hhdm_request.response orelse fatal("limine: no HHDM response");
    const memmap = memmap_request.response orelse fatal("limine: no memmap response");
    
    hhdm_mod.init(hhdm.offset);
    serial.writeString("mem: HHDM initialized\r\n");

    phys.init(memmap);
    serial.writeString("mem: Physical allocator initialized\r\n");

    if (phys.allocPage()) |_| {
        serial.writeString("mem: allocPage ok\r\n");
    } else {
        fatal("mem: allocPage failed");
    }

    if (framebuffer_request.response) |fb_resp| {
        if (fb_resp.framebuffer_count > 0) {
            serial.writeString("boot: framebuffer available\r\n");
        } else {
            serial.writeString("boot: framebuffer response has no entries\r\n");
        }
    } else {
        serial.writeString("boot: no framebuffer response\r\n");
    }

    serial.writeString("boot: hello from Zig OS\r\n");
    io.haltLoop();
}

fn fatal(msg: []const u8) noreturn {
    serial.writeString("fatal: ");
    serial.writeString(msg);
    serial.writeString("\r\n");
    io.haltLoop();
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    fatal(msg);
}
