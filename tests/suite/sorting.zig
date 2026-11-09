const std = @import("std");
const testing = std.testing;

const c = struct {
    pub const QsOrder = c_uint;
    pub const QS_ORDER_ASC: QsOrder = 0;
    pub const QS_ORDER_DESC: QsOrder = 1;

    pub const QsPartition = c_uint;
    pub const QS_PART_HOARE: QsPartition = 0;
    pub const QS_PART_LOMUTO: QsPartition = 1;
    pub const QS_PART_THREE_WAY: QsPartition = 2;
    pub const QS_PART_PDQ: QsPartition = 3;

    pub const QsPivot = c_uint;
    pub const QS_PIVOT_FIRST: QsPivot = 0;
    pub const QS_PIVOT_LAST: QsPivot = 1;
    pub const QS_PIVOT_MIDDLE: QsPivot = 2;
    pub const QS_PIVOT_RANDOM: QsPivot = 3;
    pub const QS_PIVOT_MEDIAN3: QsPivot = 4;
    pub const QS_PIVOT_NINTHER: QsPivot = 5;

    pub const QsSmallSort = c_uint;
    pub const QS_SMALL_NONE: QsSmallSort = 0;
    pub const QS_SMALL_INSERTION: QsSmallSort = 1;
    pub const QS_SMALL_BINARY_INSERTION: QsSmallSort = 2;
    pub const QS_SMALL_SHELL: QsSmallSort = 3;
    pub const QS_SMALL_HEAPSORT: QsSmallSort = 4;

    pub const QsExecMode = c_uint;
    pub const QS_EXEC_RECURSIVE: QsExecMode = 0;
    pub const QS_EXEC_TAIL_CALL: QsExecMode = 1;
    pub const QS_EXEC_ITERATIVE: QsExecMode = 2;
    pub const QS_EXEC_PARALLEL: QsExecMode = 3;

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

    pub extern "c" fn qs_vec_destroy(vec: ?*QsVec) void;
    pub extern "c" fn qs_vec_clone(src: ?*const QsVec) ?*QsVec;
    pub extern "c" fn qs_vec_verify(sorted_arr: [*]const c_int, n: usize, order: QsOrder, expected_hash: u64) bool;

    pub extern "c" fn qs_vec_preset_random(n: usize, min_val: c_int, max_val: c_int, seed: u64) ?*QsVec;
    pub extern "c" fn qs_vec_preset_sorted(n: usize, order: QsOrder, start: c_int, step: c_int) ?*QsVec;
    pub extern "c" fn qs_vec_preset_reverse(n: usize) ?*QsVec;
    pub extern "c" fn qs_vec_preset_repeated(n: usize, unique_values: usize, seed: u64) ?*QsVec;

    pub extern "c" fn qs_threadpool_create(num_threads: usize, pin_cpus: ?[*]const c_int, num_pin_cpus: usize) ?*QsThreadPool;
    pub extern "c" fn qs_threadpool_destroy(pool: ?*QsThreadPool) void;

    pub extern "c" fn qs_config_default() QsConfig;
    pub extern "c" fn qs_run_clean(arr: [*]c_int, n: usize, cfg: *const QsConfig, stats: ?*QsRunStats) bool;
    pub extern "c" fn qs_run_counted(arr: [*]c_int, n: usize, cfg: *const QsConfig, stats: ?*QsRunStats) bool;

    pub extern "c" fn qs_partition_name(part: QsPartition) [*:0]const u8;
    pub extern "c" fn qs_pivot_name(pivot: QsPivot) [*:0]const u8;
    pub extern "c" fn qs_small_sort_name(small: QsSmallSort) [*:0]const u8;
    pub extern "c" fn qs_exec_mode_name(mode: QsExecMode) [*:0]const u8;
};

