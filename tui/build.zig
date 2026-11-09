const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const lib = b.addLibrary(.{
        .name = "qs_tui",
        .linkage = .dynamic,
        .root_module = mod,
    });
    b.installArtifact(lib);

    // The quicksort binary dlopen()s build/libqs_tui.so relative to the repo root.
    // Copy the artifact to build/libqs_tui.so whether build is invoked from repo root or tui/.
    const copy = b.addSystemCommand(&.{
        "sh", "-c",
        \\if [ -f Makefile ]; then
        \\    mkdir -p build && cp -f "$1" build/libqs_tui.so
        \\elif [ -f ../Makefile ]; then
        \\    mkdir -p ../build && cp -f "$1" ../build/libqs_tui.so
        \\fi
        , "qs-tui-copy",
    });
    copy.addArtifactArg(lib);
    b.getInstallStep().dependOn(&copy.step);
}
