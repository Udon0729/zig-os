const std = @import("std");
const limine = @import("boot/limine.zig");
const serial = @import("serial.zig");
const io = @import("arch/x86_64/port_io.zig");
const hhdm_mod = @import("memory/hhdm.zig");
const phys = @import("memory/phys.zig");
const fb = @import("video/framebuffer.zig");
const cpu = @import("arch/x86_64/cpu.zig");
const gdt = @import("arch/x86_64/gdt.zig");
const interrupts = @import("arch/x86_64/interrupts.zig");
const shell = @import("shell.zig");

comptime {
    _ = @import("runtime.zig");
}

export var requests_start: limine.RequestsStartMarker linksection(".limine_requests_start") = .{};
export var base_revision: limine.BaseRevision linksection(".limine_requests") = .{};
export var hhdm_request: limine.HhdmRequest linksection(".limine_requests") = .{};
export var memmap_request: limine.MemmapRequest linksection(".limine_requests") = .{};
export var framebuffer_request: limine.FramebufferRequest linksection(".limine_requests") = .{};
export var module_request: limine.ModuleRequest linksection(".limine_requests") = .{};
export var requests_end: limine.RequestsEndMarker linksection(".limine_requests_end") = .{};

const LimineBootstrap = struct {
    hhdm: *limine.HhdmResponse,
    memmap: *limine.MemmapResponse,
    modules: *limine.ModuleResponse,
};

var rootfs: @import("rootfs.zig").Rootfs = .{};

fn initRootfs(modules: *limine.ModuleResponse) void {
    var archive: ?[]const u8 = null;
    for (modules.modules[0..@intCast(modules.module_count)]) |module| {
        const tag = module.string orelse continue;
        if (!std.mem.eql(u8, std.mem.span(tag), "initrd")) continue;
        const address = module.address orelse fatal("initrd: null address");
        const bytes: [*]const u8 = @ptrCast(address);
        archive = bytes[0..@intCast(module.size)];
        break;
    }
    rootfs.init(archive orelse fatal("initrd: module not found")) catch |err| fatal(@errorName(err));
    serial.writeString("initrd: indexed ");
    serial.writeDecU64(rootfs.count);
    serial.writeLine(" entries");
}

fn earlyInitSerialAndCpu() void {
    cpu.cli();

    serial.init(0x3f8);
    serial.writeString("boot: entered _start\r\n");

    gdt.loadTable();
    gdt.reloadSegments();
    serial.writeString("cpu: gdt initialized\r\n");

    interrupts.init();
    serial.writeString("cpu: idt initialized\r\n");
}

fn fetchLimineResponses() LimineBootstrap {
    const hhdm = hhdm_request.response orelse fatal("limine: no HHDM response");
    const memmap = memmap_request.response orelse fatal("limine: no memmap response");
    const modules = module_request.response orelse fatal("limine: no module response");

    serial.writeString("boot: limine modules ok\r\n");

    return .{
        .hhdm = hhdm,
        .memmap = memmap,
        .modules = modules,
    };
}

fn initMemorySubsystem(hhdm: *limine.HhdmResponse, memmap: *limine.MemmapResponse) void {
    hhdm_mod.init(hhdm.offset);
    serial.writeString("mem: HHDM initialized\r\n");

    phys.init(memmap);
    serial.writeString("mem: Physical allocator initialized\r\n");

    if (phys.allocPage()) |_| {
        serial.writeString("mem: smoke page alloc ok\r\n");
    } else {
        fatal("mem: allocPage failed");
    }
}

fn initFramebufferOptional() void {
    if (framebuffer_request.response) |fb_resp| {
        if (fb_resp.framebuffer_count > 0) {
            fb.init(fb_resp.framebuffers[0]);
            fb.clear(0x00202020);
            serial.writeString("boot: framebuffer initialized\r\n");
        } else {
            serial.writeString("boot: framebuffer response has no entries\r\n");
        }
    } else {
        serial.writeString("boot: no framebuffer response\r\n");
    }
}

export fn _start() noreturn {
    earlyInitSerialAndCpu();

    const boot = fetchLimineResponses();
    initMemorySubsystem(boot.hhdm, boot.memmap);

    initRootfs(boot.modules);

    initFramebufferOptional();

    serial.writeString("boot: hello from Zig OS\r\n");
    shell.run(&rootfs);
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
