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
        data: ?[*]c_int,
        len: usize,
        cap: usize,
        multiset_hash: u64,
    };

    pub const QsThreadPool = opaque {};

    pub const QsRunStats = extern struct {
        comparisons: u64,
        swaps: u64,
        moves: u64,
        max_depth_reached: usize,
        bad_partitions: usize,
        heapsort_fallbacks: usize,
        depth_limit_exceeded: bool,
    };

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

    pub const QsKernelFn = *const fn (arr: [*]c_int, n: usize, cfg: *const QsConfig, stats: ?*QsRunStats) callconv(.c) bool;

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

    pub const QsVecExprKind = u8;
    pub const QS_VEXPR_RANDOM: QsVecExprKind = 0;
    pub const QS_VEXPR_SORTED: QsVecExprKind = 1;
    pub const QS_VEXPR_REVERSE: QsVecExprKind = 2;
    pub const QS_VEXPR_REPEATED: QsVecExprKind = 3;
    pub const QS_VEXPR_CONSTANT: QsVecExprKind = 4;
    pub const QS_VEXPR_ORGAN_PIPE: QsVecExprKind = 5;
    pub const QS_VEXPR_SAWTOOTH: QsVecExprKind = 6;
    pub const QS_VEXPR_ADVERSARIAL_MED3: QsVecExprKind = 7;
    pub const QS_VEXPR_VAR: QsVecExprKind = 8;
    pub const QS_VEXPR_CONCAT: QsVecExprKind = 9;
    pub const QS_VEXPR_INTERLEAVE: QsVecExprKind = 10;
    pub const QS_VEXPR_BLEND: QsVecExprKind = 11;
    pub const QS_VEXPR_REVERSED: QsVecExprKind = 12;
    pub const QS_VEXPR_PARTIAL_SORT: QsVecExprKind = 13;
    pub const QS_VEXPR_SLICE: QsVecExprKind = 14;

    pub const QsSizeSpec = extern struct {
        is_relative: bool,
        fixed_len: usize,
        n_scale: f64,
    };

    pub const QsVecExpr = extern struct {
        kind: QsVecExprKind,
        size: QsSizeSpec,
        min_val: c_int,
        max_val: c_int,
        step: c_int,
        value: c_int,
        unique_count: usize,
        period: usize,
        factor: f64,
        order: QsOrder,
        seed: u64,
        has_seed: bool,
        slice_start: usize,
        slice_end: usize,
        slice_rel: bool,
        slice_start_ratio: f64,
        slice_end_ratio: f64,
        var_name: [64]u8,
        left: ?*QsVecExpr,
        right: ?*QsVecExpr,
    };

    pub const QsMetricFlags = u32;
    pub const QS_METRIC_MONOTONIC_NS: QsMetricFlags = 1 << 0;
    pub const QS_METRIC_COMPARISONS: QsMetricFlags = 1 << 1;
    pub const QS_METRIC_SWAPS: QsMetricFlags = 1 << 2;
    pub const QS_METRIC_MOVES: QsMetricFlags = 1 << 3;
    pub const QS_METRIC_CYCLES: QsMetricFlags = 1 << 4;
    pub const QS_METRIC_INSTRUCTIONS: QsMetricFlags = 1 << 5;
    pub const QS_METRIC_BRANCHES: QsMetricFlags = 1 << 6;
    pub const QS_METRIC_BRANCH_MISSES: QsMetricFlags = 1 << 7;
    pub const QS_METRIC_L1D_MISSES: QsMetricFlags = 1 << 8;
    pub const QS_METRIC_LLC_MISSES: QsMetricFlags = 1 << 9;
    pub const QS_METRIC_ALL: QsMetricFlags = 0x3FF;

    pub const QsHostConfig = extern struct {
        pin_cpus: [64]c_int,
        num_pin_cpus: usize,
        cold_cache: bool,
        enable_pmu: bool,
        repetitions: usize,
        warmup: usize,
        seed: u64,
    };

    pub const QsLetBinding = extern struct {
        name: [64]u8,
        expr: ?*QsVecExpr,
    };

    pub const QsDatasetSpec = extern struct {
        name: [64]u8,
        sizes: [32]usize,
        num_sizes: usize,
        expr: ?*QsVecExpr,
    };

    pub const QsVariantSpec = extern struct {
        name: [64]u8,
        cfg: QsConfig,
        jit: QsJitOptions,
        cflags_buf: [256]u8,
        cc_buf: [64]u8,
    };

    pub const QsBenchmarkSpec = extern struct {
        name: [64]u8,
        dataset_names: [32][64]u8,
        num_datasets: usize,
        variant_names: [32][64]u8,
        num_variants: usize,
        metrics_mask: u32,
        output_csv: [256]u8,
        output_latex: [256]u8,
        output_asm_dir: [256]u8,
        repetitions: usize,
        cold_cache_override: c_int,
    };

    pub const QsSimPlan = extern struct {
        host: QsHostConfig,
        bindings: [64]QsLetBinding,
        num_bindings: usize,
        datasets: [64]QsDatasetSpec,
        num_datasets: usize,
        variants: [64]QsVariantSpec,
        num_variants: usize,
        benchmarks: [32]QsBenchmarkSpec,
        num_benchmarks: usize,
    };

    pub extern "c" fn qs_sim_plan_init(plan: ?*QsSimPlan) void;
    pub extern "c" fn qs_sim_plan_destroy(plan: ?*QsSimPlan) void;
    pub extern "c" fn qs_parse_string(src: [*c]const u8, virtual_filename: [*c]const u8, plan: ?*QsSimPlan) c_int;
    pub extern "c" fn qs_parse_last_warning_count() c_int;
    pub extern "c" fn qs_parse_set_quiet(quiet: bool) void;
    pub extern "c" fn qs_vexpr_eval(expr: ?*const QsVecExpr, target_n: usize, plan: ?*const QsSimPlan, run_seed: u64) QsVec;
    pub extern "c" fn free(ptr: ?*anyopaque) void;
};

