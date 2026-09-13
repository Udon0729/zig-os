# Zig-OS

[English README](README.md)

Zig-OS は、Zig で書く実験的な x86_64 向け自作 OS です。ブートローダには Limine を使い、Apple Silicon macOS 上で higher-half ELF をビルドし、`qemu-system-x86_64` で動作確認する構成を前提にしています。

## 目的

- Zig で freestanding な `x86_64` カーネルを構築する
- Limine プロトコルでブートする
- 初期 bring-up からメモリ管理、割り込み、基本的な描画まで段階的に広げる

## 現在の構成

- `src/main.zig`: Limine応答の取得と起動順序
- `src/arch/x86_64/`: GDT、IDT、CPU例外、ポートI/O
- `src/memory/`: HHDMと単純な物理ページ割り当て
- `src/tar.zig`: チェックサムと境界を検証するustarイテレータ
- `src/rootfs.zig`: 読み取り専用の固定長索引とパス正規化
- `src/shell.zig`: `help`、`ls [path]`、`cat <file>`、`stat <path>`
- `src/serial.zig`: COM1による入力・出力
- `src/video/framebuffer.zig`: 画面クリア
- `src/runtime.zig`: libcを使わないメモリ操作

シェルとファイルサーバ相当の処理はまだカーネル内で動作します。ユーザー空間、プロセス、デバイスIRQ、ページテーブル管理、永続ストレージは未実装です。SIMD/FPUの初期化・状態保存も未実装のため、カーネルのSIMD/FPU命令生成を無効にしています。

## ビルドと検証

Zig **0.15.2**、`tar`、`xorriso`、`qemu-system-x86_64`、Limineホストツール用の`make`が必要です。スモークテストにはPython 3を使います。

```sh
git submodule update --init --recursive
zig build test
zig build kernel
zig build iso
python3 scripts/smoke.py
zig build run
```

`kernel`は`zig-out/iso/boot/kernel.elf`を生成します。`iso`は`assets/initrd/`をustar形式でビルドキャッシュへ梱包し、`zig-out/myos-bios.iso`へ配置します。追跡済みの`assets/initrd.tar`は旧成果物で、ビルドには使用しません。`run`はQEMUを起動し、ホストのターミナルをシリアル入出力に使います。

`test`はtarの破損・切り詰め、prefix、パス正規化、索引の重複・上限を検証します。`scripts/smoke.py`は画面なしのQEMUで起動と19件のシェル操作を検証し、`zig-out/smoke.log`へログを保存します。

## initrdとシェルの制限

索引はルートを除いて最大32エントリ、正規化後のパスは最大256バイトです。通常ファイルとディレクトリのみ扱い、親ディレクトリのエントリを必要とします。ustar以外の拡張形式やリンクの解決は対応していません。ファイル内容はLimineモジュールのメモリを参照するため、そのメモリの寿命を維持する必要があります。

絶対パス・相対パスはともにルートを基準とします。`.`、`..`、重複した`/`を正規化し、ルートより上への移動は拒否します。入力は最大128バイトで、超過した行は改行まで破棄し、実行しません。引用符やパイプは未対応です。
