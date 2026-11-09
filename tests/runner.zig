const std = @import("std");
const builtin = @import("builtin");

const ansi = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
    const red = "\x1b[31m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const cyan = "\x1b[36m";
};

pub const std_options: std.Options = .{
    .logFn = log,
};

var log_err_count: usize = 0;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime fmt: []const u8,
    args: anytype,
) void {
    @disableInstrumentation();
    if (@intFromEnum(level) <= @intFromEnum(std.log.Level.err))
        log_err_count +|= 1;
    if (@intFromEnum(level) <= @intFromEnum(std.testing.log_level)) {
        std.debug.print(
            "[" ++ @tagName(scope) ++ "] (" ++ @tagName(level) ++ "): " ++ fmt ++ "\n",
            args,
        );
    }
}

const ParsedName = struct { section: ?[]const u8, rest: []const u8 };

fn parseSection(name: []const u8) ParsedName {
    if (std.mem.indexOf(u8, name, ": ")) |colon_idx| {
        const before_colon = name[0..colon_idx];
        if (std.mem.lastIndexOf(u8, before_colon, "test.")) |test_idx| {
            const section = before_colon[test_idx + 5 ..];
            return .{
                .section = section,
                .rest = name[colon_idx + 2 ..],
            };
        }
        return .{
            .section = before_colon,
            .rest = name[colon_idx + 2 ..],
        };
    }
    return .{ .section = null, .rest = name };
}

const Duration = struct { value: u64, unit: []const u8 };

fn formatDuration(ns: u64) Duration {
    if (ns >= 5_000_000_000) {
        return .{ .value = ns / 1_000_000_000, .unit = "s" };
    } else if (ns >= 5_000_000) {
        return .{ .value = ns / 1_000_000, .unit = "ms" };
    } else if (ns >= 5_000) {
        return .{ .value = ns / 1_000, .unit = "μs" };
    } else {
        return .{ .value = ns, .unit = "ns" };
    }
}

fn countDigits(n: usize) usize {
    if (n == 0) return 1;
    var count: usize = 0;
    var val = n;
    while (val > 0) : (val /= 10) count += 1;
    return count;
}

fn processResult(
    result: anyerror!void,
    passed: *usize,
    failed: *usize,
    skipped: *usize,
    colors: type,
    parsed: ParsedName,
    index: usize,
    total: usize,
    elapsed_ns: u64,
    has_leak: bool,
) void {
    const duration = formatDuration(elapsed_ns);
    var test_failed = false;
    var error_msg: ?anyerror = null;
    var fail_reason: []const u8 = "";

    if (result) |_| {
        if (log_err_count != 0) {
            failed.* += 1;
            test_failed = true;
            fail_reason = "error logs";
        } else {
            passed.* += 1;
        }
    } else |err| switch (err) {
        error.SkipZigTest => {
            skipped.* += 1;
            printTestLine(colors, colors.yellow, " SKIP ", parsed, index, total, duration);
            return;
        },
        else => {
            failed.* += 1;
            test_failed = true;
            error_msg = err;
        },
    }

    if (test_failed) {
        printTestLine(colors, colors.red, "FAILED", parsed, index, total, duration);
    } else {
        printTestLine(colors, colors.green, "  OK  ", parsed, index, total, duration);
    }

    if (test_failed) {
        if (error_msg) |err| {
            std.debug.print("         {s}└─ {any}{s}\n", .{ colors.red, err, colors.reset });
        } else if (fail_reason.len > 0) {
            std.debug.print("         {s}└─ {s}{s}\n", .{ colors.red, fail_reason, colors.reset });
        }
        if (has_leak) {
            std.debug.print("         {s}└─ memory leak detected{s}\n", .{ colors.yellow, colors.reset });
        }
    }
}

