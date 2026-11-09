// SPDX-License-Identifier: ISC

#pragma once
#ifndef UI_H
#define UI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
	const char *benchmark_name;
	const char *dataset_name;
	const char *variant_name;
	size_t current_step;
	size_t total_steps;
	size_t current_rep;
	size_t total_reps;
	size_t array_size;
	uint32_t active_threads;
	int pinned_cpu;
	double last_time_ns;
	uint64_t comparisons;
	uint64_t swaps;
	uint64_t cycles;
	uint64_t instructions;
	uint64_t branch_misses;
	uint64_t l1d_misses;
	uint64_t llc_misses;
} QsUiTelemetry;

typedef enum {
	QS_UI_BACKEND_TUI,
	QS_UI_BACKEND_PBAR,
	QS_UI_BACKEND_HEADLESS,
} QsUiBackend;

typedef void *(*init_fn)(size_t total_steps);
typedef void (*update_fn)(void *ctx, const QsUiTelemetry *telemetry);
typedef void (*log_fn)(void *ctx, const char *msg);
typedef void (*finish_fn)(void *ctx, const char *summary);
typedef void (*destroy_fn)(void *ctx);

typedef struct QsUi QsUi;

[[nodiscard("Using UI requires holding its opaque handle")]]
QsUi *qs_ui_create(size_t total_steps, bool prefer_tui, const char *so_path);

void qs_ui_update(QsUi *ui, const QsUiTelemetry *telemetry);
void qs_ui_log(QsUi *ui, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
void qs_ui_finish(QsUi *ui, const char *summary);
void qs_ui_destroy(QsUi *ui);

[[nodiscard]]
bool qs_ui_is_tui(const QsUi *ui);

#endif // !UI_H
