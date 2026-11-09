// SPDX-License-Identifier: ISC

#include "jit.h"
#include "util.h"

#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

struct QsJitCache {
	char build_dir[192];
	QsJitModule static_fastpath;
	QsJitModule *modules;
	size_t count;
	size_t cap;
};

static bool ensure_dir_recursive(const char *dir)
{
	if (dir == nullptr || dir[0] == '\0') {
		return false;
	}

	char tmp[256];
	int n = snprintf(tmp, sizeof(tmp), "%s", dir);
	if (n < 0 || (size_t)n >= sizeof(tmp)) {
		return false;
	}

	size_t len = (size_t)n;
	if (len > 1 && tmp[len - 1] == '/') {
		tmp[len - 1] = '\0';
	}

	for (char *p = tmp + 1; *p != '\0'; p++) {
		if (*p == '/') {
			*p = '\0';
			if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
				return false;
			}
			*p = '/';
		}
	}

	if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
		return false;
	}
	return true;
}

static bool file_exists(const char *path)
{
	struct stat st;
	return path != nullptr && stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

[[nodiscard]] QsJitOptions qs_jit_options_default(void)
{
	QsJitOptions opts = {
		.cc = "clang",
		.cflags = "-O3 -march=native",
		.pragma_unroll_full = false,
		.pragma_no_unroll = false,
		.pragma_vectorize = false,
		.pragma_no_vectorize = false,
		.emit_asm = false,
		.force_recompile = false,
	};
	return opts;
}

static uint64_t hash_jit_options(const QsJitOptions *opts)
{
	const char *cc = (opts->cc != nullptr && opts->cc[0] != '\0') ? opts->cc : "clang";
	const char *cflags = (opts->cflags != nullptr) ? opts->cflags : "-O3 -march=native";

	uint64_t h = QS_FNV1A_OFFSET;
	h = qs_hash_str(cc, h);
	h = qs_hash_bytes(":", 1, h);
	h = qs_hash_str(cflags, h);
	h = qs_hash_bytes(":", 1, h);

	uint8_t flags[4] = {
		opts->pragma_unroll_full ? 1U : 0U,
		opts->pragma_no_unroll ? 1U : 0U,
		opts->pragma_vectorize ? 1U : 0U,
		opts->pragma_no_vectorize ? 1U : 0U,
	};
	h = qs_hash_bytes(flags, sizeof(flags), h);
	return h;
}

static bool is_default_fastpath_options(const QsJitOptions *opts)
{
	if (opts == nullptr) {
		return true;
	}
	if (opts->pragma_unroll_full || opts->pragma_no_unroll || opts->pragma_vectorize ||
	    opts->pragma_no_vectorize || opts->emit_asm || opts->force_recompile) {
		return false;
	}
	if (opts->cc != nullptr && opts->cc[0] != '\0' && strcmp(opts->cc, "clang") != 0) {
		return false;
	}
	if (opts->cflags != nullptr && opts->cflags[0] != '\0' &&
	    strcmp(opts->cflags, "-O3 -march=native") != 0 &&
	    strcmp(opts->cflags, "default") != 0) {
		return false;
	}
	return true;
}

[[nodiscard]] QsJitCache *qs_jit_cache_create(const char *build_dir)
{
	QsJitCache *cache = calloc(1, sizeof(*cache));
	if (cache == nullptr) {
		return nullptr;
	}

	const char *dir = (build_dir != nullptr && build_dir[0] != '\0') ? build_dir : "build/jit";
	int n = snprintf(cache->build_dir, sizeof(cache->build_dir), "%s", dir);
	if (n < 0 || (size_t)n >= sizeof(cache->build_dir)) {
		free(cache);
		return nullptr;
	}

	size_t len = (size_t)n;
	while (len > 1 && cache->build_dir[len - 1] == '/') {
		cache->build_dir[len - 1] = '\0';
		len--;
	}

	if (!ensure_dir_recursive(cache->build_dir)) {
		free(cache);
		return nullptr;
	}

	QsJitOptions def_opts = qs_jit_options_default();
	cache->static_fastpath.dl_handle = nullptr;
	cache->static_fastpath.run_clean = qs_run_clean;
	cache->static_fastpath.run_counted = qs_run_counted;
	cache->static_fastpath.key_hash = hash_jit_options(&def_opts);
	snprintf(cache->static_fastpath.so_path, sizeof(cache->static_fastpath.so_path),
		 "<static-fastpath>");
	cache->static_fastpath.asm_path[0] = '\0';
	cache->static_fastpath.is_static_fastpath = true;

	return cache;
}

void qs_jit_cache_destroy(QsJitCache *cache)
{
	if (cache == nullptr) {
		return;
	}
	for (size_t i = 0; i < cache->count; i++) {
		if (cache->modules[i].dl_handle != nullptr) {
			dlclose(cache->modules[i].dl_handle);
			cache->modules[i].dl_handle = nullptr;
		}
	}
	free(cache->modules);
	free(cache);
}

static void build_pragma_defines(const QsJitOptions *opts, char *buf, size_t buf_sz)
{
	buf[0] = '\0';
	size_t off = 0;

	if (opts->pragma_unroll_full) {
		int w = snprintf(buf + off, buf_sz - off,
				 " -DQS_PRAGMA_UNROLL_FULL=1 -DPRAGMA_UNROLL_FULL=1");
		if (w > 0 && off + (size_t)w < buf_sz) {
			off += (size_t)w;
		}
	}
	if (opts->pragma_no_unroll) {
		int w = snprintf(buf + off, buf_sz - off,
				 " -DQS_PRAGMA_NO_UNROLL=1 -DPRAGMA_NO_UNROLL=1");
		if (w > 0 && off + (size_t)w < buf_sz) {
			off += (size_t)w;
		}
	}
	if (opts->pragma_vectorize) {
		int w = snprintf(buf + off, buf_sz - off,
				 " -DQS_PRAGMA_VECTORIZE=1 -DPRAGMA_VECTORIZE=1");
		if (w > 0 && off + (size_t)w < buf_sz) {
			off += (size_t)w;
		}
	}
	if (opts->pragma_no_vectorize) {
		int w = snprintf(buf + off, buf_sz - off,
				 " -DQS_PRAGMA_NO_VECTORIZE=1 -DPRAGMA_NO_VECTORIZE=1");
		if (w > 0 && off + (size_t)w < buf_sz) {
			off += (size_t)w;
		}
	}
}

static bool run_compiler_cmd(const char *cmd)
{
	int status = system(cmd);
	if (status == -1) {
		return false;
	}
	return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static bool compile_kernel_so(const QsJitOptions *opts, const char *so_path)
{
	const char *cc = (opts->cc != nullptr && opts->cc[0] != '\0') ? opts->cc : "clang";
	const char *cflags = (opts->cflags != nullptr && opts->cflags[0] != '\0') ?
				     opts->cflags :
				     "-O3 -march=native";

	char pragma_defs[256];
	build_pragma_defines(opts, pragma_defs, sizeof(pragma_defs));

	char cmd[1024];
	int n = snprintf(cmd, sizeof(cmd),
			 "%s -std=c23 -D_GNU_SOURCE -shared -fPIC -Iinclude %s%s "
			 "src/quicksort_kernel.c -o '%s'",
			 cc, cflags, pragma_defs, so_path);
	if (n < 0 || (size_t)n >= sizeof(cmd)) {
		return false;
	}
	return run_compiler_cmd(cmd);
}

static bool compile_kernel_asm(const QsJitOptions *opts, const char *asm_path)
{
	const char *cc = (opts->cc != nullptr && opts->cc[0] != '\0') ? opts->cc : "clang";
	const char *cflags = (opts->cflags != nullptr && opts->cflags[0] != '\0') ?
				     opts->cflags :
				     "-O3 -march=native";

	char pragma_defs[256];
	build_pragma_defines(opts, pragma_defs, sizeof(pragma_defs));

	char cmd[1024];
	int n = snprintf(cmd, sizeof(cmd),
			 "%s -std=c23 -D_GNU_SOURCE -S -fverbose-asm -Iinclude %s%s "
			 "src/quicksort_kernel.c -o '%s'",
			 cc, cflags, pragma_defs, asm_path);
	if (n < 0 || (size_t)n >= sizeof(cmd)) {
		return false;
	}
	return run_compiler_cmd(cmd);
}

static bool load_module_symbols(QsJitModule *mod)
{
	char dl_path[260];
	if (strchr(mod->so_path, '/') == nullptr) {
		snprintf(dl_path, sizeof(dl_path), "./%s", mod->so_path);
	} else {
		snprintf(dl_path, sizeof(dl_path), "%s", mod->so_path);
	}

	dlerror();
	void *handle = dlopen(dl_path, RTLD_NOW | RTLD_LOCAL);
	if (handle == nullptr) {
		return false;
	}

	QsKernelFn clean_fn = nullptr;
	QsKernelFn counted_fn = nullptr;
	*(void **)(&clean_fn) = dlsym(handle, "qs_run_clean");
	*(void **)(&counted_fn) = dlsym(handle, "qs_run_counted");

	if (clean_fn == nullptr || counted_fn == nullptr) {
		dlclose(handle);
		return false;
	}

	mod->dl_handle = handle;
	mod->run_clean = clean_fn;
	mod->run_counted = counted_fn;
	mod->is_static_fastpath = false;
	return true;
}

[[nodiscard]] const QsJitModule *qs_jit_acquire(QsJitCache *cache, const QsJitOptions *opts)
{
	if (cache == nullptr) {
		return nullptr;
	}

	if (is_default_fastpath_options(opts)) {
		return &cache->static_fastpath;
	}

	uint64_t hash = hash_jit_options(opts);

	char so_path[256];
	char asm_path[256];
	snprintf(so_path, sizeof(so_path), "%s/kernel_%016llx.so", cache->build_dir,
		 (unsigned long long)hash);
	snprintf(asm_path, sizeof(asm_path), "%s/kernel_%016llx.s", cache->build_dir,
		 (unsigned long long)hash);

	QsJitModule *existing = nullptr;
	for (size_t i = 0; i < cache->count; i++) {
		if (cache->modules[i].key_hash == hash) {
			existing = &cache->modules[i];
			break;
		}
	}

	if (existing != nullptr && !opts->force_recompile) {
		if (opts->emit_asm && existing->asm_path[0] == '\0') {
			if (!file_exists(asm_path) && !compile_kernel_asm(opts, asm_path)) {
				return nullptr;
			}
			snprintf(existing->asm_path, sizeof(existing->asm_path), "%s", asm_path);
		}
		return existing;
	}

	if (!file_exists(so_path) || opts->force_recompile) {
		if (!compile_kernel_so(opts, so_path)) {
			return nullptr;
		}
	}

	if (opts->emit_asm && (!file_exists(asm_path) || opts->force_recompile)) {
		if (!compile_kernel_asm(opts, asm_path)) {
			return nullptr;
		}
	}

	if (existing != nullptr) {
		if (existing->dl_handle != nullptr) {
			dlclose(existing->dl_handle);
			existing->dl_handle = nullptr;
		}
		if (opts->emit_asm) {
			snprintf(existing->asm_path, sizeof(existing->asm_path), "%s", asm_path);
		}
		if (!load_module_symbols(existing)) {
			return nullptr;
		}
		return existing;
	}

	if (cache->count == cache->cap) {
		size_t new_cap = (cache->cap == 0) ? 8 : (cache->cap * 2);
		QsJitModule *new_mods = realloc(cache->modules, new_cap * sizeof(*new_mods));
		if (new_mods == nullptr) {
			return nullptr;
		}
		cache->modules = new_mods;
		cache->cap = new_cap;
	}

	QsJitModule mod = { 0 };
	mod.key_hash = hash;
	snprintf(mod.so_path, sizeof(mod.so_path), "%s", so_path);
	if (opts->emit_asm) {
		snprintf(mod.asm_path, sizeof(mod.asm_path), "%s", asm_path);
	}

	if (!load_module_symbols(&mod)) {
		return nullptr;
	}

	cache->modules[cache->count] = mod;
	cache->count++;
	return &cache->modules[cache->count - 1];
}