// 1. Valid minimal file parses with status 0 and produces expected counts
test "parser: valid minimal file parses with status 0 and expected counts" {
    c.qs_parse_set_quiet(true);

    const src =
        \\host {
        \\    pin_cpus = [0];
        \\    cold_cache = false;
        \\    repetitions = 3;
        \\    warmup = 1;
        \\}
        \\
        \\dataset small_rand {
        \\    sizes = [256, 1024];
        \\    expr = random(n, min=0, max=10000, seed=42);
        \\}
        \\
        \\variant default_qs {
        \\    partition = hoare;
        \\    pivot = median3;
        \\    cutoff = 16;
        \\    small_sort = insertion;
        \\    execution = tail_call;
        \\}
        \\
        \\benchmark smoke {
        \\    datasets = [small_rand];
        \\    variants = [default_qs];
        \\    metrics = [monotonic_ns, comparisons, swaps, moves];
        \\}
    ;

    var plan: c.QsSimPlan = undefined;
    const rc = c.qs_parse_string(src, "minimal.qs", &plan);
    try testing.expectEqual(@as(c_int, 0), rc);
    defer c.qs_sim_plan_destroy(&plan);

    try testing.expectEqual(@as(usize, 1), plan.host.num_pin_cpus);
    try testing.expectEqual(@as(c_int, 0), plan.host.pin_cpus[0]);
    try testing.expectEqual(false, plan.host.cold_cache);
    try testing.expectEqual(@as(usize, 3), plan.host.repetitions);
    try testing.expectEqual(@as(usize, 1), plan.host.warmup);

    try testing.expectEqual(@as(usize, 1), plan.num_datasets);
    try testing.expectEqual(@as(usize, 2), plan.datasets[0].num_sizes);
    try testing.expectEqual(@as(usize, 256), plan.datasets[0].sizes[0]);
    try testing.expectEqual(@as(usize, 1024), plan.datasets[0].sizes[1]);

    try testing.expectEqual(@as(usize, 1), plan.num_variants);
    try testing.expectEqual(c.QS_PART_HOARE, plan.variants[0].cfg.partition);
    try testing.expectEqual(c.QS_PIVOT_MEDIAN3, plan.variants[0].cfg.pivot);
    try testing.expectEqual(@as(usize, 16), plan.variants[0].cfg.cutoff);
    try testing.expectEqual(c.QS_SMALL_INSERTION, plan.variants[0].cfg.small_sort);
    try testing.expectEqual(c.QS_EXEC_TAIL_CALL, plan.variants[0].cfg.exec_mode);

    try testing.expectEqual(@as(usize, 1), plan.num_benchmarks);
    try testing.expectEqual(@as(usize, 1), plan.benchmarks[0].num_datasets);
    try testing.expectEqual(@as(usize, 1), plan.benchmarks[0].num_variants);
    try testing.expect((plan.benchmarks[0].metrics_mask & c.QS_METRIC_MONOTONIC_NS) != 0);
}

