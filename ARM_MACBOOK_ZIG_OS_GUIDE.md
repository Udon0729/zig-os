# Zig で書く x86_64 自作 OS を arm MacBook 上の QEMU で動かす手順書

## 0. この文書の前提

この文書は「**x86_64 PC 互換環境で起動する自作 OS** を Zig で書き、**Apple Silicon 搭載 MacBook** 上で **QEMU** により動かす」ことを目的とする。  
ここでいう「Arch 互換」は、まずは **x86_64 PC 向けの一般的なブート環境に適合する** という意味で扱う。**Arch Linux 互換ユーザーランド** や `pacman` 互換、ELF 実行環境、POSIX 互換 syscall 群まではこの段階では含めない。

2026-04-12 時点で、公式配布ページ上の Zig の stable は **0.15.2**、Homebrew の `qemu` formula は **10.2.2** である。  
Limine については、公式 GitHub mirror 上で確認できる **11.x 系ドキュメントと binary branch** に合わせて記述する。  
本書では **Zig 0.15.2 + Limine 11.x + QEMU x86_64 system emulation** を前提にする。

## 1. なぜ Zig + Limine + QEMU なのか

- **Zig** は公式言語仕様上、ターゲットを CPU アーキテクチャ / OS / ABI で明示できる。`zig targets` と `build.zig` により、arm64 macOS 上からでも `x86_64-freestanding-none` を自然に扱える。
- **Limine** は x86-64 を含む複数アーキテクチャに対応したブートローダ兼ブートプロトコルで、Framebuffer / HHDM / Memory Map など、OS 開発で最初に必要な情報を整理して受け取れる。
- **QEMU** は system emulation により別アーキテクチャのゲスト OS を実行できる。QEMU 公式ドキュメントでは、macOS/Arm ホスト上でも **TCG** が利用可能で、アクセラレータの既定も TCG である。

Apple Silicon 上で `qemu-system-x86_64` を使う場合、まずは **完全仮想化ではなくエミュレーション前提** と考えるのが安全である。  
したがって最初のマイルストーンは「高速化」ではなく、**確実に起動して serial で観測できること** に置く。

## 2. 先に読むべき一次資料

### Zig

- Language Reference 0.15.2
  - Targets
  - Assembly
  - `@cImport`
  - Zig Build System
  - Style Guide

Zig では low-level 部分を素直に書けるが、OS 開発では特に次の 4 点を押さえるとよい。

1. **ターゲット指定**  
   `x86_64-freestanding-none` を build 時に明示する。
2. **inline asm**  
   `outb`, `hlt`, `lgdt`, `lidt`, `wrmsr`, `rdmsr`, `invlpg` などに使う。
3. **`@cImport` vs `zig translate-c`**  
   `limine.h` をすぐ使いたいなら `@cImport`、安定した Zig コードとして保持したいなら `zig translate-c` が向く。
4. **build.zig**  
   ルートの `build.zig` を唯一の入口にし、ISO 生成や QEMU 起動 step まで含める。

### Limine

- `CONFIG.md`: `protocol: limine`、`kernel_path`、`resolution` などの書式
- `USAGE.md`: ISO 生成時に必要な Limine ファイル
- `PROTOCOL.md`: Base Revision、HHDM、Framebuffer、Memory Map、Executable File
- `INSTALL.md`: Limine をソースからビルドする場合の依存

Limine protocol 上では、**すべてのポインタは原則 64-bit** で、特記がない限り **HHDM オフセット込み** で返る。  
さらに x86-64 ABI は **System V ABI without FP/SIMD** と明記されているため、最初期ブートコードでは浮動小数点や SIMD を前提にしない。

### QEMU / x86_64

- QEMU system emulation introduction
- `qemu-system-x86_64` man page
- Intel SDM Volume 1 / Volume 3

QEMU man page では:

- `-accel` の既定は **TCG**
- `-serial stdio` で COM1 を標準入出力へ流せる
- `-S` で CPU 停止開始
- `-s` は `-gdb tcp::1234` の短縮形
- `-d ...` で詳細ログ

となっている。  
つまり、自作 OS の最初のデバッグ線は **COM1 + GDB + QEMU trace** で十分戦える。

## 3. arm MacBook 側の準備

Homebrew を使うなら最小構成は次でよい。

