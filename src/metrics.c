// SPDX-License-Identifier: ISC

#include "metrics.h"
#include "util.h"

#include <linux/perf_event.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <unistd.h>

enum {
	QS_PMU_CYCLES = 0,
	QS_PMU_INSTRUCTIONS = 1,
	QS_PMU_BRANCH_INSTRUCTIONS = 2,
	QS_PMU_BRANCH_MISSES = 3,
	QS_PMU_L1D_MISSES = 4,
	QS_PMU_LLC_MISSES = 5,
	QS_PMU_COUNT = 6,
};

struct QsMetricsCtx {
	bool enable_pmu;
	bool pmu_supported;
	int fds[QS_PMU_COUNT];
	uint64_t start_ns;
	uint8_t *thrash_buf;
	size_t thrash_len;
	volatile uint64_t sink;
};

static int open_perf_counter(uint32_t type, uint64_t config)
{
	struct perf_event_attr pe;
	memset(&pe, 0, sizeof(pe));
	pe.type = type;
	pe.size = sizeof(pe);
	pe.config = config;
	pe.disabled = 1;
	pe.exclude_kernel = 1;
	pe.exclude_hv = 1;

	long fd = syscall(SYS_perf_event_open, &pe, 0, -1, -1, 0);
	if (fd < 0) {
		return -1;
	}
	return (int)fd;
}

[[nodiscard]] QsMetricsCtx *qs_metrics_create(bool enable_pmu, size_t llc_bytes)
{
	QsMetricsCtx *ctx = calloc(1, sizeof(*ctx));
	if (ctx == nullptr) {
		return nullptr;
	}

	for (size_t i = 0; i < QS_PMU_COUNT; i++) {
		ctx->fds[i] = -1;
	}

	size_t min_thrash = 2ULL * 1024ULL * 1024ULL;
	size_t target = llc_bytes * 2ULL;
	if (target < min_thrash) {
		target = min_thrash;
	}
	target = (target + 63ULL) & ~63ULL;

	ctx->thrash_buf = aligned_alloc(64, target);
	if (ctx->thrash_buf == nullptr) {
		free(ctx);
		return nullptr;
	}
	ctx->thrash_len = target;
	memset(ctx->thrash_buf, 0xA5, ctx->thrash_len);

	ctx->enable_pmu = enable_pmu;
	ctx->pmu_supported = false;

	if (enable_pmu) {
		uint64_t l1d_cfg = (uint64_t)PERF_COUNT_HW_CACHE_L1D |
				   ((uint64_t)PERF_COUNT_HW_CACHE_OP_READ << 8) |
				   ((uint64_t)PERF_COUNT_HW_CACHE_RESULT_MISS << 16);
		uint64_t llc_cfg = (uint64_t)PERF_COUNT_HW_CACHE_LL |
				   ((uint64_t)PERF_COUNT_HW_CACHE_OP_READ << 8) |
				   ((uint64_t)PERF_COUNT_HW_CACHE_RESULT_MISS << 16);

		ctx->fds[QS_PMU_CYCLES] =
			open_perf_counter(PERF_TYPE_HARDWARE, PERF_COUNT_HW_CPU_CYCLES);
		ctx->fds[QS_PMU_INSTRUCTIONS] =
			open_perf_counter(PERF_TYPE_HARDWARE, PERF_COUNT_HW_INSTRUCTIONS);
		ctx->fds[QS_PMU_BRANCH_INSTRUCTIONS] =
			open_perf_counter(PERF_TYPE_HARDWARE, PERF_COUNT_HW_BRANCH_INSTRUCTIONS);
		ctx->fds[QS_PMU_BRANCH_MISSES] =
			open_perf_counter(PERF_TYPE_HARDWARE, PERF_COUNT_HW_BRANCH_MISSES);
		ctx->fds[QS_PMU_L1D_MISSES] = open_perf_counter(PERF_TYPE_HW_CACHE, l1d_cfg);
		ctx->fds[QS_PMU_LLC_MISSES] = open_perf_counter(PERF_TYPE_HW_CACHE, llc_cfg);

		if (ctx->fds[QS_PMU_CYCLES] >= 0 && ctx->fds[QS_PMU_INSTRUCTIONS] >= 0) {
			ctx->pmu_supported = true;
		}
	}

	return ctx;
}