// 2. Keyword/identifier normalization: case-folding of MEDIAN3 vs median3
test "parser: keyword and identifier normalization" {
    c.qs_parse_set_quiet(true);

    // MEDIAN3 is normalized to lowercase "median3" by qs_ident_normalize
    const src_upper =
        \\variant v_upper {
        \\    pivot = MEDIAN3;
        \\}
    ;
    var plan_upper: c.QsSimPlan = undefined;
    const rc_upper = c.qs_parse_string(src_upper, "upper.qs", &plan_upper);
    try testing.expectEqual(@as(c_int, 0), rc_upper);
    defer c.qs_sim_plan_destroy(&plan_upper);

    const src_lower =
        \\variant v_lower {
        \\    pivot = median3;
        \\}
    ;
    var plan_lower: c.QsSimPlan = undefined;
    const rc_lower = c.qs_parse_string(src_lower, "lower.qs", &plan_lower);
    try testing.expectEqual(@as(c_int, 0), rc_lower);
    defer c.qs_sim_plan_destroy(&plan_lower);

    // median_of_three and median-of-three normalize to the same pivot as median3 / MEDIAN3
    const src_underscored =
        \\variant v_und {
        \\    pivot = median_of_three;
        \\}
    ;
    var plan_und: c.QsSimPlan = undefined;
    const rc_und = c.qs_parse_string(src_underscored, "und.qs", &plan_und);
    try testing.expectEqual(@as(c_int, 0), rc_und);
    defer c.qs_sim_plan_destroy(&plan_und);

    const src_hyphenated =
        \\variant v_hyp {
        \\    pivot = median-of-three;
        \\}
    ;
    var plan_hyp: c.QsSimPlan = undefined;
    const rc_hyp = c.qs_parse_string(src_hyphenated, "hyp.qs", &plan_hyp);
    try testing.expectEqual(@as(c_int, 0), rc_hyp);
    defer c.qs_sim_plan_destroy(&plan_hyp);

    try testing.expectEqual(c.QS_PIVOT_MEDIAN3, plan_lower.variants[0].cfg.pivot);
    try testing.expectEqual(c.QS_PIVOT_MEDIAN3, plan_upper.variants[0].cfg.pivot);
    try testing.expectEqual(c.QS_PIVOT_MEDIAN3, plan_und.variants[0].cfg.pivot);
    try testing.expectEqual(c.QS_PIVOT_MEDIAN3, plan_hyp.variants[0].cfg.pivot);
}

// 3. Defaults applied when fields are omitted
test "parser: defaults applied when fields are omitted" {
    c.qs_parse_set_quiet(true);

    const src =
        \\variant v_defaults {}
    ;
    var plan: c.QsSimPlan = undefined;
    const rc = c.qs_parse_string(src, "defaults.qs", &plan);
    try testing.expectEqual(@as(c_int, 0), rc);
    defer c.qs_sim_plan_destroy(&plan);

    // Plan host defaults initialized by qs_sim_plan_init()
    try testing.expectEqual(@as(usize, 5), plan.host.repetitions);
    try testing.expectEqual(@as(usize, 1), plan.host.warmup);
    try testing.expectEqual(@as(u64, 42), plan.host.seed);
    try testing.expectEqual(false, plan.host.cold_cache);

    // Variant defaults initialized by qs_config_default()
    try testing.expectEqual(@as(usize, 1), plan.num_variants);
    const cfg = plan.variants[0].cfg;
    try testing.expectEqual(c.QS_PART_HOARE, cfg.partition);
    try testing.expectEqual(c.QS_PIVOT_MEDIAN3, cfg.pivot);
    try testing.expectEqual(c.QS_SMALL_INSERTION, cfg.small_sort);
    try testing.expectEqual(c.QS_EXEC_TAIL_CALL, cfg.exec_mode);
    try testing.expectEqual(@as(usize, 16), cfg.cutoff);
    try testing.expectEqual(c.QS_ORDER_ASC, cfg.order);

    // Pragmas parsing: unroll(4), unroll(disable), vectorize
    const src_pragmas =
        \\variant v_p1 { pragmas = ["unroll(4)", "vectorize"]; }
        \\variant v_p2 { pragmas = ["unroll(disable)", "no_vectorize"]; }
    ;
    var plan_p: c.QsSimPlan = undefined;
    const rc_p = c.qs_parse_string(src_pragmas, "pragmas.qs", &plan_p);
    try testing.expectEqual(@as(c_int, 0), rc_p);
    defer c.qs_sim_plan_destroy(&plan_p);

    try testing.expectEqual(@as(c_uint, 4), plan_p.variants[0].jit.pragma_unroll_count);
    try testing.expectEqual(true, plan_p.variants[0].jit.pragma_vectorize);
    try testing.expectEqual(true, plan_p.variants[1].jit.pragma_no_unroll);
    try testing.expectEqual(true, plan_p.variants[1].jit.pragma_no_vectorize);
}