fn printTestLine(
    c: type,
    status_color: []const u8,
    status_text: []const u8,
    parsed: ParsedName,
    index: usize,
    total: usize,
    duration: Duration,
) void {
    std.debug.print("[{s}{s}{s}{s}] ", .{ c.bold, status_color, status_text, c.reset });

    var name_len: usize = 0;
    if (parsed.section) |section| {
        std.debug.print("{s}{s}{s}: {s}", .{ c.bold, section, c.reset, parsed.rest });
        name_len = section.len + 2 + parsed.rest.len;
    } else {
        std.debug.print("{s}", .{parsed.rest});
        name_len = parsed.rest.len;
    }

    const unit_display_len: usize = switch (duration.unit.len) {
        1 => 1,
        else => 2,
    };

    const counter_width = countDigits(total);
    const suffix_len =
        1 +
        1 +
        countDigits(duration.value) +
        unit_display_len +
        1 +
        counter_width +
        1 +
        counter_width +
        1;

    const prefix_len: usize = 9;
    const used = prefix_len + name_len + suffix_len;
    const target_width: usize = 120;

    if (used < target_width) {
        const padding = target_width - used;
        for (0..padding) |_| std.debug.print(" ", .{});
    }

    std.debug.print(
        " {s}{d}{s} ({d:[6]}/{d:[6]}){s}\n",
        .{
            c.dim,
            duration.value,
            duration.unit,
            index + 1,
            total,
            c.reset,
            counter_width,
        },
    );
}

pub fn main(init: std.process.Init.Minimal) void {
    @disableInstrumentation();

    const total: usize = builtin.test_functions.len;
    var passed: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;
    var leaks: usize = 0;

    const colors = ansi;

    std.debug.print(
        "{s}{s}Running {d} test{s}...{s}\n",
        .{ colors.bold, colors.cyan, total, if (total == 1) "" else "s", colors.reset },
    );

    for (builtin.test_functions, 0..) |test_fn, i| {
        std.testing.allocator_instance = .init(std.heap.page_allocator, .{
            .canary = 0xc3a701ba,
            .check_write_after_free = true,
        });
        std.testing.io_instance = .init(std.testing.allocator, .{
            .argv0 = .init(init.args),
            .environ = init.environ,
        });
        var has_leak = false;
        defer {
            std.testing.io_instance.deinit();
            if (std.testing.allocator_instance.deinit() != 0) {
                leaks += 1;
                has_leak = true;
            }
        }
        std.testing.log_level = .warn;
        std.testing.environ = init.environ;
        log_err_count = 0;

        const parsed = parseSection(test_fn.name);

        var start_ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(.MONOTONIC, &start_ts);
        const result = test_fn.func();
        var end_ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(.MONOTONIC, &end_ts);
        const start_ns: i128 = @as(i128, start_ts.sec) * 1_000_000_000 + start_ts.nsec;
        const end_ns: i128 = @as(i128, end_ts.sec) * 1_000_000_000 + end_ts.nsec;
        const elapsed_ns: u64 = @intCast(@max(0, end_ns - start_ns));

        processResult(result, &passed, &failed, &skipped, colors, parsed, i, total, elapsed_ns, has_leak);
    }

    std.debug.print("\n", .{});
    const status_color = if (failed > 0 or leaks > 0) colors.red else colors.green;
    const status_word = if (failed > 0 or leaks > 0) "FAILED" else "PASSED";
    std.debug.print(
        "{s}{s}{s}: {s}{d} passed{s}",
        .{ colors.bold, status_color, status_word, colors.green, passed, colors.reset },
    );
    if (failed > 0)
        std.debug.print(", {s}{d} failed{s}", .{ colors.red, failed, colors.reset });
    if (skipped > 0)
        std.debug.print(", {s}{d} skipped{s}", .{ colors.yellow, skipped, colors.reset });
    if (leaks > 0)
        std.debug.print(", {s}{d} leaked{s}", .{ colors.yellow, leaks, colors.reset });
    std.debug.print("\n", .{});

    if (failed > 0 or leaks > 0)
        std.process.exit(1);
}
