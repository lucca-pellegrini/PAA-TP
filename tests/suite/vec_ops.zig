const std = @import("std");
const testing = std.testing;

const c = struct {
    pub const QsCacheLevel = extern struct {
        level: u32,
        type: [16]u8,
        size_bytes: usize,
        line_size: u32,
        ways: u32,
    };

    pub const QsHostInfo = extern struct {
        cpu_model: [128]u8,
        kernel_release: [64]u8,
        compiler_version: [128]u8,
        logical_cpus: u32,
        physical_cores: u32,
        total_ram_bytes: usize,
        perf_event_paranoid: c_int,
        l1d_bytes: usize,
        l1i_bytes: usize,
        l2_bytes: usize,
        l3_bytes: usize,
        cache_line_bytes: u32,
        caches: [8]QsCacheLevel,
        num_caches: usize,
    };

    pub const QsUiTelemetry = extern struct {
        benchmark_name: ?[*:0]const u8,
        dataset_name: ?[*:0]const u8,
        variant_name: ?[*:0]const u8,
        current_step: usize,
        total_steps: usize,
        current_rep: usize,
        total_reps: usize,
        array_size: usize,
        active_threads: u32,
        pinned_cpu: c_int,
        last_time_ns: f64,
        comparisons: u64,
        swaps: u64,
        cycles: u64,
        instructions: u64,
        branch_misses: u64,
        l1d_misses: u64,
        llc_misses: u64,
    };

    pub const QsUi = opaque {};

    pub const QsPbar = extern struct {
        total: usize,
        current: usize,
        start_ns: u64,
        last_render_ns: u64,
        width: u32,
        enabled: bool,
    };

    pub const QsOrder = c_uint;
    pub const QS_ORDER_ASC: QsOrder = 0;
    pub const QS_ORDER_DESC: QsOrder = 1;

    pub const QsVec = extern struct {
        data: [*]c_int,
        len: usize,
        cap: usize,
        multiset_hash: u64,
    };

    pub const QsThreadPool = opaque {};
    pub const QsTaskFn = *const fn (?*anyopaque) callconv(.c) void;

    pub extern "c" fn qs_sysinfo_detect(out: *QsHostInfo) c_int;
    pub extern "c" fn qs_sysinfo_write_csv(info: *const QsHostInfo, path: [*:0]const u8) c_int;
    pub extern "c" fn qs_sysinfo_write_latex(info: *const QsHostInfo, path: [*:0]const u8) c_int;

    pub extern "c" fn qs_ui_create(total_steps: usize, prefer_tui: bool, so_path: ?[*:0]const u8) ?*QsUi;
    pub extern "c" fn qs_ui_update(ui: ?*QsUi, telemetry: *const QsUiTelemetry) void;
    pub extern "c" fn qs_ui_log(ui: ?*QsUi, fmt: [*:0]const u8, ...) void;
    pub extern "c" fn qs_ui_finish(ui: ?*QsUi, summary: [*:0]const u8) void;
    pub extern "c" fn qs_ui_destroy(ui: ?*QsUi) void;
    pub extern "c" fn qs_ui_is_tui(ui: ?*const QsUi) bool;

    pub extern "c" fn qs_pbar_init(pb: *QsPbar, total: usize, width: u32, enabled: bool) void;
    pub extern "c" fn qs_pbar_update(pb: *QsPbar, current: usize, status_label: [*:0]const u8, last_ns: f64) void;
    pub extern "c" fn qs_pbar_finish(pb: *QsPbar, summary_label: [*:0]const u8) void;

    pub extern "c" fn qs_vec_create(len: usize) ?*QsVec;
    pub extern "c" fn qs_vec_destroy(vec: ?*QsVec) void;
    pub extern "c" fn qs_vec_clone(src: ?*const QsVec) ?*QsVec;
    pub extern "c" fn qs_vec_copy_data(dst: [*]c_int, dst_len: usize, src: ?*const QsVec) bool;
    pub extern "c" fn qs_vec_multiset_hash(arr: [*]const c_int, n: usize) u64;
    pub extern "c" fn qs_vec_rehash(vec: ?*QsVec) void;
    pub extern "c" fn qs_vec_is_sorted(arr: [*]const c_int, n: usize, order: QsOrder) bool;
    pub extern "c" fn qs_vec_verify(sorted_arr: [*]const c_int, n: usize, order: QsOrder, expected_hash: u64) bool;

    pub extern "c" fn qs_vec_preset_random(n: usize, min_val: c_int, max_val: c_int, seed: u64) ?*QsVec;
    pub extern "c" fn qs_vec_preset_sorted(n: usize, order: QsOrder, start: c_int, step: c_int) ?*QsVec;
    pub extern "c" fn qs_vec_preset_reverse(n: usize) ?*QsVec;
    pub extern "c" fn qs_vec_preset_repeated(n: usize, unique_values: usize, seed: u64) ?*QsVec;
    pub extern "c" fn qs_vec_preset_constant(n: usize, value: c_int) ?*QsVec;
    pub extern "c" fn qs_vec_preset_organ_pipe(n: usize) ?*QsVec;
    pub extern "c" fn qs_vec_preset_sawtooth(n: usize, period: usize, order: QsOrder) ?*QsVec;
    pub extern "c" fn qs_vec_preset_adversarial_med3(n: usize) ?*QsVec;

    pub extern "c" fn qs_vec_partial_sort(vec: ?*QsVec, factor: f64, order: QsOrder, seed: u64) bool;
    pub extern "c" fn qs_vec_reverse_in_place(vec: ?*QsVec) void;
    pub extern "c" fn qs_vec_reversed(src: ?*const QsVec) ?*QsVec;
    pub extern "c" fn qs_vec_concat(a: ?*const QsVec, b: ?*const QsVec) ?*QsVec;
    pub extern "c" fn qs_vec_interleave(a: ?*const QsVec, b: ?*const QsVec) ?*QsVec;
    pub extern "c" fn qs_vec_blend(a: ?*const QsVec, b: ?*const QsVec, ratio_a: f64, seed: u64) ?*QsVec;
    pub extern "c" fn qs_vec_slice(src: ?*const QsVec, start: usize, end: usize) ?*QsVec;

    pub extern "c" fn qs_pin_current_thread(cpu_id: c_int) bool;
    pub extern "c" fn qs_threadpool_create(num_threads: usize, pin_cpus: ?[*]const c_int, num_pin_cpus: usize) ?*QsThreadPool;
    pub extern "c" fn qs_threadpool_destroy(pool: ?*QsThreadPool) void;
    pub extern "c" fn qs_threadpool_submit(pool: ?*QsThreadPool, func: QsTaskFn, arg: ?*anyopaque) bool;
    pub extern "c" fn qs_threadpool_wait_all(pool: ?*QsThreadPool) void;
    pub extern "c" fn qs_threadpool_num_threads(pool: ?*const QsThreadPool) usize;
    pub extern "c" fn qs_threadpool_pending_tasks(pool: ?*const QsThreadPool) usize;
    pub extern "c" fn qs_threadpool_worker_cpu(pool: ?*const QsThreadPool, worker_idx: usize) c_int;
};

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unlink(pathname: [*:0]const u8) c_int;