void qs_metrics_destroy(QsMetricsCtx *ctx)
{
	if (ctx == nullptr) {
		return;
	}
	for (size_t i = 0; i < QS_PMU_COUNT; i++) {
		if (ctx->fds[i] >= 0) {
			close(ctx->fds[i]);
			ctx->fds[i] = -1;
		}
	}
	free(ctx->thrash_buf);
	free(ctx);
}

void qs_metrics_thrash_cache(QsMetricsCtx *ctx)
{
	if (ctx == nullptr || ctx->thrash_buf == nullptr || ctx->thrash_len == 0) {
		return;
	}

	volatile uint8_t *buf = ctx->thrash_buf;
	const size_t n = ctx->thrash_len;
	uint64_t acc = ctx->sink;

	for (size_t i = 0; i < n; i += 64) {
		uint8_t v = (uint8_t)(buf[i] + 1U);
		buf[i] = v;
		acc += v;
	}

	ctx->sink = acc;
	atomic_signal_fence(memory_order_seq_cst);
}

void qs_metrics_begin(QsMetricsCtx *ctx)
{
	if (ctx == nullptr) {
		return;
	}
	if (ctx->enable_pmu && ctx->pmu_supported) {
		for (size_t i = 0; i < QS_PMU_COUNT; i++) {
			if (ctx->fds[i] >= 0) {
				(void)ioctl(ctx->fds[i], PERF_EVENT_IOC_RESET, 0);
				(void)ioctl(ctx->fds[i], PERF_EVENT_IOC_ENABLE, 0);
			}
		}
	}
	atomic_signal_fence(memory_order_seq_cst);
	ctx->start_ns = qs_monotonic_ns();
}

static uint64_t read_counter_fd(int fd)
{
	if (fd < 0) {
		return 0;
	}
	uint64_t val = 0;
	ssize_t n = read(fd, &val, sizeof(val));
	if (n != (ssize_t)sizeof(val)) {
		return 0;
	}
	return val;
}

[[nodiscard]] QsPerfSnapshot qs_metrics_end(QsMetricsCtx *ctx)
{
	uint64_t end_ns = qs_monotonic_ns();
	atomic_signal_fence(memory_order_seq_cst);

	QsPerfSnapshot snap = { 0 };
	if (ctx == nullptr) {
		return snap;
	}

	snap.monotonic_ns = (end_ns >= ctx->start_ns) ? (end_ns - ctx->start_ns) : 0;
	snap.pmu_available = ctx->enable_pmu && ctx->pmu_supported;

	if (snap.pmu_available) {
		for (size_t i = 0; i < QS_PMU_COUNT; i++) {
			if (ctx->fds[i] >= 0) {
				(void)ioctl(ctx->fds[i], PERF_EVENT_IOC_DISABLE, 0);
			}
		}
		snap.cpu_cycles = read_counter_fd(ctx->fds[QS_PMU_CYCLES]);
		snap.instructions = read_counter_fd(ctx->fds[QS_PMU_INSTRUCTIONS]);
		snap.branch_instructions = read_counter_fd(ctx->fds[QS_PMU_BRANCH_INSTRUCTIONS]);
		snap.branch_misses = read_counter_fd(ctx->fds[QS_PMU_BRANCH_MISSES]);
		snap.l1d_misses = read_counter_fd(ctx->fds[QS_PMU_L1D_MISSES]);
		snap.llc_misses = read_counter_fd(ctx->fds[QS_PMU_LLC_MISSES]);
	}

	return snap;
}

[[nodiscard]] bool qs_metrics_pmu_supported(const QsMetricsCtx *ctx)
{
	return ctx != nullptr && ctx->pmu_supported;
}