fn verifyBothPasses(src: *const c.QsVec, cfg: *const c.QsConfig) !void {
    const v_clean = c.qs_vec_clone(src).?;
    defer c.qs_vec_destroy(v_clean);

    const v_counted = c.qs_vec_clone(src).?;
    defer c.qs_vec_destroy(v_counted);

    var stats_clean: c.QsRunStats = std.mem.zeroes(c.QsRunStats);
    var stats_counted: c.QsRunStats = std.mem.zeroes(c.QsRunStats);

    try testing.expect(c.qs_run_clean(v_clean.data, v_clean.len, cfg, &stats_clean));
    try testing.expect(c.qs_run_counted(v_counted.data, v_counted.len, cfg, &stats_counted));

    try testing.expect(c.qs_vec_verify(v_clean.data, v_clean.len, cfg.order, src.multiset_hash));
    try testing.expect(c.qs_vec_verify(v_counted.data, v_counted.len, cfg.order, src.multiset_hash));

    try testing.expectEqual(@as(u64, 0), stats_clean.comparisons);
    if (src.len >= 2) {
        try testing.expect(stats_counted.comparisons > 0);
    }

    try testing.expectEqualSlices(c_int, v_clean.data[0..v_clean.len], v_counted.data[0..v_counted.len]);
}

test "sorting: all partitions x pivots x small_sorts x exec_modes on random array" {
    const n: usize = 160;
    const base = c.qs_vec_preset_random(n, -1000, 1000, 2026).?;
    defer c.qs_vec_destroy(base);

    const pool = c.qs_threadpool_create(2, null, 0).?;
    defer c.qs_threadpool_destroy(pool);

    const partitions = [_]c.QsPartition{
        c.QS_PART_HOARE,
        c.QS_PART_LOMUTO,
        c.QS_PART_THREE_WAY,
        c.QS_PART_PDQ,
    };
    const pivots = [_]c.QsPivot{
        c.QS_PIVOT_FIRST,
        c.QS_PIVOT_LAST,
        c.QS_PIVOT_MIDDLE,
        c.QS_PIVOT_RANDOM,
        c.QS_PIVOT_MEDIAN3,
        c.QS_PIVOT_NINTHER,
    };
    const small_sorts = [_]c.QsSmallSort{
        c.QS_SMALL_NONE,
        c.QS_SMALL_INSERTION,
        c.QS_SMALL_BINARY_INSERTION,
        c.QS_SMALL_SHELL,
        c.QS_SMALL_HEAPSORT,
    };
    const exec_modes = [_]c.QsExecMode{
        c.QS_EXEC_RECURSIVE,
        c.QS_EXEC_TAIL_CALL,
        c.QS_EXEC_ITERATIVE,
        c.QS_EXEC_PARALLEL,
    };

    for (partitions) |part| {
        for (pivots) |piv| {
            for (small_sorts) |small| {
                for (exec_modes) |mode| {
                    var cfg = c.qs_config_default();
                    cfg.partition = part;
                    cfg.pivot = piv;
                    cfg.small_sort = small;
                    cfg.exec_mode = mode;
                    cfg.cutoff = if (small == c.QS_SMALL_NONE) 0 else 16;
                    cfg.parallel_threshold = 32;
                    cfg.seed = 98765;
                    cfg.pool = if (mode == c.QS_EXEC_PARALLEL) pool else null;

                    try verifyBothPasses(base, &cfg);
                }
            }
        }
    }
}