test "sysinfo: detect host topology and emit CSV/LaTeX" {
    var info: c.QsHostInfo = std.mem.zeroes(c.QsHostInfo);
    try testing.expectEqual(@as(c_int, 0), c.qs_sysinfo_detect(&info));
    try testing.expect(info.logical_cpus > 0);
    try testing.expect(info.l1d_bytes > 0);
    try testing.expect(info.l3_bytes > 0);
    try testing.expect(info.num_caches > 0);
    try testing.expect(info.caches[0].size_bytes > 0);

    const csv_path = "/tmp/opencode/test_sysinfo.csv";
    const tex_path = "/tmp/opencode/test_sysinfo.tex";
    defer {
        _ = unlink(csv_path);
        _ = unlink(tex_path);
    }

    try testing.expectEqual(@as(c_int, 0), c.qs_sysinfo_write_csv(&info, csv_path));
    try testing.expectEqual(@as(c_int, 0), c.qs_sysinfo_write_latex(&info, tex_path));
}

test "ui: headless and fallback when libqs_tui.so is absent" {
    const ui = c.qs_ui_create(10, true, "/tmp/opencode/nonexistent_libqs_tui.so");
    try testing.expect(ui != null);
    defer c.qs_ui_destroy(ui);

    try testing.expect(!c.qs_ui_is_tui(ui));

    var telem: c.QsUiTelemetry = std.mem.zeroes(c.QsUiTelemetry);
    telem.benchmark_name = "test_bench";
    telem.dataset_name = "random";
    telem.variant_name = "baseline";
    telem.current_step = 1;
    telem.total_steps = 10;
    telem.array_size = 1024;
    telem.last_time_ns = 12345.0;
    c.qs_ui_update(ui, &telem);
    c.qs_ui_log(ui, "step %d ok", @as(c_int, 1));
    c.qs_ui_finish(ui, "done");

    _ = setenv("__QS_UI_SHUT_UP", "0", 1);
    defer _ = setenv("__QS_UI_SHUT_UP", "1", 1);

    const ui_fallback = c.qs_ui_create(5, false, null);
    try testing.expect(ui_fallback != null);
    defer c.qs_ui_destroy(ui_fallback);
    try testing.expect(!c.qs_ui_is_tui(ui_fallback));
    c.qs_ui_update(ui_fallback, &telem);
    c.qs_ui_finish(ui_fallback, "fallback done");

    var pb: c.QsPbar = std.mem.zeroes(c.QsPbar);
    c.qs_pbar_init(&pb, 10, 24, false);
    c.qs_pbar_update(&pb, 5, "halfway", 1000.0);
    c.qs_pbar_finish(&pb, "complete");
}

