const std = @import("std");
const testing = std.testing;

const c = struct {
    pub const QsOrder = c_uint;
    pub const QS_ORDER_ASC: QsOrder = 0;

    pub const QsPartition = c_uint;
    pub const QsPivot = c_uint;
    pub const QsSmallSort = c_uint;
    pub const QsExecMode = c_uint;

    pub const QsVec = extern struct {
        data: [*]c_int,
        len: usize,
        cap: usize,
        multiset_hash: u64,
    };

    pub const QsThreadPool = opaque {};

    pub const QsConfig = extern struct {
        partition: QsPartition,
        pivot: QsPivot,
        small_sort: QsSmallSort,
        exec_mode: QsExecMode,
        order: QsOrder,
        cutoff: usize,
        max_depth: usize,
        parallel_threshold: usize,
        introsort_fallback: bool,
        seed: u64,
        pool: ?*QsThreadPool,
    };

    pub const QsRunStats = extern struct {
        comparisons: u64,
        swaps: u64,
        moves: u64,
        max_depth_reached: usize,
        bad_partitions: usize,
        heapsort_fallbacks: usize,
        depth_limit_exceeded: bool,
    };

    pub const QsKernelFn = *const fn (arr: [*]c_int, n: usize, cfg: *const QsConfig, stats: ?*QsRunStats) callconv(.c) bool;

    pub const QsPerfSnapshot = extern struct {
        monotonic_ns: u64,
        cpu_cycles: u64,
        instructions: u64,
        branch_instructions: u64,
        branch_misses: u64,
        l1d_misses: u64,
        llc_misses: u64,
        pmu_available: bool,
    };

    pub const QsMetricsCtx = opaque {};

    pub const QsJitOptions = extern struct {
        cc: ?[*:0]const u8,
        cflags: ?[*:0]const u8,
        pragma_unroll_count: c_uint,
        pragma_no_unroll: bool,
        pragma_vectorize: bool,
        pragma_no_vectorize: bool,
        emit_asm: bool,
        force_recompile: bool,
    };

    pub const QsJitModule = extern struct {
        dl_handle: ?*anyopaque,
        run_clean: ?QsKernelFn,
        run_counted: ?QsKernelFn,
        key_hash: u64,
        so_path: [256]u8,
        asm_path: [256]u8,
        is_static_fastpath: bool,
    };

    pub const QsJitCache = opaque {};

    pub extern "c" fn qs_vec_preset_random(n: usize, min_val: c_int, max_val: c_int, seed: u64) ?*QsVec;
    pub extern "c" fn qs_vec_clone(src: ?*const QsVec) ?*QsVec;
    pub extern "c" fn qs_vec_destroy(vec: ?*QsVec) void;
    pub extern "c" fn qs_vec_verify(sorted_arr: [*]const c_int, n: usize, order: QsOrder, expected_hash: u64) bool;

    pub extern "c" fn qs_config_default() QsConfig;

    pub extern "c" fn qs_metrics_create(enable_pmu: bool, llc_bytes: usize) ?*QsMetricsCtx;
    pub extern "c" fn qs_metrics_destroy(ctx: ?*QsMetricsCtx) void;
    pub extern "c" fn qs_metrics_thrash_cache(ctx: ?*QsMetricsCtx) void;
    pub extern "c" fn qs_metrics_begin(ctx: ?*QsMetricsCtx) void;
    pub extern "c" fn qs_metrics_end(ctx: ?*QsMetricsCtx) QsPerfSnapshot;
    pub extern "c" fn qs_metrics_pmu_supported(ctx: ?*const QsMetricsCtx) bool;

    pub extern "c" fn qs_jit_options_default() QsJitOptions;
    pub extern "c" fn qs_jit_cache_create(build_dir: ?[*:0]const u8) ?*QsJitCache;
    pub extern "c" fn qs_jit_cache_destroy(cache: ?*QsJitCache) void;
    pub extern "c" fn qs_jit_acquire(cache: ?*QsJitCache, opts: ?*const QsJitOptions) ?*const QsJitModule;
};

