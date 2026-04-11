# Zig-OS

[English README](README.md)

Zig-OS は、Zig で書く実験的な x86_64 向け自作 OS です。ブートローダには Limine を使い、Apple Silicon macOS 上で開発し、`qemu-system-x86_64` で起動確認する構成を想定しています。

## 目的

- Zig で freestanding な `x86_64` カーネルを構築する
- Limine プロトコルでブートする
- serial 出力による初期 bring-up から始めて、メモリ管理、割り込み、framebuffer へ段階的に広げる

## リポジトリ構成

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

## 現状の実装

実装済み:

- `build.zig` の freestanding build 設定
- リンカスクリプトと Limine の起動設定
- base revision / HHDM / memory map / framebuffer 向けの Limine 構造体定義
- `src/main.zig` のカーネル入口の骨格

未実装:

- `src/serial.zig`
- `src/arch/x86_64/port_io.zig`
- `build.zig` 内の ISO 作成と QEMU 実行 step
- メモリアロケータ、割り込み初期化、framebuffer 描画

## ビルド状況

- `zig build`
  - 現状は `zig-out/iso/limine.conf` の staging まで成功する
- `zig build kernel`
  - `src/serial.zig` と `src/arch/x86_64/port_io.zig` がまだ無いため、現在は失敗する

## 次にやるべきこと

1. `src/arch/x86_64/port_io.zig` を実装する
2. `src/serial.zig` を実装する
3. `zig build kernel` で `zig-out/iso/boot/kernel.elf` を生成できるようにする
4. ISO 生成と `zig build run` を追加する
5. Limine の HHDM と memory map を使った初期化に進む

## 関連資料

- Apple Silicon + QEMU 前提の開発手順:
  - [ARM_MACBOOK_ZIG_OS_GUIDE.md](ARM_MACBOOK_ZIG_OS_GUIDE.md)
- コントリビュータ向けメモ:
  - [AGENTS.md](AGENTS.md)
