const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // resolveTargetQuery: ホスト向けではなく、OSカーネル向けのfreestandingターゲットにする
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
        // No SIMD/FPU setup or context saving exists in the kernel yet.
        .cpu_features_sub = std.Target.x86.featureSet(&.{ .mmx, .sse, .sse2, .avx, .avx2, .x87 }),
    });

    const kernel_obj = b.addObject(.{
        .name = "kernel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
            // No hosted stack-probe runtime or demand-grown stack is available.
            .stack_check = false,
            .pic = true,
            .strip = false,
            // code_model: 高位アドレスに置くx86_64カーネル向け
            .code_model = .kernel,
        }),
    });

    // red_zone = false: カーネルでは無効化しておくのが無難
    kernel_obj.root_module.red_zone = false;

    const lowlevel_obj_cmd = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "cc",
        "-c",
        "-x",
        "assembler-with-cpp",
        "-target",
        "x86_64-freestanding-none",
        "-o",
    });
    lowlevel_obj_cmd.setName("assemble lowlevel");
    const lowlevel_obj = lowlevel_obj_cmd.addOutputFileArg("lowlevel-x86_64.o");
    lowlevel_obj_cmd.addFileArg(b.path("src/arch/x86_64/lowlevel.S"));

    const link_kernel = b.addSystemCommand(&.{ b.graph.zig_exe, "ld.lld" });
    link_kernel.addArgs(&.{
        "-m",        "elf_x86_64",
        "-nostdlib", "-T",
        "linker.ld",
    });
    link_kernel.addFileArg(kernel_obj.getEmittedBin());
    link_kernel.addFileArg(lowlevel_obj);
    link_kernel.addArg("-o");
    const linked_kernel = link_kernel.addOutputFileArg("kernel.elf");

    const install_kernel = b.addInstallFile(linked_kernel, "iso/boot/kernel.elf");
    const install_limine_conf = b.addInstallFile(b.path("limine.conf"), "iso/limine.conf");
    const install_bios_sys = b.addInstallFile(b.path("vendor/limine/limine-bios.sys"), "iso/limine-bios.sys");
    const install_bios_cd = b.addInstallFile(b.path("vendor/limine/limine-bios-cd.bin"), "iso/boot/limine-bios-cd.bin");
    // assets/initrd/ を tar で固めて /boot/initrd.tar として ISO に配置する
    const initrd_tar = b.addSystemCommand(&.{ "tar", "--format=ustar", "-cf" });
    initrd_tar.setEnvironmentVariable("COPYFILE_DISABLE", "1");
    const archive = initrd_tar.addOutputFileArg("initrd.tar");
    initrd_tar.addArg("-C");
    initrd_tar.addDirectoryArg(b.path("assets/initrd"));
    initrd_tar.addArg(".");
    const install_initrd = b.addInstallFile(archive, "iso/boot/initrd.tar");

    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    }) });
    b.step("test", "Test archive and rootfs validation").dependOn(&b.addRunArtifact(tests).step);

    const kernel_step = b.step("kernel", "Build the freestanding x86_64 kernel");
    kernel_step.dependOn(&install_kernel.step);
    kernel_step.dependOn(&install_limine_conf.step);

    b.getInstallStep().dependOn(&install_kernel.step);
    b.getInstallStep().dependOn(&install_limine_conf.step);

    const iso_cmd = b.addSystemCommand(&.{
        "xorriso",
        "-as",
        "mkisofs",
        "-b",
        "boot/limine-bios-cd.bin",
        "-no-emul-boot",
        "-boot-load-size",
        "4",
        "-boot-info-table",
        "zig-out/iso",
        "-o",
        "zig-out/myos-bios.iso",
    });
    iso_cmd.setName("build iso");
    iso_cmd.step.dependOn(&install_kernel.step);
    iso_cmd.step.dependOn(&install_limine_conf.step);
    iso_cmd.step.dependOn(&install_bios_sys.step);
    iso_cmd.step.dependOn(&install_bios_cd.step);
    iso_cmd.step.dependOn(&install_initrd.step);

    const bios_install = b.addSystemCommand(&.{
        "vendor/limine/limine",
        "bios-install",
        "zig-out/myos-bios.iso",
    });
    bios_install.setName("install limine bios");
    bios_install.step.dependOn(&iso_cmd.step);

    const iso_step = b.step("iso", "Build a bootable Limine BIOS ISO");
    iso_step.dependOn(&bios_install.step);

    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-machine",
        "pc,accel=tcg",
        "-cpu",
        "qemu64",
        "-m",
        "512M",
        "-serial",
        "stdio",
        "-cdrom",
        "zig-out/myos-bios.iso",
        "-no-reboot",
        "-no-shutdown",
    });
    run_cmd.setName("run qemu");
    run_cmd.stdio = .inherit;
    run_cmd.step.dependOn(&bios_install.step);

    const run_step = b.step("run", "Boot the kernel in QEMU");
    run_step.dependOn(&run_cmd.step);
}
