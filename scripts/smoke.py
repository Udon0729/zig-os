#!/usr/bin/env python3
"""Run after `zig build iso`; validate real serial shell behavior in QEMU."""
import os
from pathlib import Path
import select
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
COMMAND = [
    "qemu-system-x86_64", "-machine", "pc,accel=tcg", "-cpu", "qemu64",
    "-m", "512M", "-display", "none", "-monitor", "none", "-serial", "stdio",
    "-cdrom", str(ROOT / "zig-out/myos-bios.iso"), "-no-reboot", "-no-shutdown",
]


def main():
    transcript = bytearray()
    process = subprocess.Popen(COMMAND, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def prompt():
        data = bytearray()
        deadline = time.monotonic() + 20
        while not data.endswith(b"\r\n> "):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(f"Serial prompt timed out: {data!r}")
            if select.select([process.stdout], [], [], remaining)[0]:
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    raise AssertionError(f"QEMU exited: {data!r}")
                data.extend(chunk)
                transcript.extend(chunk)
        assert b"\r\r\n" not in data, repr(data)
        assert b"fatal:" not in data and b"EXCEPTION" not in data, repr(data)
        return data

    def check(command, expected, absent=None):
        # Pace writes so the emulated UART's finite receive FIFO is not overrun.
        for byte in command:
            process.stdin.write(bytes([byte]))
            process.stdin.flush()
            time.sleep(0.003)
        output = prompt()
        assert expected in output, (command, output)
        if absent is not None:
            assert absent not in output, (command, output)
        print(f"PASS {command[:60]!r}")

    try:
        boot = prompt()
        for marker in (b"cpu: gdt initialized", b"cpu: idt initialized", b"mem: smoke page alloc ok", b"initrd: indexed 5 entries", b"boot: hello from Zig OS"):
            assert marker in boot, boot
        check(b"help\r\n", b"Available commands:")
        check(b"ls\r", b"[FILE] hello.txt", b"[FILE] info.txt")
        check(b"ls /docs/\n", b"[FILE] info.txt", b"hello.txt")
        check(b"cat /hello.txt\r", b"Hello from initrd")
        check(b"cat ./docs/../docs/info.txt\r", b"This file is inside the initrd tar archive.")
        check(b"stat /etc/motd\r", b"Size: 18 bytes")
        check(b"stat /\r", b"Type: directory")
        check(b"cat /docs\r", b"cat: is a directory")
        check(b"cat missing\r", b"cat: path not found")
        check(b"ls missing\r", b"ls: path not found")
        check(b"cat ../../hello.txt\r", b"shell: invalid path")
        check(b"cat\r", b"cat: missing operand")
        check(b"cat hello.txt extra\r", b"shell: too many arguments")
        check(b"helx\x7fp\r", b"Available commands:")
        check(b"cat\thello.txt\r", b"Hello from initrd")
        check(b"x" * 150 + b"\r", b"shell: line too long", b"Unknown command:")
        check(b"help\r", b"Available commands:")
        check(b"\r", b"\r\n> ", b"Unknown command:")
        check(b"unknown\r", b"Unknown command: unknown")
        print("PASS boot and 19 serial shell checks")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        (ROOT / "zig-out/smoke.log").write_bytes(transcript)


if __name__ == "__main__":
    main()
