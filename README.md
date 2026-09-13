# Zig-OS

[日本語版はこちら](README.ja.md)

Zig-OS is an experimental x86_64 hobby OS written in Zig and booted through Limine. The current development host is Apple Silicon macOS, with the kernel built as a higher-half ELF and tested under `qemu-system-x86_64`.

## Goals

- Build a freestanding `x86_64` kernel in Zig
- Boot via the Limine protocol
- Expand from early bring-up into memory management, interrupts, and basic graphics

## Current structure

- `src/main.zig`: Limine responses and boot sequencing
- `src/arch/x86_64/`: GDT, IDT, CPU exceptions and port I/O
- `src/memory/`: HHDM and sequential physical page allocation
- `src/tar.zig`: ustar iterator with checksum and bounds validation
- `src/rootfs.zig`: fixed-size read-only index and path normalization
- `src/shell.zig`: `help`, `ls [path]`, `cat <file>`, `stat <path>`
- `src/serial.zig`: COM1 input/output
- `src/video/framebuffer.zig`: screen clear
- `src/runtime.zig`: memory operations without libc

The shell and file handling still run inside the kernel. Userspace, processes, device IRQs, page-table management and persistent storage are not implemented. Kernel SIMD/FPU instruction generation is disabled because initialization and context saving are not implemented.

## Build and validation

Requires Zig **0.15.2**, `tar`, `xorriso`, `qemu-system-x86_64`, and `make` for the Limine host tool. The smoke test requires Python 3.

```sh
git submodule update --init --recursive
zig build test
zig build kernel
zig build iso
python3 scripts/smoke.py
zig build run
```

`kernel` stages `zig-out/iso/boot/kernel.elf`. `iso` packages `assets/initrd/` as ustar in the build cache and installs it into `zig-out/myos-bios.iso`. The tracked `assets/initrd.tar` is a legacy artifact and is not a build input. `run` starts QEMU with serial input/output on the host terminal.

`test` covers corrupt/truncated archives, ustar prefixes, path normalization, duplicate entries and index capacity. `scripts/smoke.py` validates boot and 19 serial shell cases in headless QEMU and saves `zig-out/smoke.log`.

## Initrd and shell limits

The index holds up to 32 entries excluding root, with normalized paths up to 256 bytes. Only regular files and directories are indexed; parent directory entries are required. Extended archive formats and link resolution are unsupported. File contents borrow Limine module memory, which must remain valid.

Absolute and relative paths both start at root. `.`, `..`, and repeated slashes are normalized; traversal above root is rejected. Input is limited to 128 bytes. Oversized lines are drained through the newline and never executed. Quoting and pipes are unsupported.