extern "c" fn access(pathname: [*:0]const u8, mode: c_int) c_int;
extern "c" fn unlink(pathname: [*:0]const u8) c_int;
extern "c" fn rmdir(pathname: [*:0]const u8) c_int;
extern "c" fn fopen(filename: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(stream: ?*anyopaque) c_int;
extern "c" fn fseek(stream: ?*anyopaque, offset: c_long, whence: c_int) c_int;
extern "c" fn ftell(stream: ?*anyopaque) c_long;
extern "c" fn fread(ptr: [*]u8, size: usize, n: usize, stream: ?*anyopaque) usize;

fn readWholeFile(allocator: std.mem.Allocator, path: [*:0]const u8) ![]u8 {
    const f = fopen(path, "rb") orelse return error.FileNotFound;
    defer _ = fclose(f);
    _ = fseek(f, 0, 2);
    const sz: usize = @intCast(ftell(f));
    _ = fseek(f, 0, 0);
    const buf = try allocator.alloc(u8, sz);
    _ = fread(buf.ptr, 1, sz, f);
    return buf;
}

test "metrics: create, thrash_cache, begin, end, destroy with monotonic_ns > 0" {
    const ctx = c.qs_metrics_create(true, 1024 * 1024);
    try testing.expect(ctx != null);
    defer c.qs_metrics_destroy(ctx);

    _ = c.qs_metrics_pmu_supported(ctx);
    c.qs_metrics_thrash_cache(ctx);

    c.qs_metrics_begin(ctx);
    c.qs_metrics_thrash_cache(ctx);
    const snap = c.qs_metrics_end(ctx);

    try testing.expect(snap.monotonic_ns > 0);
}

test "jit: static fastpath and dynamic .so/.s compilation + execution" {
    const jit_dir = "/tmp/opencode/qs_jit_test";
    const cache = c.qs_jit_cache_create(jit_dir);
    try testing.expect(cache != null);
    defer c.qs_jit_cache_destroy(cache);

    const def_opts = c.qs_jit_options_default();
    const fast_mod = c.qs_jit_acquire(cache, &def_opts);
    try testing.expect(fast_mod != null);
    try testing.expect(fast_mod.?.is_static_fastpath);
    try testing.expect(fast_mod.?.run_clean != null);
    try testing.expect(fast_mod.?.run_counted != null);

    var custom_opts = c.qs_jit_options_default();
    custom_opts.cflags = "-O2";
    custom_opts.pragma_unroll_count = 4;
    custom_opts.emit_asm = true;

    const dyn_mod = c.qs_jit_acquire(cache, &custom_opts);
    try testing.expect(dyn_mod != null);
    try testing.expect(!dyn_mod.?.is_static_fastpath);
    try testing.expect(dyn_mod.?.dl_handle != null);
    try testing.expect(dyn_mod.?.run_clean != null);
    try testing.expect(dyn_mod.?.run_counted != null);

    const so_path_ptr: [*:0]const u8 = @ptrCast(&dyn_mod.?.so_path);
    const asm_path_ptr: [*:0]const u8 = @ptrCast(&dyn_mod.?.asm_path);
    defer {
        _ = unlink(so_path_ptr);
        _ = unlink(asm_path_ptr);
        _ = rmdir(jit_dir);
    }

    try testing.expectEqual(@as(c_int, 0), access(so_path_ptr, 0));
    try testing.expectEqual(@as(c_int, 0), access(asm_path_ptr, 0));

    const n: usize = 256;
    const base = c.qs_vec_preset_random(n, -1000, 1000, 31415).?;
    defer c.qs_vec_destroy(base);

    const v_clean = c.qs_vec_clone(base).?;
    defer c.qs_vec_destroy(v_clean);

    const v_counted = c.qs_vec_clone(base).?;
    defer c.qs_vec_destroy(v_counted);

    const cfg = c.qs_config_default();
    var st_clean: c.QsRunStats = std.mem.zeroes(c.QsRunStats);
    var st_counted: c.QsRunStats = std.mem.zeroes(c.QsRunStats);

    try testing.expect(dyn_mod.?.run_clean.?(v_clean.data, v_clean.len, &cfg, &st_clean));
    try testing.expect(dyn_mod.?.run_counted.?(v_counted.data, v_counted.len, &cfg, &st_counted));

    try testing.expect(c.qs_vec_verify(v_clean.data, v_clean.len, cfg.order, base.multiset_hash));
    try testing.expect(c.qs_vec_verify(v_counted.data, v_counted.len, cfg.order, base.multiset_hash));
    try testing.expectEqual(@as(u64, 0), st_clean.comparisons);
    try testing.expect(st_counted.comparisons > 0);
    try testing.expectEqualSlices(c_int, v_clean.data[0..v_clean.len], v_counted.data[0..v_counted.len]);
}

test "jit: unroll(4) pragma produces different assembly from default" {
    const jit_dir = "build/jit_test_unroll";
    const cache = c.qs_jit_cache_create(jit_dir);
    try testing.expect(cache != null);
    defer c.qs_jit_cache_destroy(cache);

    // Module 1: default with emit_asm
    var opts_default = c.qs_jit_options_default();
    opts_default.cflags = "-O3 -march=native";
    opts_default.emit_asm = true;
    opts_default.force_recompile = true;
    const mod_default = c.qs_jit_acquire(cache, &opts_default);
    try testing.expect(mod_default != null);

    // Module 2: unroll(4) with emit_asm
    var opts_unroll = c.qs_jit_options_default();
    opts_unroll.cflags = "-O3 -march=native";
    opts_unroll.pragma_unroll_count = 4;
    opts_unroll.emit_asm = true;
    opts_unroll.force_recompile = true;
    const mod_unroll = c.qs_jit_acquire(cache, &opts_unroll);
    try testing.expect(mod_unroll != null);

    const so_default_ptr: [*:0]const u8 = @ptrCast(&mod_default.?.so_path);
    const asm_default_ptr: [*:0]const u8 = @ptrCast(&mod_default.?.asm_path);
    const so_unroll_ptr: [*:0]const u8 = @ptrCast(&mod_unroll.?.so_path);
    const asm_unroll_ptr: [*:0]const u8 = @ptrCast(&mod_unroll.?.asm_path);
    defer {
        _ = unlink(so_default_ptr);
        _ = unlink(asm_default_ptr);
        _ = unlink(so_unroll_ptr);
        _ = unlink(asm_unroll_ptr);
        _ = rmdir(jit_dir);
    }

    const content_default = try readWholeFile(testing.allocator, asm_default_ptr);
    defer testing.allocator.free(content_default);

    const content_unroll = try readWholeFile(testing.allocator, asm_unroll_ptr);
    defer testing.allocator.free(content_unroll);

    try testing.expect(!std.mem.eql(u8, content_default, content_unroll));
}