test "sorting: random, sorted, reverse, and repeated datasets in ASC and DESC order" {
    const n: usize = 256;
    const v_rand = c.qs_vec_preset_random(n, -500, 500, 77).?;
    defer c.qs_vec_destroy(v_rand);

    const v_sorted = c.qs_vec_preset_sorted(n, c.QS_ORDER_ASC, 1, 2).?;
    defer c.qs_vec_destroy(v_sorted);

    const v_rev = c.qs_vec_preset_reverse(n).?;
    defer c.qs_vec_destroy(v_rev);

    const v_rep = c.qs_vec_preset_repeated(n, 5, 88).?;
    defer c.qs_vec_destroy(v_rep);

    const pool = c.qs_threadpool_create(2, null, 0).?;
    defer c.qs_threadpool_destroy(pool);

    const datasets = [_]*const c.QsVec{ v_rand, v_sorted, v_rev, v_rep };
    const orders = [_]c.QsOrder{ c.QS_ORDER_ASC, c.QS_ORDER_DESC };
    const partitions = [_]c.QsPartition{
        c.QS_PART_HOARE,
        c.QS_PART_LOMUTO,
        c.QS_PART_THREE_WAY,
        c.QS_PART_PDQ,
    };
    const modes = [_]c.QsExecMode{
        c.QS_EXEC_RECURSIVE,
        c.QS_EXEC_TAIL_CALL,
        c.QS_EXEC_ITERATIVE,
        c.QS_EXEC_PARALLEL,
    };

    for (datasets) |ds| {
        for (orders) |ord| {
            for (partitions) |part| {
                for (modes) |mode| {
                    var cfg = c.qs_config_default();
                    cfg.partition = part;
                    cfg.pivot = c.QS_PIVOT_MEDIAN3;
                    cfg.small_sort = c.QS_SMALL_INSERTION;
                    cfg.exec_mode = mode;
                    cfg.order = ord;
                    cfg.cutoff = 16;
                    cfg.parallel_threshold = 48;
                    cfg.pool = if (mode == c.QS_EXEC_PARALLEL) pool else null;

                    try verifyBothPasses(ds, &cfg);
                }
            }
        }
    }
}

test "sorting: strategy name helpers" {
    try testing.expectEqualStrings("hoare", std.mem.span(c.qs_partition_name(c.QS_PART_HOARE)));
    try testing.expectEqualStrings("lomuto", std.mem.span(c.qs_partition_name(c.QS_PART_LOMUTO)));
    try testing.expectEqualStrings("three_way", std.mem.span(c.qs_partition_name(c.QS_PART_THREE_WAY)));
    try testing.expectEqualStrings("pdq", std.mem.span(c.qs_partition_name(c.QS_PART_PDQ)));

    try testing.expectEqualStrings("first", std.mem.span(c.qs_pivot_name(c.QS_PIVOT_FIRST)));
    try testing.expectEqualStrings("last", std.mem.span(c.qs_pivot_name(c.QS_PIVOT_LAST)));
    try testing.expectEqualStrings("middle", std.mem.span(c.qs_pivot_name(c.QS_PIVOT_MIDDLE)));
    try testing.expectEqualStrings("random", std.mem.span(c.qs_pivot_name(c.QS_PIVOT_RANDOM)));
    try testing.expectEqualStrings("median3", std.mem.span(c.qs_pivot_name(c.QS_PIVOT_MEDIAN3)));
    try testing.expectEqualStrings("ninther", std.mem.span(c.qs_pivot_name(c.QS_PIVOT_NINTHER)));

    try testing.expectEqualStrings("none", std.mem.span(c.qs_small_sort_name(c.QS_SMALL_NONE)));
    try testing.expectEqualStrings("insertion", std.mem.span(c.qs_small_sort_name(c.QS_SMALL_INSERTION)));
    try testing.expectEqualStrings("binary_insertion", std.mem.span(c.qs_small_sort_name(c.QS_SMALL_BINARY_INSERTION)));
    try testing.expectEqualStrings("shell", std.mem.span(c.qs_small_sort_name(c.QS_SMALL_SHELL)));
    try testing.expectEqualStrings("heapsort", std.mem.span(c.qs_small_sort_name(c.QS_SMALL_HEAPSORT)));

    try testing.expectEqualStrings("recursive", std.mem.span(c.qs_exec_mode_name(c.QS_EXEC_RECURSIVE)));
    try testing.expectEqualStrings("tail_call", std.mem.span(c.qs_exec_mode_name(c.QS_EXEC_TAIL_CALL)));
    try testing.expectEqualStrings("iterative", std.mem.span(c.qs_exec_mode_name(c.QS_EXEC_ITERATIVE)));
    try testing.expectEqualStrings("parallel", std.mem.span(c.qs_exec_mode_name(c.QS_EXEC_PARALLEL)));
}
