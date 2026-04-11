# Zig-OS

[日本語版はこちら](README.ja.md)

Zig-OS is an experimental x86_64 hobby OS written in Zig and booted through Limine. The current development host is Apple Silicon macOS, with the kernel built as a higher-half ELF and tested under `qemu-system-x86_64`.

## Goals

- Build a freestanding `x86_64` kernel in Zig
- Boot via the Limine protocol
- Expand from early bring-up into memory management, interrupts, and basic graphics

## Repository Layout

```text
.
├── build.zig
├── linker.ld
├── limine.conf
├── include/limine.h
├── src/
│   ├── arch/x86_64/port_io.zig
│   ├── boot/limine.zig
│   ├── main.zig
│   ├── memory/{hhdm,phys}.zig
│   ├── serial.zig
│   └── video/framebuffer.zig
└── vendor/limine
```

## Current Status

Implemented:

- Freestanding Zig build and higher-half linker flow
- Limine boot entry and protocol request/response bindings
- Serial bring-up on COM1
- HHDM initialization and a simple physical page allocator
- Framebuffer detection and basic screen clear
- `zig build kernel`, `zig build iso`, and `zig build run`

Verified:

- The kernel boots in QEMU on Apple Silicon macOS
- Serial output reaches the host terminal
- The framebuffer can be initialized and cleared

Not implemented yet:

- GDT and IDT setup
- Interrupt and exception handlers
- Paging management beyond Limine-provided mappings
- Keyboard input, timer support, and a shell

## Setup

Initialize the Limine submodule after cloning:

```sh
git submodule update --init --recursive
```

Required host tools:

- Zig `0.15.2`
- `xorriso`
- `qemu-system-x86_64`
- `make` for building the Limine host tool when needed

## Build And Run

```sh
zig build kernel
zig build iso
zig build run
```

- `zig build kernel` builds and stages `zig-out/iso/boot/kernel.elf`
- `zig build iso` assembles `zig-out/myos-bios.iso` and runs `limine bios-install`
- `zig build run` boots the ISO in QEMU with serial output on standard I/O

## Next Steps

1. Add GDT and IDT initialization
2. Install basic exception and interrupt handlers
3. Replace the bump-style physical allocator with a reusable frame allocator
4. Add simple text or primitive drawing on top of the framebuffer
