const std = @import("std");

const c_lib_sources: []const []const u8 = &.{
    "src/sysinfo.c",
    "src/pbar.c",
    "src/ui.c",
    "src/vec.c",
    "src/threadpool.c",
    "src/quicksort_kernel.c",
    "src/metrics.c",
    "src/jit.c",
};

const c_flags: []const []const u8 = &.{
    "-std=c23",
    "-Wall",
    "-Wextra",
    "-Wpedantic",
    "-D_GNU_SOURCE",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    test_mod.addIncludePath(.{ .cwd_relative = "include" });
    test_mod.linkSystemLibrary("dl", .{});
    test_mod.linkSystemLibrary("m", .{});
    test_mod.addCSourceFiles(.{
        .root = .{ .cwd_relative = "." },
        .files = c_lib_sources,
        .flags = c_flags,
    });

    const tests = b.addTest(.{
        .root_module = test_mod,
        .test_runner = .{
            .path = b.path("runner.zig"),
            .mode = .simple,
        },
    });
    tests.rdynamic = true;

    const run_tests = b.addRunArtifact(tests);
    run_tests.setEnvironmentVariable("__QS_UI_SHUT_UP", "1");
    run_tests.stdio = .inherit;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
