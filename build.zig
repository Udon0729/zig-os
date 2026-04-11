const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const kernel_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .pic = false,
        .strip = false,
        .red_zone = false,
        .code_model = .kernel,
    });

    // @cImport("limine.h")を使うなら有効化する
    kernel_module.addIncludePath(b.path("include"));

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_module = kernel_module,
    });

    kernel.setLinkerScript(b.path("linker.ld"));
    kernel.entry = .{ .symbol_name = "_start"};
    kernel.pie = false;

    const install_kernel = b.addInstallArtifact(kernel, .{
        .dest_dir = .{ .override = .{ .custom = "iso/boot" } },
        .dest_sub_path = "kernel.elf",
    });

    // ISOルート用にlimine.confもstagingしておく
    b.installFile("limine.conf", "iso/limine.conf");

    const kernel_step = b.step("kernel", "Build the freestanding x86_64 kernel");
    kernel_step.dependOn(&install_kernel.step);
}
