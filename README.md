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
├── assets/initrd/          Static files staged for packaging into initrd.tar (optional / planned use)
├── src/
│   ├── arch/x86_64/
│   │   ├── cpu.zig
│   │   ├── gdt.zig
│   │   ├── idt.zig
│   │   ├── interrupts.zig
│   │   ├── port_io.zig
│   │   └── lowlevel.S
│   ├── boot/limine.zig
│   ├── main.zig
│   ├── memory/{hhdm,phys}.zig
│   ├── runtime.zig
│   ├── serial.zig
│   └── video/framebuffer.zig
└── vendor/limine
```

## Current Status

Implemented:

- Freestanding Zig build and higher-half linker flow
- Limine boot entry and protocol request/response bindings (HHDM, memory map, framebuffer, **modules**)
- Serial bring-up on COM1
- **GDT setup, segment reload, and IDT installation** (see `src/arch/x86_64/{gdt,idt,interrupts}.zig` and `lowlevel.S`)
- **CPU exception path** with serial logging for common faults (e.g. breakpoint, page fault)
- HHDM initialization and a simple physical page allocator (with a smoke-test page allocation)
- Framebuffer detection and basic screen clear
- `zig build kernel`, `zig build iso`, and `zig build run`

Verified:

- The kernel boots in QEMU on Apple Silicon macOS
- Serial output reaches the host terminal (boot phases logged under prefixes such as `boot:`, `cpu:`, `mem:`)
- The framebuffer can be initialized and cleared
- Exception handling has been exercised in QEMU (for example breakpoint vector `3` and page-fault vector `14`)

Not implemented yet:

- **Initrd / module content** in the kernel (`limine.conf` can reference `/boot/initrd.tar`, but there is no in-kernel archive reader or shell yet)
- Full interrupt controller bring-up (**PIC/APIC**) and device IRQs (timer, keyboard, storage)
- Paging management beyond Limine-provided mappings
- Block device drivers and filesystems (e.g. FAT32)
- Interactive serial shell

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

1. Package `assets/initrd/` as `initrd.tar`, wire the Limine module into the ISO, and **parse or index the archive in the kernel**
2. Add a **minimal serial shell** (`help`, `ls`, `cat`, `stat`) backed by that read-only data
3. Extend the physical allocator beyond the current bring-up smoke test as needs grow
4. Optional: text or primitive drawing on the framebuffer

Device-level work (PIC/APIC, timers, keyboard, real disks) is intentionally deferred until the above read-only initrd path is usable.
