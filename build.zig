const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const sdk = resolveMacOsSdk(b);

    const lib_arm64 = addOmniLayoutLibrary(
        b,
        optimize,
        b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .macos }),
        sdk,
    );
    const lib_x86_64 = addOmniLayoutLibrary(
        b,
        optimize,
        b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .macos }),
        sdk,
    );

    const lipo = b.addSystemCommand(&.{ "lipo", "-create", "-output" });
    const universal_lib = lipo.addOutputFileArg("libomni_layout.a");
    lipo.addFileArg(lib_arm64.getEmittedBin());
    lipo.addFileArg(lib_x86_64.getEmittedBin());

    const install_universal = b.addInstallFile(universal_lib, "zig/libomni_layout.a");
    const omni_layout_step = b.step("omni-layout", "Build universal libomni_layout.a into <prefix>/zig");
    omni_layout_step.dependOn(&install_universal.step);

    const phase0_exe = b.addExecutable(.{
        .name = "omniwm_phase0",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig/app/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const objc_module = b.createModule(.{
        .root_source_file = b.path("zig/platform/objc.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cocoa_module = b.createModule(.{
        .root_source_file = b.path("zig/platform/cocoa.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cf_module = b.createModule(.{
        .root_source_file = b.path("zig/platform/cf.zig"),
        .target = target,
        .optimize = optimize,
    });
    cocoa_module.addImport("objc_platform", objc_module);
    phase0_exe.root_module.addImport("objc_platform", objc_module);
    phase0_exe.root_module.addImport("cocoa_platform", cocoa_module);
    phase0_exe.root_module.addImport("cf_platform", cf_module);
    configureMacSdk(phase0_exe.root_module, sdk);
    linkPlatformLibraries(phase0_exe.root_module);
    phase0_exe.root_module.linkSystemLibrary("objc", .{});
    phase0_exe.root_module.addObjectFile(b.path("Frameworks/GhosttyKit.xcframework/macos-arm64_x86_64/libghostty.a"));

    const install_phase0 = b.addInstallArtifact(phase0_exe, .{});
    const phase0_step = b.step("phase0", "Build the standalone Zig phase0 bootstrap executable");
    phase0_step.dependOn(&install_phase0.step);

    const run_phase0_cmd = b.addRunArtifact(phase0_exe);
    run_phase0_cmd.step.dependOn(&install_phase0.step);
    if (b.args) |args| {
        run_phase0_cmd.addArgs(args);
    }
    const run_phase0_step = b.step("run-phase0", "Run the standalone Zig phase0 bootstrap executable");
    run_phase0_step.dependOn(&run_phase0_cmd.step);

    const zig_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig/omni_layout.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    configureMacSdk(zig_tests.root_module, sdk);
    linkPlatformLibraries(zig_tests.root_module);
    zig_tests.root_module.linkSystemLibrary("objc", .{});

    const run_tests = b.addRunArtifact(zig_tests);
    const test_step = b.step("test-zig", "Run Zig tests with macOS framework linkage");
    test_step.dependOn(&run_tests.step);

    b.default_step.dependOn(omni_layout_step);
}

fn addOmniLayoutLibrary(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
    sdk: MacSdk,
) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "omni_layout",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig/omni_layout.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    configureMacSdk(lib.root_module, sdk);
    lib.root_module.link_libc = true;
    return lib;
}

fn linkPlatformLibraries(module: *std.Build.Module) void {
    module.link_libc = true;
    module.linkFramework("AppKit", .{});
    module.linkFramework("ApplicationServices", .{});
    module.linkFramework("Carbon", .{});
    module.linkFramework("CoreGraphics", .{});
    module.linkFramework("IOKit", .{});
    module.linkFramework("CoreFoundation", .{});
    module.linkFramework("QuartzCore", .{});
    module.linkFramework("Metal", .{});
    module.linkFramework("MetalKit", .{});
}

const MacSdk = struct {
    frameworks_path: []const u8,
    include_path: []const u8,
};

fn resolveMacOsSdk(b: *std.Build) MacSdk {
    const sdk_path = blk: {
        if (b.graph.env_map.get("SDKROOT")) |sdkroot| {
            if (sdkroot.len > 0) break :blk b.dupePath(sdkroot);
        }

        const xcrun = b.findProgram(&.{"xcrun"}, &.{}) catch {
            std.debug.panic("could not find xcrun and SDKROOT is not set", .{});
        };
        const output = b.run(&.{ xcrun, "--sdk", "macosx", "--show-sdk-path" });
        break :blk std.mem.trim(u8, output, " \n\r\t");
    };

    return .{
        .frameworks_path = b.pathJoin(&.{ sdk_path, "System/Library/Frameworks" }),
        .include_path = b.pathJoin(&.{ sdk_path, "usr/include" }),
    };
}

fn configureMacSdk(module: *std.Build.Module, sdk: MacSdk) void {
    module.addSystemFrameworkPath(.{ .cwd_relative = sdk.frameworks_path });
    module.addSystemIncludePath(.{ .cwd_relative = sdk.include_path });
}
