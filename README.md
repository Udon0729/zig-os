# Zig-OS

[日本語版はこちら](README.ja.md)

Zig-OS is an experimental x86_64 hobby OS written in Zig and intended to boot via Limine. The current target workflow is to develop on Apple Silicon macOS and run the kernel under `qemu-system-x86_64`.

## Goals

- Build a freestanding `x86_64` kernel in Zig
- Boot through the Limine protocol
- Grow from early serial-output bring-up into memory management, interrupts, and framebuffer support

## Repository Layout

```text
.
├── build.zig
├── linker.ld
├── limine.conf
├── include/limine.h
├── src/
│   ├── main.zig
│   └── boot/limine.zig
└── ARM_MACBOOK_ZIG_OS_GUIDE.md
```

## Current Status

Implemented:

- Freestanding Zig build configuration in `build.zig`
- Linker script and Limine boot entry
- Limine request/response structs for base revision, HHDM, memory map, and framebuffer
- Kernel entry skeleton in `src/main.zig`

Not implemented yet:

- `src/serial.zig`
- `src/arch/x86_64/port_io.zig`
- ISO creation and QEMU run steps in `build.zig`
- Memory allocator, interrupt setup, framebuffer drawing

## Build Status

- `zig build`
  - currently succeeds, but only stages `zig-out/iso/limine.conf`
- `zig build kernel`
  - currently fails because `src/serial.zig` and `src/arch/x86_64/port_io.zig` are referenced but not created yet

## Planned Next Steps

1. Implement `src/arch/x86_64/port_io.zig`
2. Implement `src/serial.zig`
3. Make `zig build kernel` produce `zig-out/iso/boot/kernel.elf`
4. Add ISO assembly and `zig build run` for QEMU
5. Initialize HHDM and parse the Limine memory map

## Documentation

- Development guide for Apple Silicon + QEMU:
  - [ARM_MACBOOK_ZIG_OS_GUIDE.md](ARM_MACBOOK_ZIG_OS_GUIDE.md)
- Contributor notes:
  - [AGENTS.md](AGENTS.md)
