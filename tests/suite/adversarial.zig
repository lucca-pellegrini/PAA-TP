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

    pub extern "c" fn qs_vec_create(len: usize) ?*QsVec;
    pub extern "c" fn qs_vec_destroy(vec: ?*QsVec) void;
    pub extern "c" fn qs_vec_clone(src: ?*const QsVec) ?*QsVec;
    pub extern "c" fn qs_vec_rehash(vec: ?*QsVec) void;
    pub extern "c" fn qs_vec_multiset_hash(arr: [*]const c_int, n: usize) u64;
    pub extern "c" fn qs_vec_verify(sorted_arr: [*]const c_int, n: usize, order: QsOrder, expected_hash: u64) bool;

    pub extern "c" fn qs_vec_preset_sorted(n: usize, order: QsOrder, start: c_int, step: c_int) ?*QsVec;
    pub extern "c" fn qs_vec_preset_constant(n: usize, value: c_int) ?*QsVec;
    pub extern "c" fn qs_vec_preset_organ_pipe(n: usize) ?*QsVec;
    pub extern "c" fn qs_vec_preset_sawtooth(n: usize, period: usize, order: QsOrder) ?*QsVec;
    pub extern "c" fn qs_vec_preset_adversarial_med3(n: usize) ?*QsVec;

    pub extern "c" fn qs_config_default() QsConfig;
    pub extern "c" fn qs_run_clean(arr: [*]c_int, n: usize, cfg: *const QsConfig, stats: ?*QsRunStats) bool;
    pub extern "c" fn qs_run_counted(arr: [*]c_int, n: usize, cfg: *const QsConfig, stats: ?*QsRunStats) bool;
};

test "adversarial: organ_pipe, sawtooth, constant, and adversarial_med3 across THREE_WAY, PDQ, and HOARE+MEDIAN3" {
    const n: usize = 300;
    const v_organ = c.qs_vec_preset_organ_pipe(n).?;
    defer c.qs_vec_destroy(v_organ);

    const v_saw = c.qs_vec_preset_sawtooth(n, 16, c.QS_ORDER_ASC).?;
    defer c.qs_vec_destroy(v_saw);

    const v_const = c.qs_vec_preset_constant(n, 42).?;
    defer c.qs_vec_destroy(v_const);

    const v_adv = c.qs_vec_preset_adversarial_med3(n).?;
    defer c.qs_vec_destroy(v_adv);

    const workloads = [_]*const c.QsVec{ v_organ, v_saw, v_const, v_adv };
    const partitions = [_]c.QsPartition{
        c.QS_PART_THREE_WAY,
        c.QS_PART_PDQ,
        c.QS_PART_HOARE,
    };

    for (workloads) |w| {
        for (partitions) |part| {
            var cfg = c.qs_config_default();
            cfg.partition = part;
            cfg.pivot = c.QS_PIVOT_MEDIAN3;
            cfg.small_sort = c.QS_SMALL_INSERTION;
            cfg.cutoff = 16;

            const vc = c.qs_vec_clone(w).?;
            defer c.qs_vec_destroy(vc);
            var st_clean: c.QsRunStats = std.mem.zeroes(c.QsRunStats);
            try testing.expect(c.qs_run_clean(vc.data, vc.len, &cfg, &st_clean));
            try testing.expect(c.qs_vec_verify(vc.data, vc.len, cfg.order, w.multiset_hash));

            const vk = c.qs_vec_clone(w).?;
            defer c.qs_vec_destroy(vk);
            var st_counted: c.QsRunStats = std.mem.zeroes(c.QsRunStats);
            try testing.expect(c.qs_run_counted(vk.data, vk.len, &cfg, &st_counted));
            try testing.expect(c.qs_vec_verify(vk.data, vk.len, cfg.order, w.multiset_hash));
            try testing.expect(st_counted.comparisons > 0);
        }
    }
}