```sh
brew install zig qemu xorriso
```

Limine をソースから組むなら追加で以下も入れる。

```sh
brew install nasm mtools
```

推奨確認:

```sh
zig version
qemu-system-x86_64 --version
xorriso -version
```

Zig は公式配布の `zig-aarch64-macos-0.15.2.tar.xz` を使ってもよい。  
Homebrew の `zig` formula も Apple Silicon で配布されている。

## 4. このリポジトリで整理すべき構成

このリポジトリでは、ビルド定義は **ルートの `build.zig`** に集約すべきである。  
少なくとも次のような構成に寄せると後で破綻しにくい。

```text
Zig-OS/
├── build.zig
├── linker.ld
├── limine.conf
├── include/
│   └── limine.h
├── src/
│   ├── main.zig
│   ├── serial.zig
│   └── arch/
│       └── x86_64/
│           ├── port_io.zig
│           ├── gdt.zig
│           ├── idt.zig
│           └── paging.zig
└── zig-out/
```

重要なのは次の分離である。

- `src/main.zig`
  - `_start` と最初の制御移譲だけ
- `src/arch/x86_64/*`
  - x86_64 固有処理
- `src/serial.zig`
  - serial 出力
- `linker.ld`
  - 高位配置と section 制御
- `limine.conf`
  - Limine menu entry と boot protocol 指定

## 5. 最初の到達目標

最初の milestone は非常に小さくてよい。

1. `zig build` で `kernel.elf` を生成する
2. ISO を作る
3. `qemu-system-x86_64` で起動する
4. COM1 に `"Hello from Zig OS!"` を出す
5. `hlt` で停止する

この段階では framebuffer すら不要である。  
画面表示より **serial first** の方が arm MacBook + x86_64 emulation の状況で切り分けしやすい。

## 6. Zig カーネル側の設計方針

### 6.1 build.zig

`build.zig` の責務は次の 4 つに限定するとよい。

1. `x86_64-freestanding-none` を target に設定する
2. `linker.ld` を明示する
3. `kernel.elf` を生成する
4. ISO 作成と QEMU 起動を step 化する

補足:

- `code_model = .kernel`
- `red_zone = false`
- entry は `_start`
- `build.zig` は **ルートに置く**

### 6.2 `src/main.zig`

最初は次だけでよい。

- Limine の base revision tag
- `export fn _start() noreturn`
- `panic` handler
- serial 出力
- `hlt`

### 6.3 Limine の request/response

最初に使うべき request は次の順がよい。

1. **Base Revision**
2. **HHDM**
3. **Memory Map**
4. **Framebuffer**
5. **Executable File**

理由:

- HHDM があると物理メモリへアクセスしやすい
- Memory Map がないと page allocator を作れない
- Framebuffer は画面表示に必須
- Executable File は自己再配置やモジュール処理の足場になる

### 6.4 実装すべきソースツリー

最初の数週間は、次の単位でファイルを分けるとよい。

```text
src/
├── main.zig
├── serial.zig
├── log.zig
├── boot/
│   └── limine.zig
├── memory/
│   ├── hhdm.zig
│   └── phys.zig
├── video/
│   └── framebuffer.zig
└── arch/
    └── x86_64/
        ├── port_io.zig
        ├── gdt.zig
        ├── idt.zig
        └── isr_stub.asm
```

依存関係は一方向に保つ。

- `main.zig`
  - 起動順序だけを書く
- `boot/limine.zig`
  - Boot protocol の型と helper
- `arch/x86_64/*`
  - x86_64 固有命令と descriptor table
- `memory/*`
  - HHDM 変換と物理ページ allocator
- `video/*`
  - framebuffer 操作
- `log.zig`
  - serial / framebuffer へログを流す薄い層

`main.zig` が巨大化すると bring-up が崩れるので、**main は配線だけ** にする。

### 6.5 `src/boot/limine.zig` の実装

最初は `@cImport` で `include/limine.h` を読み込むのが最短である。  
そのため `build.zig` で `include/` を Zig module の include path に追加する。

```zig
kernel.root_module.addIncludePath(b.path("include"));
```

`src/boot/limine.zig` は次のように薄く始めればよい。

```zig
pub const c = @cImport({
    @cInclude("limine.h");
});
```

