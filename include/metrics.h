#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct QsPerfSnapshot {
	uint64_t monotonic_ns;
	uint64_t cpu_cycles;
	uint64_t instructions;
	uint64_t branch_instructions;
	uint64_t branch_misses;
	uint64_t l1d_misses;
	uint64_t llc_misses;
	bool pmu_available;
} QsPerfSnapshot;

typedef struct QsMetricsCtx QsMetricsCtx;

[[nodiscard]] QsMetricsCtx *qs_metrics_create(bool enable_pmu, size_t llc_bytes);
void qs_metrics_destroy(QsMetricsCtx *ctx);

void qs_metrics_thrash_cache(QsMetricsCtx *ctx);
void qs_metrics_begin(QsMetricsCtx *ctx);
[[nodiscard]] QsPerfSnapshot qs_metrics_end(QsMetricsCtx *ctx);
[[nodiscard]] bool qs_metrics_pmu_supported(const QsMetricsCtx *ctx);
