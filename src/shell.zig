const std = @import("std");
const serial = @import("serial.zig");
const fs = @import("rootfs.zig");

fn execute(rootfs: *const fs.Rootfs, line: []const u8) void {
    var tokens = std.mem.tokenizeAny(u8, line, " \t\r\n");
    const command = tokens.next() orelse return;
    const argument = tokens.next();
    if (tokens.next() != null) {
        serial.writeLine("shell: too many arguments");
        return;
    }
    if (std.mem.eql(u8, command, "help")) {
        if (argument != null) {
            serial.writeLine("usage: help");
            return;
        }
        serial.writeLine("Available commands:\n  help          - Show this help\n  ls [path]     - List directory contents\n  cat <file>    - Display file contents\n  stat <path>   - Show file info");
        return;
    }
    const list = std.mem.eql(u8, command, "ls");
    const cat = std.mem.eql(u8, command, "cat");
    const stat = std.mem.eql(u8, command, "stat");
    if (!list and !cat and !stat) {
        serial.writeString("Unknown command: ");
        serial.writeLine(command);
        return;
    }
    if (!list and argument == null) {
        serial.writeString(command);
        serial.writeLine(": missing operand");
        return;
    }
    var buffer: [fs.max_path]u8 = undefined;
    const path = fs.normalize(argument orelse "/", &buffer) catch {
        serial.writeLine("shell: invalid path");
        return;
    };
    const entry = rootfs.find(path) orelse {
        serial.writeString(command);
        serial.writeLine(": path not found");
        return;
    };
    if (list) {
        if (!entry.is_dir) {
            serial.writeLine(entry.name());
            return;
        }
        var found = false;
        for (rootfs.entries[0..rootfs.count]) |*child| {
            if (!std.mem.eql(u8, fs.parentPath(child.name()), path)) continue;
            serial.writeString(if (child.is_dir) "  [DIR] " else "  [FILE] ");
            const start = if (path.len == 0) 0 else path.len + 1;
            serial.writeLine(child.name()[start..]);
            found = true;
        }
        if (!found) serial.writeLine("(empty)");
    } else if (cat) {
        if (entry.is_dir) {
            serial.writeLine("cat: is a directory");
            return;
        }
        serial.writeString(entry.data);
        if (entry.data.len > 0 and entry.data[entry.data.len - 1] != '\n') serial.writeLine("");
    } else {
        serial.writeString("  Name: /");
        serial.writeLine(entry.name());
        serial.writeString("  Type: ");
        serial.writeLine(if (entry.is_dir) "directory" else "file");
        serial.writeString("  Size: ");
        serial.writeDecU64(entry.data.len);
        serial.writeLine(" bytes");
    }
}

pub fn run(rootfs: *const fs.Rootfs) noreturn {
    var buffer: [128]u8 = undefined;
    serial.writeLine("\nZig OS Shell - type 'help' for commands");
    while (true) {
        serial.writeString("\n> ");
        const length = serial.readLine(&buffer) catch {
            serial.writeLine("shell: line too long");
            continue;
        };
        execute(rootfs, buffer[0..length]);
    }
}