ただし bring-up 初期は、必要最小限だけ **手書き `extern struct`** にした方が読みやすい。  
少なくとも次の型を定義する。

- `BaseRevision`
- `RequestsStartMarker`
- `RequestsEndMarker`
- `HhdmRequest` / `HhdmResponse`
- `MemmapRequest` / `MemmapResponse` / `MemmapEntry`
- `FramebufferRequest` / `FramebufferResponse` / `Framebuffer`

Limine のローカルヘッダにある magic 値は、そのまま Zig 側へ写してよい。  
たとえば request marker と base revision は次の形にできる。

```zig
pub const RequestsStartMarker = extern struct {
    marker: [4]u64 = .{
        0xf6b8f4b39de7d1ae,
        0xfab91a6940fcb9cf,
        0x785c6ed015d3e316,
        0x181e920a7852b9d9,
    },
};

pub const RequestsEndMarker = extern struct {
    marker: [2]u64 = .{
        0xadc0e0531bb10d03,
        0x9572709f31764c62,
    },
};

pub const BaseRevision = extern struct {
    tag: [3]u64 = .{
        0xf9562b2d5c95a6c8,
        0x6a7b384944536bdc,
        2,
    },
};
```

Request object も同様に定義する。

```zig
pub const HhdmResponse = extern struct {
    revision: u64,
    offset: u64,
};

pub const HhdmRequest = extern struct {
    id: [4]u64 = .{
        0xc7b1dd30df4c8b88,
        0x0a82e883a194f07b,
        0x48dcf1cb8ad2b852,
        0x63984e959a98244b,
    },
    revision: u64 = 0,
    response: ?*HhdmResponse = null,
};

pub const MemmapEntry = extern struct {
    base: u64,
    length: u64,
    type: u64,
};

pub const MemmapResponse = extern struct {
    revision: u64,
    entry_count: u64,
    entries: [*]*MemmapEntry,
};

pub const MemmapRequest = extern struct {
    id: [4]u64 = .{
        0xc7b1dd30df4c8b88,
        0x0a82e883a194f07b,
        0x67cf3d9d378a806f,
        0xe304acdfc50c3c62,
    },
    revision: u64 = 0,
    response: ?*MemmapResponse = null,
};

pub const Framebuffer = extern struct {
    address: ?*anyopaque,
    width: u64,
    height: u64,
    pitch: u64,
    bpp: u16,
    memory_model: u8,
    red_mask_size: u8,
    red_mask_shift: u8,
    green_mask_size: u8,
    green_mask_shift: u8,
    blue_mask_size: u8,
    blue_mask_shift: u8,
    unused: [7]u8,
    edid_size: u64,
    edid: ?*anyopaque,
    mode_count: u64,
    modes: ?*anyopaque,
};

pub const FramebufferResponse = extern struct {
    revision: u64,
    framebuffer_count: u64,
    framebuffers: [*]*Framebuffer,
};

pub const FramebufferRequest = extern struct {
    id: [4]u64 = .{
        0xc7b1dd30df4c8b88,
        0x0a82e883a194f07b,
        0x9d5827dcd881dd75,
        0xa3148604f6fab11b,
    },
    revision: u64 = 0,
    response: ?*FramebufferResponse = null,
};
```

この層の責務は **C ABI と Zig の橋渡しだけ** である。  
allocator や描画ロジックは絶対にここへ入れない。

### 6.6 `src/arch/x86_64/port_io.zig` と `src/serial.zig`

今のリポジトリは `outb` を `main.zig` に直書きしているが、すぐに分離した方がよい。  
まず `port_io.zig` に 1 命令 1 関数でまとめる。

```zig
pub inline fn out8(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
        : "memory"
    );
}

pub inline fn haltLoop() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}
```

`serial.zig` では UART の初期化と文字列出力を切り出す。  
QEMU の `-serial stdio` を前提にするなら COM1 (`0x3f8`) で十分である。

実装順は次でよい。

1. `init(base: u16)` を作る
2. divisor / line control / FIFO / modem control を設定する
3. `writeByte()` を作る
4. `writeString()` を作る
5. `\n` を `\r\n` に正規化する

重要なのは、**送信レジスタへ盲目的に書かない** ことである。  
最初のプロトタイプは今のような「そのまま書く」でも動く場合があるが、安定化のためには **Line Status Register bit 5** をポーリングしてから送信する。

