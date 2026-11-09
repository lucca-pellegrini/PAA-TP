#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

typedef struct {
	uint32_t level;
	char type[16];
	size_t size_bytes;
	uint32_t line_size;
	uint32_t ways;
} QsCacheLevel;

typedef struct {
	char cpu_model[128];
	char kernel_release[64];
	char compiler_version[128];
	uint32_t logical_cpus;
	uint32_t physical_cores;
	size_t total_ram_bytes;
	int perf_event_paranoid;
	size_t l1d_bytes;
	size_t l1i_bytes;
	size_t l2_bytes;
	size_t l3_bytes;
	uint32_t cache_line_bytes;
	QsCacheLevel caches[8];
	size_t num_caches;
} QsHostInfo;

[[nodiscard]] int qs_sysinfo_detect(QsHostInfo *out);
void qs_sysinfo_print(const QsHostInfo *info, FILE *stream);
[[nodiscard]] int qs_sysinfo_write_csv(const QsHostInfo *info, const char *path);
[[nodiscard]] int qs_sysinfo_write_latex(const QsHostInfo *info, const char *path);