test "adversarial: recursion depth guard triggers safely without crashing" {
    const n: usize = 500;
    const v_sorted = c.qs_vec_preset_sorted(n, c.QS_ORDER_ASC, 1, 1).?;
    defer c.qs_vec_destroy(v_sorted);

    var cfg = c.qs_config_default();
    cfg.partition = c.QS_PART_LOMUTO;
    cfg.pivot = c.QS_PIVOT_FIRST;
    cfg.exec_mode = c.QS_EXEC_RECURSIVE;
    cfg.small_sort = c.QS_SMALL_NONE;
    cfg.cutoff = 0;
    cfg.max_depth = 16;

    const v_clean = c.qs_vec_clone(v_sorted).?;
    defer c.qs_vec_destroy(v_clean);
    var stats_clean: c.QsRunStats = std.mem.zeroes(c.QsRunStats);
    try testing.expect(c.qs_run_clean(v_clean.data, v_clean.len, &cfg, &stats_clean));
    try testing.expect(stats_clean.depth_limit_exceeded);
    try testing.expect(stats_clean.heapsort_fallbacks > 0);
    try testing.expect(c.qs_vec_verify(v_clean.data, v_clean.len, cfg.order, v_sorted.multiset_hash));

    const v_counted = c.qs_vec_clone(v_sorted).?;
    defer c.qs_vec_destroy(v_counted);
    var stats_counted: c.QsRunStats = std.mem.zeroes(c.QsRunStats);
    try testing.expect(c.qs_run_counted(v_counted.data, v_counted.len, &cfg, &stats_counted));
    try testing.expect(stats_counted.depth_limit_exceeded);
    try testing.expect(stats_counted.heapsort_fallbacks > 0);
    try testing.expect(stats_counted.comparisons > 0);
    try testing.expect(c.qs_vec_verify(v_counted.data, v_counted.len, cfg.order, v_sorted.multiset_hash));
}

test "adversarial: edge cases n=0, n=1, n=2 (asc/desc pairs), and all-equal negative numbers" {
    var cfg = c.qs_config_default();
    var stats: c.QsRunStats = std.mem.zeroes(c.QsRunStats);

    // n = 0
    var dummy: [1]c_int = .{0};
    try testing.expect(c.qs_run_clean(&dummy, 0, &cfg, &stats));
    try testing.expect(c.qs_run_counted(&dummy, 0, &cfg, &stats));
    try testing.expectEqual(@as(u64, 0), stats.comparisons);

    // n = 1
    var single: [1]c_int = .{-999};
    const hash1 = c.qs_vec_multiset_hash(&single, 1);
    try testing.expect(c.qs_run_clean(&single, 1, &cfg, &stats));
    try testing.expect(c.qs_vec_verify(&single, 1, cfg.order, hash1));
    try testing.expect(c.qs_run_counted(&single, 1, &cfg, &stats));
    try testing.expect(c.qs_vec_verify(&single, 1, cfg.order, hash1));

    // n = 2 ascending pair
    var pair_asc: [2]c_int = .{ -10, 20 };
    const hash_pair_asc = c.qs_vec_multiset_hash(&pair_asc, 2);
    try testing.expect(c.qs_run_clean(&pair_asc, 2, &cfg, &stats));
    try testing.expect(c.qs_vec_verify(&pair_asc, 2, cfg.order, hash_pair_asc));

    var pair_asc_cnt: [2]c_int = .{ -10, 20 };
    try testing.expect(c.qs_run_counted(&pair_asc_cnt, 2, &cfg, &stats));
    try testing.expect(c.qs_vec_verify(&pair_asc_cnt, 2, cfg.order, hash_pair_asc));
    try testing.expect(stats.comparisons > 0);

    // n = 2 descending pair
    var pair_desc: [2]c_int = .{ 20, -10 };
    const hash_pair_desc = c.qs_vec_multiset_hash(&pair_desc, 2);
    try testing.expect(c.qs_run_clean(&pair_desc, 2, &cfg, &stats));
    try testing.expect(c.qs_vec_verify(&pair_desc, 2, cfg.order, hash_pair_desc));
    try testing.expectEqual(@as(c_int, -10), pair_desc[0]);
    try testing.expectEqual(@as(c_int, 20), pair_desc[1]);

    var pair_desc_cnt: [2]c_int = .{ 20, -10 };
    try testing.expect(c.qs_run_counted(&pair_desc_cnt, 2, &cfg, &stats));
    try testing.expect(c.qs_vec_verify(&pair_desc_cnt, 2, cfg.order, hash_pair_desc));
    try testing.expect(stats.comparisons > 0);

    // All-equal negative numbers across all partitions
    const neg_vec = c.qs_vec_preset_constant(128, -4242).?;
    defer c.qs_vec_destroy(neg_vec);

    const parts = [_]c.QsPartition{
        c.QS_PART_HOARE,
        c.QS_PART_LOMUTO,
        c.QS_PART_THREE_WAY,
        c.QS_PART_PDQ,
    };
    for (parts) |part| {
        cfg.partition = part;
        const v_copy = c.qs_vec_clone(neg_vec).?;
        defer c.qs_vec_destroy(v_copy);

        try testing.expect(c.qs_run_counted(v_copy.data, v_copy.len, &cfg, &stats));
        try testing.expect(c.qs_vec_verify(v_copy.data, v_copy.len, cfg.order, neg_vec.multiset_hash));
        try testing.expectEqual(@as(c_int, -4242), v_copy.data[0]);
        try testing.expectEqual(@as(c_int, -4242), v_copy.data[v_copy.len - 1]);
    }
}