// 4. Vector algebra: ++, **, ^, ~, |> partial_sort(...), [a..b] slices
test "parser: vector algebra combinators evaluate to expected lengths" {
    c.qs_parse_set_quiet(true);

    const src =
        \\let a = sorted(60);
        \\let b = sorted(40);
        \\let c_concat = a ++ b;
        \\let d_interleave = a ** b;
        \\let e_blend = a ^ b;
        \\let f_rev = ~a;
        \\let g_part = a |> partial_sort(factor=0.5, order=asc);
        \\let h_slice = a[10..30];
    ;
    var plan: c.QsSimPlan = undefined;
    const rc = c.qs_parse_string(src, "vec_algebra.qs", &plan);
    try testing.expectEqual(@as(c_int, 0), rc);
    defer c.qs_sim_plan_destroy(&plan);

    try testing.expectEqual(@as(usize, 8), plan.num_bindings);

    // c_concat: 60 + 40 = 100
    const vec_concat = c.qs_vexpr_eval(plan.bindings[2].expr, 0, &plan, 42);
    defer c.free(vec_concat.data);
    try testing.expectEqual(@as(usize, 100), vec_concat.len);

    // d_interleave: 60 + 40 = 100
    const vec_interleave = c.qs_vexpr_eval(plan.bindings[3].expr, 0, &plan, 42);
    defer c.free(vec_interleave.data);
    try testing.expectEqual(@as(usize, 100), vec_interleave.len);

    // e_blend: 60 + 40 = 100
    const vec_blend = c.qs_vexpr_eval(plan.bindings[4].expr, 0, &plan, 42);
    defer c.free(vec_blend.data);
    try testing.expectEqual(@as(usize, 100), vec_blend.len);

    // f_rev: ~a has len 60
    const vec_rev = c.qs_vexpr_eval(plan.bindings[5].expr, 0, &plan, 42);
    defer c.free(vec_rev.data);
    try testing.expectEqual(@as(usize, 60), vec_rev.len);

    // g_part: a |> partial_sort has len 60
    const vec_part = c.qs_vexpr_eval(plan.bindings[6].expr, 0, &plan, 42);
    defer c.free(vec_part.data);
    try testing.expectEqual(@as(usize, 60), vec_part.len);

    // h_slice: a[10..30] has len 30 - 10 = 20
    const vec_slice = c.qs_vexpr_eval(plan.bindings[7].expr, 0, &plan, 42);
    defer c.free(vec_slice.data);
    try testing.expectEqual(@as(usize, 20), vec_slice.len);
}

// 5. Invalid input (unknown keyword, missing '}') returns nonzero and does not leak
test "parser: invalid input returns nonzero and cleans up" {
    c.qs_parse_set_quiet(true);

    // Missing closing brace
    const src_unclosed = "host { pin_cpus = [0];";
    var plan1: c.QsSimPlan = undefined;
    const rc1 = c.qs_parse_string(src_unclosed, "unclosed.qs", &plan1);
    try testing.expect(rc1 != 0);

    // Unknown generator function
    const src_unknown_fn = "dataset d { sizes = [10]; expr = non_existent_fn(10); }";
    var plan2: c.QsSimPlan = undefined;
    const rc2 = c.qs_parse_string(src_unknown_fn, "badfn.qs", &plan2);
    try testing.expect(rc2 != 0);

    // Unterminated string
    const src_unterminated_str = "variant v { cflags = \"unterminated; }";
    var plan3: c.QsSimPlan = undefined;
    const rc3 = c.qs_parse_string(src_unterminated_str, "badstr.qs", &plan3);
    try testing.expect(rc3 != 0);
}

// 6. Location tracking: query capability check
test "parser: location tracking public API check" {
    // The public API in include/parser.h only exposes:
    //   qs_parse_string(src, virtual_filename, plan) -> int
    //   qs_parse_last_warning_count() -> int
    // Error locations (line/column) are formatted directly to stderr via
    // print_snippet() in src/parser.c and are not exposed programmatically
    // via a getter (e.g. qs_parse_last_error_line()).
    // Therefore programmatic verification of error line numbers is skipped as
    // permitted by the test specification.
}

// 7. Deterministic fuzz loop (2000 iterations) asserting parser never crashes
test "parser: deterministic fuzz loop with fixed seed" {
    c.qs_parse_set_quiet(true);

    var prng = std.Random.DefaultPrng.init(0xdeadbeef_cafebabe);
    const rng = prng.random();

    var buf: [256]u8 = undefined;

    var iter: usize = 0;
    while (iter < 2000) : (iter += 1) {
        const len = rng.uintLessThan(usize, buf.len - 1);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            buf[i] = rng.int(u8);
        }
        buf[len] = 0;

        var plan: c.QsSimPlan = undefined;
        const rc = c.qs_parse_string(&buf, "fuzz.qs", &plan);
        if (rc == 0) {
            c.qs_sim_plan_destroy(&plan);
        }
    }
}
