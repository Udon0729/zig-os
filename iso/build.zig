const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // resolveTargetQuery: ホスト向けではなく、OSカーネル向けのfreestandingターゲットにする
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
            .pic = false,
            .strip = false,
            // code_model: 高位アドレスに置くx86_64カーネル向け
            .code_model = .kernel,
        }),
    });

    kernel.setLinkerScript(b.path("Linker.ld"));
    // kernel.entry: エントリポイントをmainではなく_startにする
    kernel.entry = .{ .symbol_name = "_start"};
    kernel.pie = false;
    // red_zone = false: カーネルでは無効化しておくのが無難
    kernel.root_module.red_zone = false;

    // addInstallArtifact: zig build後にzig-out/iso/boot/kernel.elfを得る
    const install_kernel = b.addInstallArtifact(kernel, .{
        .dest_dir = .{ .override = .{ custom = "iso/boot" }}
        .dest_sub_path + "kernel.elf",
    });
    b.getInstallStep().dependOn(&install_kernel.step);

    b.installFile("limine.conf", "limine.conf");
}
