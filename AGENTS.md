# Repository Guidelines

## Project Structure & Module Organization
`src/main.zig` is the freestanding kernel entrypoint and currently contains `_start`, serial output, and panic handling. Bootloader-facing assets live at the repo root: `linker.ld` controls section layout, `limine.conf` defines the Limine boot entry, and `include/limine.h` is the imported protocol header. Use `iso/boot/` as the staging area for bootable image contents. Treat `.zig-cache/` and `kernel.elf` as generated artifacts, not source.

## Architecture Notes
This repository is an early x86_64 Zig OS kernel booted with Limine. Keep low-level boot code isolated, prefer small helpers for port I/O and logging, and move reusable logic out of `_start` so it can be tested separately.

## Build, Test, and Development Commands
Use Zig `0.15.2` to match the current workspace.

- `zig fmt src/main.zig` formats the kernel source.
- `zig fmt --check src/main.zig` verifies formatting before a PR.
- `zig build` is intended to become the canonical build entry, but it currently fails because `build.zig` does not yet define `pub fn build(...)`.
- `zig test src/main.zig` is not valid for the current freestanding entrypoint because inline kernel assembly such as `hlt` cannot run in host tests.

When adding build automation, make `zig build` produce `kernel.elf` and stage boot files under `iso/boot/`.

## Coding Style & Naming Conventions
Follow Zig defaults and let `zig fmt` decide whitespace and indentation. Use `camelCase` for functions (`printSerial`), `PascalCase` for types (`LimineBaseRevision`), and `snake_case` only where ABI or exported symbol names require it (`base_revision`). Keep comments brief and focused on hardware, boot, or linker constraints.

## Testing Guidelines
There is no automated test suite yet. New logic should be moved into host-safe functions or separate modules, then covered with `zig test` in dedicated files such as `src/serial_test.zig` or `tests/serial_test.zig`. Prioritize tests for pure helpers, parsing, and address calculations; verify boot-path changes with emulator serial output.

## Commit & Pull Request Guidelines
Git history is not available in this workspace, so no local convention can be inferred. Use short imperative commit messages with a scope, for example `kernel: add COM1 writer`. PRs should describe the boot impact, list required tool versions, link related issues, and include proof of verification such as serial logs or emulator screenshots when behavior changes.
