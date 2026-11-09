#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "threadpool.h"
#include "vec.h"

typedef enum QsPartition {
	QS_PART_HOARE = 0,
	QS_PART_LOMUTO = 1,
	QS_PART_THREE_WAY = 2,
	QS_PART_PDQ = 3,
} QsPartition;

typedef enum QsPivot {
	QS_PIVOT_FIRST = 0,
	QS_PIVOT_LAST = 1,
	QS_PIVOT_MIDDLE = 2,
	QS_PIVOT_RANDOM = 3,
	QS_PIVOT_MEDIAN3 = 4,
	QS_PIVOT_NINTHER = 5,
} QsPivot;

typedef enum QsSmallSort {
	QS_SMALL_NONE = 0,
	QS_SMALL_INSERTION = 1,
	QS_SMALL_BINARY_INSERTION = 2,
	QS_SMALL_SHELL = 3,
	QS_SMALL_HEAPSORT = 4,
} QsSmallSort;

typedef enum QsExecMode {
	QS_EXEC_RECURSIVE = 0,
	QS_EXEC_TAIL_CALL = 1,
	QS_EXEC_ITERATIVE = 2,
	QS_EXEC_PARALLEL = 3,
} QsExecMode;

typedef struct QsConfig {
	QsPartition partition;
	QsPivot pivot;
	QsSmallSort small_sort;
	QsExecMode exec_mode;
	QsOrder order;
	size_t cutoff;
	size_t max_depth;
	size_t parallel_threshold;
	bool introsort_fallback;
	uint64_t seed;
	QsThreadPool *pool;
} QsConfig;

typedef struct QsRunStats {
	uint64_t comparisons;
	uint64_t swaps;
	uint64_t moves;
	size_t max_depth_reached;
	size_t bad_partitions;
	size_t heapsort_fallbacks;
	bool depth_limit_exceeded;
} QsRunStats;

typedef bool (*QsKernelFn)(int *arr, size_t n, const QsConfig *cfg, QsRunStats *stats);

[[nodiscard]] QsConfig qs_config_default(void);

bool qs_run_clean(int *arr, size_t n, const QsConfig *cfg, QsRunStats *stats);
bool qs_run_counted(int *arr, size_t n, const QsConfig *cfg, QsRunStats *stats);

[[nodiscard]] const char *qs_partition_name(QsPartition part);
[[nodiscard]] const char *qs_pivot_name(QsPivot pivot);
[[nodiscard]] const char *qs_small_sort_name(QsSmallSort small);
[[nodiscard]] const char *qs_exec_mode_name(QsExecMode mode);
