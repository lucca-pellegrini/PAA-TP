#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "quicksort.h"

typedef struct QsJitOptions {
	const char *cc;
	const char *cflags;
	unsigned int pragma_unroll_count;
	bool pragma_no_unroll;
	bool pragma_vectorize;
	bool pragma_no_vectorize;
	bool emit_asm;
	bool force_recompile;
} QsJitOptions;

typedef struct QsJitModule {
	void *dl_handle;
	QsKernelFn run_clean;
	QsKernelFn run_counted;
	uint64_t key_hash;
	char so_path[256];
	char asm_path[256];
	bool is_static_fastpath;
} QsJitModule;

typedef struct QsJitCache QsJitCache;

[[nodiscard]] QsJitOptions qs_jit_options_default(void);
[[nodiscard]] QsJitCache *qs_jit_cache_create(const char *build_dir);
void qs_jit_cache_destroy(QsJitCache *cache);

[[nodiscard]] const QsJitModule *qs_jit_acquire(QsJitCache *cache, const QsJitOptions *opts);
