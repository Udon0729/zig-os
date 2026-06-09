# Repository Guidelines

## Project Structure & Module Organization
`src/main.zig` is the kernel entry point. Architecture-specific x86_64 code lives in `src/arch/x86_64/`, including CPU setup, GDT/IDT, interrupts, port I/O, and `lowlevel.S`. Boot bindings are in `src/boot/limine.zig`; memory helpers are under `src/memory/`; serial and framebuffer support live in `src/serial.zig` and `src/video/`. Top-level build inputs are `build.zig`, `linker.ld`, and `limine.conf`. Static initrd files are stored in `assets/initrd/`. Treat `vendor/limine/` as vendored bootloader code.

Key files: `src/runtime.zig` provides minimal `memcpy`/`memmove`/`memset` (no libc). `limine.conf` references `/boot/initrd.tar` but the archive does not exist yet — initrd packing is a pending task.

## Build, Test, and Development Commands
Use Zig `0.15.2` with `xorriso`, `qemu-system-x86_64`, and `make`. Development host is Apple Silicon macOS; kernel targets x86_64 freestanding and is linked with `lld`.

- `zig build kernel` builds the kernel and stages `zig-out/iso/boot/kernel.elf`.
- `zig build iso` packages `zig-out/myos-bios.iso` and runs `limine bios-install`.
- `zig build run` boots the ISO in QEMU with serial output on stdio.
- `git submodule update --init --recursive` initializes the Limine submodule after cloning.

## Coding Style & Naming Conventions
Follow Zig defaults: 4-space indentation, no tabs, and grouped imports. Run `zig fmt` on edited Zig files before submitting. Use `lower_snake_case` for filenames and assembly labels, `camelCase` for Zig functions and locals such as `haltLoop`, and `PascalCase` for types such as `InterruptFrame`. Keep serial logs short and explicit.

## Testing Guidelines
There is no separate automated test suite yet. Use the build and QEMU path for validation:

- Run `zig build kernel` for compile/link checks.
- Run `zig build iso` when boot assets, Limine configuration, or ISO layout changes.
- Run `zig build run` for runtime validation and inspect serial output for `boot:`, CPU setup, and exception messages.

For memory, interrupt, or boot-path changes, include the exact command used and the relevant serial output in the PR.

## Commit & Pull Request Guidelines
Recent history uses short, action-first subjects such as `fix limine.zig`, `add cpu.zig, gdt.zig, idt.zig, interrupts.zig`, and `Refactor _start function and modularize boot process in main.zig`. Keep commits focused. PRs should describe affected kernel behavior, list verification commands, and note QEMU-visible results. Include screenshots only for framebuffer changes; otherwise prefer serial logs.

## Implementation Notes
Current exception handling, GDT/IDT setup, Limine boot data, HHDM access, memmap access, physical allocation, framebuffer clear, and module request wiring are working. Preserve that baseline unless a task changes it. The next planned feature area is initrd-backed read-only file browsing using Limine modules, a tar parser, a fixed-size rootfs index, and serial shell commands such as `help`, `ls`, `cat`, and `stat`.

## Common Pitfalls
- Forgetting `git submodule update --init --recursive` after clone → Limine binaries missing, ISO build fails.
- Editing `limine.conf` without running `zig build iso` → QEMU boots stale ISO.
- `zig build run` inherits stdio for serial; if terminal appears hung, the kernel likely panicked — check earlier serial lines.
- Build artifacts in `zig-out/` and `.zig-cache/` are gitignored; clean with `rm -rf zig-out .zig-cache` if needed.
