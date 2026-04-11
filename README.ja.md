# Zig-OS

[English README](README.md)

Zig-OS は、Zig で書く実験的な x86_64 向け自作 OS です。ブートローダには Limine を使い、Apple Silicon macOS 上で higher-half ELF をビルドし、`qemu-system-x86_64` で動作確認する構成を前提にしています。

## 目的

- Zig で freestanding な `x86_64` カーネルを構築する
- Limine プロトコルでブートする
- 初期 bring-up からメモリ管理、割り込み、基本的な描画まで段階的に広げる

## リポジトリ構成

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

## 現状の実装

実装済み:

- freestanding Zig build と higher-half linker 構成
- Limine の起動エントリと protocol request/response 定義
- COM1 を使った serial 初期化とログ出力
- HHDM 初期化と単純な物理ページアロケータ
- framebuffer の取得と画面クリア
- `zig build kernel`、`zig build iso`、`zig build run`

確認済み:

- Apple Silicon macOS 上の QEMU でカーネルが起動する
- serial 出力がホストのターミナルへ流れる
- framebuffer を初期化して単色で塗りつぶせる

未実装:

- GDT / IDT 初期化
- 割り込みと例外ハンドラ
- Limine 提供マッピング以降のページング管理
- キーボード入力、タイマ、シェル

## セットアップ

clone 後に Limine の submodule を初期化します。

```sh
git submodule update --init --recursive
```

必要なホストツール:

- Zig `0.15.2`
- `xorriso`
- `qemu-system-x86_64`
- Limine のホストツールを作るための `make`

## ビルドと実行

```sh
zig build kernel
zig build iso
zig build run
```

- `zig build kernel` は `zig-out/iso/boot/kernel.elf` を生成して staging します
- `zig build iso` は `zig-out/myos-bios.iso` を作成し、`limine bios-install` まで実行します
- `zig build run` は QEMU を起動し、serial 出力を標準入出力へ流します

## 次にやるべきこと

1. GDT と IDT の初期化を追加する
2. 基本的な例外・割り込みハンドラを入れる
3. 物理ページアロケータを再利用しやすい形に拡張する
4. framebuffer 上に簡単な文字描画または図形描画を追加する