### 6.7 `src/main.zig` の書き方

`main.zig` は「request 定義」「起動順序」「失敗時の停止」の 3 つだけに絞る。  
概念コードは次の形になる。

```zig
const std = @import("std");
const limine = @import("boot/limine.zig");
const serial = @import("serial.zig");
const io = @import("arch/x86_64/port_io.zig");
const phys = @import("memory/phys.zig");
const fb = @import("video/framebuffer.zig");

export var requests_start: limine.RequestsStartMarker = .{};
export var base_revision: limine.BaseRevision = .{};
export var hhdm_request: limine.HhdmRequest = .{};
export var memmap_request: limine.MemmapRequest = .{};
export var framebuffer_request: limine.FramebufferRequest = .{};
export var requests_end: limine.RequestsEndMarker = .{};

export fn _start() noreturn {
    serial.init(0x3f8);
    serial.writeString("boot: entered _start\r\n");

    const hhdm = hhdm_request.response orelse fatal("limine: no HHDM");
    const memmap = memmap_request.response orelse fatal("limine: no memmap");

    phys.init(hhdm.offset, memmap);
    serial.writeString("mem: allocator ready\r\n");

    if (framebuffer_request.response) |resp| {
        if (resp.framebuffer_count > 0) {
            fb.init(resp.framebuffers[0]);
            fb.clear(0x00202020);
        }
    }

    serial.writeString("boot: hello from Zig OS\r\n");
    io.haltLoop();
}

fn fatal(msg: []const u8) noreturn {
    serial.writeString(msg);
    serial.writeString("\r\n");
    io.haltLoop();
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    fatal(msg);
}
```

ポイント:

- request 群は **global export** にする
- request は **start/end marker の間** に置く
- `_start` でいきなり複雑な処理をしない
- 失敗時は必ず serial に理由を出す

### 6.8 `src/memory/hhdm.zig` と `src/memory/phys.zig`

最初の allocator は **bump allocator** で十分である。  
free list や buddy allocator は後回しにする。

`hhdm.zig` には変換 helper だけを書く。

```zig
var g_hhdm_offset: u64 = 0;

pub fn init(offset: u64) void {
    g_hhdm_offset = offset;
}

pub fn physToVirt(addr: u64) u64 {
    return addr + g_hhdm_offset;
}

pub fn virtToPhys(addr: u64) u64 {
    return addr - g_hhdm_offset;
}
```

`phys.zig` は「usable な領域だけを走査して 4 KiB page を返す」最低限でよい。  
実装手順は次の順にすると壊れにくい。

1. `LIMINE_MEMMAP_USABLE` な entry だけ集める
2. `base` を 4 KiB 境界へ切り上げる
3. `length` を page 単位へ丸める
4. 現在 region と next pointer を保持する
5. `allocPage()` で 4096 byte ずつ進める

この段階では:

- `BOOTLOADER_RECLAIMABLE`
- `EXECUTABLE_AND_MODULES`
- `FRAMEBUFFER`

を allocation 対象に入れない。  
最初は「使えるページが返る」だけで十分である。

### 6.9 `src/video/framebuffer.zig`

Framebuffer は「描画 API」ではなく、まず **生ポインタへ安全に 1 pixel 書ける層** として作る。  
最初に持つべき関数は次の 4 つだけでよい。

- `init(raw_fb)`
- `putPixel(x, y, color)`
- `clear(color)`
- `fillRect(x, y, w, h, color)`

実装上の注意:

- `memory_model` が RGB か確認する
- `bpp == 32` 前提で始める
- `pitch` は `width * 4` と仮定しない
- `address` は `[*]volatile u8` または `[*]u8` で扱う

最初の見える成果物としては、起動後に画面全体を単色で塗るだけでよい。  
文字描画やフォントはその後である。

### 6.10 `src/arch/x86_64/gdt.zig` / `idt.zig`

Descriptor table までは Zig だけでも書けるが、**ISR stub だけは小さなアセンブリファイルへ逃がす** 方が現実的である。  
理由は、割り込み entry/exit の prologue/epilogue は Zig inline asm より独立した asm の方が読みやすく、壊れ方も追いやすいからである。

順序は次でよい。

