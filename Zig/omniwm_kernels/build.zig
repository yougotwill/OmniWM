// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.linkSystemLibrary("c", .{});

    module.addIncludePath(b.path("../../Sources/COmniWMKernels/include"));

    const lib = b.addLibrary(.{
        .name = "omniwm_kernels",
        .linkage = .static,
        .root_module = module,
    });
    lib.bundle_compiler_rt = true;
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run OmniWM kernel Zig tests");
    test_step.dependOn(&run_tests.step);
}