test "vec: presets random, sorted (asc & desc), reverse, repeated, constant, organ_pipe, sawtooth, adversarial_med3" {
    const n: usize = 64;

    const v_rand = c.qs_vec_preset_random(n, -100, 100, 42).?;
    defer c.qs_vec_destroy(v_rand);
    try testing.expectEqual(n, v_rand.len);
    for (0..n) |i| {
        const val = v_rand.data[i];
        try testing.expect(val >= -100 and val <= 100);
    }

    const v_asc = c.qs_vec_preset_sorted(n, c.QS_ORDER_ASC, 10, 3).?;
    defer c.qs_vec_destroy(v_asc);
    try testing.expect(c.qs_vec_is_sorted(v_asc.data, v_asc.len, c.QS_ORDER_ASC));
    try testing.expectEqual(@as(c_int, 10), v_asc.data[0]);
    try testing.expectEqual(@as(c_int, 13), v_asc.data[1]);

    const v_desc = c.qs_vec_preset_sorted(n, c.QS_ORDER_DESC, 10, 3).?;
    defer c.qs_vec_destroy(v_desc);
    try testing.expect(c.qs_vec_is_sorted(v_desc.data, v_desc.len, c.QS_ORDER_DESC));

    const v_rev = c.qs_vec_preset_reverse(n).?;
    defer c.qs_vec_destroy(v_rev);
    try testing.expect(c.qs_vec_is_sorted(v_rev.data, v_rev.len, c.QS_ORDER_DESC));
    try testing.expectEqual(@as(c_int, @intCast(n)), v_rev.data[0]);
    try testing.expectEqual(@as(c_int, 1), v_rev.data[n - 1]);

    const v_rep = c.qs_vec_preset_repeated(n, 4, 99).?;
    defer c.qs_vec_destroy(v_rep);
    for (0..n) |i| {
        try testing.expect(v_rep.data[i] >= 1 and v_rep.data[i] <= 4);
    }

    const v_const = c.qs_vec_preset_constant(n, 77).?;
    defer c.qs_vec_destroy(v_const);
    try testing.expect(c.qs_vec_is_sorted(v_const.data, v_const.len, c.QS_ORDER_ASC));
    try testing.expect(c.qs_vec_is_sorted(v_const.data, v_const.len, c.QS_ORDER_DESC));
    try testing.expectEqual(@as(c_int, 77), v_const.data[0]);
    try testing.expectEqual(@as(c_int, 77), v_const.data[n - 1]);

    const v_organ = c.qs_vec_preset_organ_pipe(n).?;
    defer c.qs_vec_destroy(v_organ);
    try testing.expectEqual(v_organ.data[0], v_organ.data[n - 1]);
    try testing.expect(v_organ.data[n / 2] >= v_organ.data[0]);

    const v_saw = c.qs_vec_preset_sawtooth(n, 8, c.QS_ORDER_ASC).?;
    defer c.qs_vec_destroy(v_saw);
    try testing.expectEqual(@as(c_int, 0), v_saw.data[0]);
    try testing.expectEqual(@as(c_int, 7), v_saw.data[7]);
    try testing.expectEqual(@as(c_int, 0), v_saw.data[8]);

    const v_adv = c.qs_vec_preset_adversarial_med3(n).?;
    defer c.qs_vec_destroy(v_adv);
    const v_one_to_n = c.qs_vec_preset_sorted(n, c.QS_ORDER_ASC, 1, 1).?;
    defer c.qs_vec_destroy(v_one_to_n);
    try testing.expectEqual(v_one_to_n.multiset_hash, v_adv.multiset_hash);
}

test "vec: multiset_hash invariance under reversal and partial_sort, and corruption detection" {
    const n: usize = 128;
    const v = c.qs_vec_preset_random(n, -5000, 5000, 12345).?;
    defer c.qs_vec_destroy(v);

    const orig_hash = v.multiset_hash;
    try testing.expectEqual(orig_hash, c.qs_vec_multiset_hash(v.data, v.len));

    c.qs_vec_reverse_in_place(v);
    try testing.expectEqual(orig_hash, c.qs_vec_multiset_hash(v.data, v.len));

    try testing.expect(c.qs_vec_partial_sort(v, 0.0, c.QS_ORDER_ASC, 111));
    try testing.expectEqual(orig_hash, c.qs_vec_multiset_hash(v.data, v.len));

    try testing.expect(c.qs_vec_partial_sort(v, 0.5, c.QS_ORDER_ASC, 222));
    try testing.expectEqual(orig_hash, c.qs_vec_multiset_hash(v.data, v.len));

    try testing.expect(c.qs_vec_partial_sort(v, 1.0, c.QS_ORDER_ASC, 333));
    try testing.expect(c.qs_vec_verify(v.data, v.len, c.QS_ORDER_ASC, orig_hash));

    v.data[n / 2] +%= 1;
    try testing.expect(!c.qs_vec_verify(v.data, v.len, c.QS_ORDER_ASC, orig_hash));
}

