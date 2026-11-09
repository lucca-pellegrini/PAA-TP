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
    "src/parser.c",
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

    // Flex/Bison generation mirrors the root Makefile (src/parser.{l,y}).
    const bison = b.addSystemCommand(&.{ "bison", "-d" });
    const parser_tab_h = bison.addPrefixedOutputFileArg("--defines=", "parser.tab.h");
    bison.addArg("-o");
    const parser_tab_c = bison.addOutputFileArg("parser.tab.c");
    bison.addFileArg(b.path("../src/parser.y"));

    const flex = b.addSystemCommand(&.{"flex"});
    const parser_lex_h = flex.addPrefixedOutputFileArg("--header-file=", "parser.lex.h");
    flex.addArg("-o");
    const parser_lex_c = flex.addOutputFileArg("parser.lex.c");
    flex.addFileArg(b.path("../src/parser.l"));

    test_mod.addIncludePath(.{ .cwd_relative = "include" });
    test_mod.addIncludePath(parser_tab_h.dirname());
    test_mod.addIncludePath(parser_lex_h.dirname());
    test_mod.linkSystemLibrary("dl", .{});
    test_mod.linkSystemLibrary("m", .{});
    test_mod.addCSourceFiles(.{
        .root = .{ .cwd_relative = "." },
        .files = c_lib_sources,
        .flags = c_flags,
    });
    test_mod.addCSourceFile(.{ .file = parser_tab_c, .flags = c_flags });
    test_mod.addCSourceFile(.{ .file = parser_lex_c, .flags = c_flags });

    const tests = b.addTest(.{
        .root_module = test_mod,
        .test_runner = .{
            .path = b.path("runner.zig"),
            .mode = .simple,
        },
    });
    tests.rdynamic = true;

    // Installed test binary consumed by `make cov` (kcov).
    const install_tests = b.addInstallArtifact(tests, .{
        .dest_sub_path = "test_runner",
    });
    const test_exe_step = b.step("test-exe", "Build the test binary for kcov");
    test_exe_step.dependOn(&install_tests.step);

    const run_tests = b.addRunArtifact(tests);
    run_tests.setEnvironmentVariable("__QS_UI_SHUT_UP", "1");
    run_tests.stdio = .inherit;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