1. GDT: null / kernel code / kernel data の最小 3 entry
2. `lgdt`
3. IDT: 例外ベクタ 0-31 だけ登録
4. すべて同じ共通 handler へ飛ばす
5. common handler で vector 番号を serial 出力
6. その場で停止

この段階では PIC/APIC の初期化やユーザー空間用 descriptor は不要である。

### 6.11 `src/log.zig`

log 層は非常に小さく保つ。

- boot 初期
  - serial のみ
- framebuffer 初期化後
  - serial + 画面

たとえば `log.info("mem: ready")` を呼ぶと、内部では serial と framebuffer の両方へ流す。  
これを先に作っておくと、以後の allocator、interrupt、paging 実装で観測点を増やしやすい。

### 6.12 どこまでを `zig test` するか

カーネル入口そのものは host 上でそのまま `zig test` しにくい。  
したがって test しやすい部分を明確に分離する。

- test する
  - address alignment
  - HHDM 変換
  - memmap filtering
  - bump allocator の進み方
  - rectangle clipping
- test しない
  - `hlt`
  - `outb`
  - `lgdt`
  - `lidt`
  - 割り込み entry stub

方針としては、**CPU 命令は薄く包むだけ、ロジックは pure function に寄せる** のが Zig と相性がよい。

## 7. Limine の導入方針

### 7.1 まずは binary release を使う

Limine 公式 README では、point release の binary branch が提供されている。  
最短経路はそれを利用して host utility と boot files を得る方法である。

例:

```sh
git clone https://github.com/Limine-Bootloader/Limine.git --branch=v11.x-binary --depth=1 vendor/limine
make -C vendor/limine
```

### 7.2 `limine.conf`

最初の設定は小さくてよい。

```cfg
TIMEOUT=0

:My Zig OS
  PROTOCOL=limine
  KERNEL_PATH=boot://kernel.elf
```

公式 `CONFIG.md` 上では、`protocol` に `limine` を指定し、`kernel_path` は `path` の alias である。  
必要になったら `resolution`, `module_path`, `cmdline` を追加する。

## 8. ISO 生成の実務

### 8.1 最初は BIOS-only でよい

Limine 公式の `USAGE.md` では、`limine.conf` と `limine-bios.sys` は root / `limine` / `boot` / `boot/limine` のいずれかに置ける。  
このリポジトリでは分かりやすさを優先し、設定ファイルは root、カーネル本体は `boot/` に置くのがよい。

概念的には次の配置になる。

```text
iso_root/
├── limine.conf
├── limine-bios.sys
└── boot/
    ├── kernel.elf
    └── limine-bios-cd.bin
```

生成例:

```sh
xorriso -as mkisofs \
  -b boot/limine-bios-cd.bin \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  iso_root \
  -o zig-out/myos-bios.iso
```

その後:

```sh
vendor/limine/limine bios-install zig-out/myos-bios.iso
```

### 8.2 後で UEFI/hybrid ISO に拡張する

Limine 公式 `USAGE.md` には hybrid ISO の手順もある。  
ただし最初から UEFI を混ぜると、問題が Zig 側なのか Limine 側なのか ISO 生成なのか切り分けにくい。  
**最初の 1 本目は BIOS-only** を推奨する。

UEFI/hybrid へ進むときは、さらに次を ISO root に加える。

```text
iso_root/
├── limine-uefi-cd.bin
└── EFI/
    └── BOOT/
        └── BOOTX64.EFI
```

## 9. arm MacBook 上での QEMU 実行

Apple Silicon 上では、まず **TCG を明示** した方が意図がぶれない。

```sh
qemu-system-x86_64 \
  -machine pc,accel=tcg \
  -cpu qemu64 \
  -m 512M \
  -smp 2 \
  -serial stdio \
  -cdrom zig-out/myos-bios.iso \
  -no-reboot \
  -no-shutdown
```

ポイント:

- `-serial stdio`
  - COM1 (`0x3f8`) 出力をそのまま観測できる
- `-no-reboot`
  - triple fault や panic 時に即再起動せず原因を追いやすい
- `-machine ...,accel=tcg`
  - Apple Silicon 上の x86_64 開発で「まず確実に動く」構成

TCG は multi-thread にできる。

```sh
-accel tcg,thread=multi
```

