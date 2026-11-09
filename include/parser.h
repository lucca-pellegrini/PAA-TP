#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "jit.h"
#include "quicksort.h"
#include "vec.h"

typedef enum QsVecExprKind : uint8_t {
	QS_VEXPR_RANDOM = 0,
	QS_VEXPR_SORTED,
	QS_VEXPR_REVERSE,
	QS_VEXPR_REPEATED,
	QS_VEXPR_CONSTANT,
	QS_VEXPR_ORGAN_PIPE,
	QS_VEXPR_SAWTOOTH,
	QS_VEXPR_ADVERSARIAL_MED3,
	QS_VEXPR_VAR,
	QS_VEXPR_CONCAT,
	QS_VEXPR_INTERLEAVE,
	QS_VEXPR_BLEND,
	QS_VEXPR_REVERSED,
	QS_VEXPR_PARTIAL_SORT,
	QS_VEXPR_SLICE,
} QsVecExprKind;

typedef struct QsSizeSpec {
	bool is_relative;
	size_t fixed_len;
	double n_scale;
} QsSizeSpec;

typedef struct QsVecExpr QsVecExpr;

struct QsVecExpr {
	QsVecExprKind kind;
	QsSizeSpec size;
	int min_val;
	int max_val;
	int step;
	int value;
	size_t unique_count;
	size_t period;
	double factor;
	QsOrder order;
	uint64_t seed;
	bool has_seed;
	size_t slice_start;
	size_t slice_end;
	bool slice_rel;
	double slice_start_ratio;
	double slice_end_ratio;
	char var_name[64];
	QsVecExpr *left;
	QsVecExpr *right;
};

typedef enum QsMetricFlags : uint32_t {
	QS_METRIC_MONOTONIC_NS = 1u << 0,
	QS_METRIC_COMPARISONS = 1u << 1,
	QS_METRIC_SWAPS = 1u << 2,
	QS_METRIC_MOVES = 1u << 3,
	QS_METRIC_CYCLES = 1u << 4,
	QS_METRIC_INSTRUCTIONS = 1u << 5,
	QS_METRIC_BRANCHES = 1u << 6,
	QS_METRIC_BRANCH_MISSES = 1u << 7,
	QS_METRIC_L1D_MISSES = 1u << 8,
	QS_METRIC_LLC_MISSES = 1u << 9,
	QS_METRIC_ALL = 0x3FFu,
} QsMetricFlags;

typedef struct QsHostConfig {
	int pin_cpus[64];
	size_t num_pin_cpus;
	bool cold_cache;
	bool enable_pmu;
	size_t repetitions;
	size_t warmup;
	uint64_t seed;
} QsHostConfig;

typedef struct QsLetBinding {
	char name[64];
	QsVecExpr *expr;
} QsLetBinding;

typedef struct QsDatasetSpec {
	char name[64];
	size_t sizes[32];
	size_t num_sizes;
	QsVecExpr *expr;
} QsDatasetSpec;

typedef struct QsVariantSpec {
	char name[64];
	QsConfig cfg;
	QsJitOptions jit;
	char cflags_buf[256];
	char cc_buf[64];
} QsVariantSpec;

typedef struct QsBenchmarkSpec {
	char name[64];
	char dataset_names[32][64];
	size_t num_datasets;
	char variant_names[32][64];
	size_t num_variants;
	uint32_t metrics_mask;
	char output_csv[256];
	char output_latex[256];
	char output_asm_dir[256];
	size_t repetitions;
	int cold_cache_override;
} QsBenchmarkSpec;

typedef struct QsSimPlan {
	QsHostConfig host;
	QsLetBinding bindings[64];
	size_t num_bindings;
	QsDatasetSpec datasets[64];
	size_t num_datasets;
	QsVariantSpec variants[64];
	size_t num_variants;
	QsBenchmarkSpec benchmarks[32];
	size_t num_benchmarks;
} QsSimPlan;

void qs_sim_plan_init(QsSimPlan *plan);
void qs_sim_plan_destroy(QsSimPlan *plan);

[[nodiscard("check parse result")]]
int qs_parse_file(const char *path, QsSimPlan *plan);

[[nodiscard("check parse result")]]
int qs_parse_string(const char *src, const char *virtual_filename, QsSimPlan *plan);

int qs_parse_last_warning_count(void);
void qs_parse_set_quiet(bool quiet);

[[nodiscard("evaluated vector must be freed with qs_vec_free")]]
QsVec qs_vexpr_eval(const QsVecExpr *expr, size_t target_n, const QsSimPlan *plan,
		    uint64_t run_seed);
