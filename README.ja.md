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
├── assets/initrd/          initrd.tar 化する静的ファイル（任意／予定）
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

## 現状の実装

実装済み:

- freestanding Zig build と higher-half linker 構成
- Limine の起動エントリと protocol request/response 定義（HHDM、メモリマップ、フレームバッファ、**モジュール**）
- COM1 を使った serial 初期化とログ出力
- **GDT の設定・セグメント再読込・IDT の構築**（`src/arch/x86_64/{gdt,idt,interrupts}.zig` と `lowlevel.S`）
- **CPU 例外経路**（代表的な例外をシリアルへログ出力。例: ブレークポイント、ページフォルト）
- HHDM 初期化と単純な物理ページアロケータ（スモークテストとしてのページ割り当てあり）
- framebuffer の取得と画面クリア
- `zig build kernel`、`zig build iso`、`zig build run`

確認済み:

- Apple Silicon macOS 上の QEMU でカーネルが起動する
- serial 出力がホストのターミナルへ流れる（`boot:`、`cpu:`、`mem:` などのプレフィックスでブート段階をログ出力）
- framebuffer を初期化して単色で塗りつぶせる
- QEMU 上で例外処理を確認済み（例: ベクター `3` のブレークポイント、ベクター `14` のページフォルト）

未実装:

- カーネル側での **initrd／モジュールの内容利用**（`limine.conf` で `/boot/initrd.tar` を参照できる構成はあるが、アーカイブ読み取りやシェルはまだない）
- 割り込みコントローラの本番初期化（**PIC/APIC**）およびデバイス IRQ（タイマ、キーボード、ストレージなど）
- Limine が用意したマッピングを超えるページング管理
- ブロックデバイスドライバやファイルシステム（例: FAT32）
- 対話型のシリアルシェル

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

1. `assets/initrd/` を `initrd.tar` にまとめ、Limine のモジュールとして ISO に載せ、カーネル側で **アーカイブのパースまたはインデックス化**を行う
2. その読み取り専用データをバックエンドとした **最小のシリアルシェル**（`help`、`ls`、`cat`、`stat`）を追加する
3. 必要に応じて、現在の bring-up 用スモークテストを超えて物理アロケータを拡張する
4. （任意）フレームバッファ上へのテキストまたは簡易図形描画

上記の読み取り専用 initrd 経路が使えるようになるまでは、デバイス寄りの作業（PIC/APIC、タイマ、キーボード、実ディスクなど）は意図的に後回しにしています。
