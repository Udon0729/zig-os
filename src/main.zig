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
const tar = @import("tar.zig");

comptime {
    _ = @import("runtime.zig");
}

export var requests_start: limine.RequestsStartMarker = .{};
export var base_revision: limine.BaseRevision = .{};
export var hhdm_request: limine.HhdmRequest = .{};
export var memmap_request: limine.MemmapRequest = .{};
export var framebuffer_request: limine.FramebufferRequest = .{};
export var module_request: limine.ModuleRequest = .{};
export var requests_end: limine.RequestsEndMarker = .{};

const LimineBootstrap = struct {
    hhdm: *limine.HhdmResponse,
    memmap: *limine.MemmapResponse,
    modules: *limine.ModuleResponse,
};

const MAX_FILES = 32;

const RootfsEntry = struct {
    name: [64]u8,
    name_len: usize,
    data_ptr: [*]const u8,
    data_len: usize,
    is_dir: bool,
};

var g_rootfs: [MAX_FILES]RootfsEntry = undefined;
var g_rootfs_count: usize = 0;

fn initRootfs(modules: *limine.ModuleResponse) void {
    if (modules.module_count == 0) {
        serial.writeString("initrd: no modules\r\n");
        return;
    }
    const mod = modules.modules[0];
    const archive_ptr: [*]const u8 = @ptrFromInt(@intFromPtr(mod.address));
    const archive_len: usize = @intCast(mod.size);

    _ = tar.iterate(archive_ptr, archive_len, struct {
        fn callback(_: ?*anyopaque, hdr: []const u8, data: []const u8) ?bool {
            if (g_rootfs_count >= MAX_FILES) return false;
            const name = tar.getFileName(hdr);
            if (name.len >= 64) return true;
            var entry = RootfsEntry{
                .name = undefined,
                .name_len = name.len,
                .data_ptr = data.ptr,
                .data_len = data.len,
                .is_dir = tar.isDirectory(hdr),
            };
            for (&entry.name) |*c| c.* = 0;
            for (name, 0..) |c, i| {
                entry.name[i] = c;
            }
            g_rootfs[g_rootfs_count] = entry;
            g_rootfs_count += 1;
            return true;
        }
    }.callback, null);

    serial.writeString("initrd: indexed ");
    serial.writeDecU64(g_rootfs_count);
    serial.writeString(" entries\r\n");
}

fn findFile(name: []const u8) ?RootfsEntry {
    for (g_rootfs[0..g_rootfs_count]) |entry| {
        const entry_name = entry.name[0..entry.name_len];
        if (std.mem.eql(u8, entry_name, name)) {
            return entry;
        }
    }
    return null;
}

fn cmdHelp() void {
    serial.writeString("Available commands:\r\n");
    serial.writeString("  help          - Show this help\r\n");
    serial.writeString("  ls [path]     - List directory contents\r\n");
    serial.writeString("  cat <file>    - Display file contents\r\n");
    serial.writeString("  stat <file>   - Show file info\r\n");
}

fn cmdLs(path: []const u8) void {
        var prefix = path;
        if (prefix.len > 0 and prefix[prefix.len - 1] != '/') {
            var buf: [65]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{s}/", .{prefix}) catch buf[0..0];
            prefix = slice;
        }
    var found = false;
    for (g_rootfs[0..g_rootfs_count]) |entry| {
        const entry_name = entry.name[0..entry.name_len];
        if (std.mem.startsWith(u8, entry_name, prefix)) {
            const rest = entry_name[prefix.len..];
            if (rest.len > 0 and std.mem.indexOf(u8, rest, "/") == 0) {
                const next_slash = std.mem.indexOf(u8, rest[1..], "/");
                const name_end = if (next_slash) |pos| pos + 1 else rest.len;
                const item_name = rest[0..name_end];
                serial.writeString("  ");
                if (std.mem.endsWith(u8, item_name, "/")) {
                    serial.writeString("[DIR] ");
                } else {
                    serial.writeString("[FILE]");
                }
                serial.writeString(item_name);
                serial.writeString("\r\n");
                found = true;
            }
        }
    }
    if (!found) {
        serial.writeString("(empty)\r\n");
    }
}

fn cmdCat(path: []const u8) void {
    if (findFile(path)) |entry| {
        if (entry.is_dir) {
            serial.writeString("cat: is a directory\r\n");
        } else {
            const data_ptr: [*]const u8 = @ptrFromInt(@intFromPtr(entry.data_ptr));
            var i: usize = 0;
            while (i < entry.data_len) {
                serial.writeByte(data_ptr[i]);
                i += 1;
            }
            if (entry.data_len > 0 and data_ptr[entry.data_len - 1] != '\n') {
                serial.writeString("\r\n");
            }
        }
    } else {
        serial.writeString("cat: file not found\r\n");
    }
}

fn cmdStat(path: []const u8) void {
    if (findFile(path)) |entry| {
        serial.writeString("  Name: ");
        serial.writeString(entry.name[0..entry.name_len]);
        serial.writeString("\r\n");
        serial.writeString("  Type: ");
        if (entry.is_dir) serial.writeString("directory") else serial.writeString("file");
        serial.writeString("\r\n");
        serial.writeString("  Size: ");
        serial.writeDecU64(entry.data_len);
        serial.writeString(" bytes\r\n");
        serial.writeString("  Addr: ");
        serial.writeHex64(@intFromPtr(entry.data_ptr));
        serial.writeString("\r\n");
    } else {
        serial.writeString("stat: file not found\r\n");
    }
}

fn parseAndExec(line: []const u8) void {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return;

    // Simple space-separated tokenization
    var tokens: [4][]const u8 = undefined;
    var token_count: usize = 0;
    var start: usize = 0;
    var in_token = false;

    for (trimmed, 0..) |c, i| {
        if (c == ' ' or c == '\t') {
            if (in_token) {
                tokens[token_count] = trimmed[start..i];
                token_count += 1;
                if (token_count >= tokens.len) break;
                in_token = false;
            }
        } else {
            if (!in_token) {
                start = i;
                in_token = true;
            }
        }
    }
    if (in_token and token_count < tokens.len) {
        tokens[token_count] = trimmed[start..trimmed.len];
        token_count += 1;
    }

    if (token_count == 0) return;
    const cmd = tokens[0];

    if (std.mem.eql(u8, cmd, "help")) {
        cmdHelp();
    } else if (std.mem.eql(u8, cmd, "ls")) {
        const path = if (token_count > 1) tokens[1] else "/";
        cmdLs(path);
    } else if (std.mem.eql(u8, cmd, "cat")) {
        if (token_count < 2) {
            serial.writeString("cat: missing operand\r\n");
            return;
        }
        cmdCat(tokens[1]);
    } else if (std.mem.eql(u8, cmd, "stat")) {
        if (token_count < 2) {
            serial.writeString("stat: missing operand\r\n");
            return;
        }
        cmdStat(tokens[1]);
    } else {
        serial.writeString("Unknown command: ");
        serial.writeString(cmd);
        serial.writeString("\r\nType 'help' for available commands.\r\n");
    }
}

fn shellLoop() noreturn {
    var buf: [128]u8 = undefined;
    serial.writeString("\r\nZig OS Shell - type 'help' for commands\r\n");
    while (true) {
        serial.writeString("\r\n> ");
        _ = serial.readLine(&buf);
        const line = buf[0..buf.len];
        parseAndExec(line);
    }
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
    shellLoop();
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