test "vec: algebraic combinators concat, interleave, blend, reversed, slice" {
    const a = c.qs_vec_preset_sorted(4, c.QS_ORDER_ASC, 1, 1).?; // [1, 2, 3, 4]
    defer c.qs_vec_destroy(a);

    const b = c.qs_vec_preset_sorted(3, c.QS_ORDER_ASC, 10, 10).?; // [10, 20, 30]
    defer c.qs_vec_destroy(b);

    const cat = c.qs_vec_concat(a, b).?;
    defer c.qs_vec_destroy(cat);
    try testing.expectEqual(@as(usize, 7), cat.len);
    try testing.expectEqual(@as(c_int, 1), cat.data[0]);
    try testing.expectEqual(@as(c_int, 4), cat.data[3]);
    try testing.expectEqual(@as(c_int, 10), cat.data[4]);
    try testing.expectEqual(@as(c_int, 30), cat.data[6]);

    const ilv = c.qs_vec_interleave(a, b).?;
    defer c.qs_vec_destroy(ilv);
    try testing.expectEqual(@as(usize, 7), ilv.len);
    try testing.expectEqual(cat.multiset_hash, ilv.multiset_hash);
    try testing.expectEqual(@as(c_int, 1), ilv.data[0]);
    try testing.expectEqual(@as(c_int, 10), ilv.data[1]);
    try testing.expectEqual(@as(c_int, 2), ilv.data[2]);
    try testing.expectEqual(@as(c_int, 20), ilv.data[3]);

    const blended = c.qs_vec_blend(a, b, 0.5, 777).?;
    defer c.qs_vec_destroy(blended);
    try testing.expectEqual(@as(usize, 7), blended.len);
    try testing.expectEqual(cat.multiset_hash, blended.multiset_hash);

    const rev = c.qs_vec_reversed(a).?;
    defer c.qs_vec_destroy(rev);
    try testing.expectEqual(@as(usize, 4), rev.len);
    try testing.expectEqual(a.multiset_hash, rev.multiset_hash);
    try testing.expectEqual(@as(c_int, 4), rev.data[0]);
    try testing.expectEqual(@as(c_int, 1), rev.data[3]);

    const sl = c.qs_vec_slice(cat, 2, 5).?;
    defer c.qs_vec_destroy(sl);
    try testing.expectEqual(@as(usize, 3), sl.len);
    try testing.expectEqual(@as(c_int, 3), sl.data[0]);
    try testing.expectEqual(@as(c_int, 4), sl.data[1]);
    try testing.expectEqual(@as(c_int, 10), sl.data[2]);
}

const NestedCtx = struct {
    pool: *c.QsThreadPool,
    counter: std.atomic.Value(u32),
};

fn leafTask(arg: ?*anyopaque) callconv(.c) void {
    const ctx: *NestedCtx = @ptrCast(@alignCast(arg.?));
    _ = ctx.counter.fetchAdd(1, .acq_rel);
}

fn parentTask(arg: ?*anyopaque) callconv(.c) void {
    const ctx: *NestedCtx = @ptrCast(@alignCast(arg.?));
    _ = ctx.counter.fetchAdd(1, .acq_rel);
    for (0..8) |_| {
        _ = c.qs_threadpool_submit(ctx.pool, leafTask, ctx);
    }
}

test "threadpool: parallel execution and nested task submission without deadlock" {
    const pins = [_]c_int{ 0, 1, 2, 3 };
    const pool = c.qs_threadpool_create(4, &pins, pins.len);
    try testing.expect(pool != null);
    defer c.qs_threadpool_destroy(pool);

    try testing.expectEqual(@as(usize, 4), c.qs_threadpool_num_threads(pool));
    try testing.expectEqual(@as(c_int, 0), c.qs_threadpool_worker_cpu(pool, 0));

    var ctx = NestedCtx{
        .pool = pool.?,
        .counter = std.atomic.Value(u32).init(0),
    };

    const parents: u32 = 16;
    for (0..parents) |_| {
        try testing.expect(c.qs_threadpool_submit(pool, parentTask, &ctx));
    }

    c.qs_threadpool_wait_all(pool);
    try testing.expectEqual(parents + parents * 8, ctx.counter.load(.acquire));
    try testing.expectEqual(@as(usize, 0), c.qs_threadpool_pending_tasks(pool));
}