ただし初期 bring-up では性能より再現性を優先し、まずはシンプルな引数で固定する方がよい。

## 10. デバッグ手順

### 10.1 Serial

最初は COM1 だけで十分。  
今のリポジトリのように `outb(0x3f8, c)` を使うなら `-serial stdio` を使う。

### 10.2 GDB

```sh
qemu-system-x86_64 \
  -machine pc,accel=tcg \
  -cpu qemu64 \
  -m 512M \
  -serial stdio \
  -cdrom zig-out/myos-bios.iso \
  -s -S
```

別端末で:

```sh
gdb kernel.elf
(gdb) target remote :1234
(gdb) b _start
(gdb) c
```

### 10.3 QEMU trace

```sh
qemu-system-x86_64 ... -d guest_errors,cpu_reset,int -D qemu.log
```

これは page fault、割り込み設定ミス、リセット原因の切り分けに有効である。

## 11. 実装順序の推奨ロードマップ

1. **serial 出力**
2. **Limine HHDM / Memory Map 取得**
3. **bump allocator**
4. **physical page allocator**
5. **GDT / IDT / 例外ハンドラ**
6. **framebuffer console**
7. **timer / keyboard**
8. **heap allocator**
9. **ELF loader**
10. **ユーザーモード / syscall**
11. **VFS**
12. **Arch Linux 互換に向けた ABI 整備**

もし本当に Arch Linux 互換ユーザーランドを目指すなら、最低でも次が必要になる。

- ELF64 実行
- 仮想メモリ
- fork/exec 相当
- ファイルシステム
- tty / pty
- `mmap`, `clone`, signal, futex 周辺の syscall

これは「最初の kernel bring-up」とは別フェーズである。

## 12. Zig で OS を書くときの実践パターン

### 推奨

- `extern struct` で boot protocol / C ABI に合わせる
- `@cImport` でまず Limine header を取り込む
- 落ち着いたら `zig translate-c` か手書き Zig 型へ移行する
- `arch/x86_64` に依存を閉じ込める
- pure function を分離し、host 上で `zig test` できる形にする

### 非推奨

- `_start` に全ロジックを書く
- 初期段階から framebuffer だけでデバッグする
- build ロジックを複数箇所に分散する
- page table / allocator / interrupt を同時に入れる

## 13. 参考資料

### 一次資料

- Zig Download: https://ziglang.org/download/
- Zig Language Reference 0.15.2: https://ziglang.org/documentation/0.15.2/
- QEMU Introduction: https://www.qemu.org/docs/master/system/introduction.html
- QEMU `qemu-system-x86_64` man page: https://www.qemu.org/docs/master/system/qemu-manpage.html
- Limine README: https://github.com/Limine-Bootloader/Limine
- Limine `CONFIG.md`: https://github.com/Limine-Bootloader/Limine/blob/v11.x/CONFIG.md
- Limine `USAGE.md`: https://github.com/Limine-Bootloader/Limine/blob/v11.x/USAGE.md
- Limine `INSTALL.md`: https://github.com/Limine-Bootloader/Limine/blob/v11.x/INSTALL.md
- Limine Protocol: https://github.com/Limine-Bootloader/limine-protocol/blob/trunk/PROTOCOL.md
- Homebrew `zig`: https://formulae.brew.sh/formula/zig
- Homebrew `qemu`: https://formulae.brew.sh/formula/qemu
- Homebrew `xorriso`: https://formulae.brew.sh/formula/xorriso
- Intel SDM overview: https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html

### 二次資料

以下は仕様書の代わりには使わず、**実装の勘所を掴む補助** として使う。

- OSDev Wiki `x86-64`: https://wiki.osdev.org/X86-64
- OSDev Wiki `GDT Tutorial`: https://wiki.osdev.org/GDT_Tutorial
- OSDev Wiki `Interrupt Descriptor Table`: https://wiki.osdev.org/Interrupt_Descriptor_Table

## 14. 最短の次アクション

このリポジトリで次にやるべきことは次の 3 つである。

1. ルートの `build.zig` を正しい Zig 0.15.2 API で実装する
2. BIOS-only ISO を `zig build` から生成する
3. `zig build run` で上の QEMU コマンドを step 化する

この 3 つが揃えば、arm MacBook 上でも「編集 → build → boot → serial 観測」のループを固定できる。
