// SPDX-License-Identifier: ISC

#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "pbar.h"
#include "ui.h"

typedef void (*ui_vtable_update_fn)(void *impl, const QsUiTelemetry *telemetry);
typedef void (*ui_vtable_log_fn)(void *impl, const char *msg);
typedef void (*ui_vtable_finish_fn)(void *impl, const char *summary);
typedef void (*ui_vtable_destroy_fn)(void *impl);

struct QsUi {
	QsUiBackend backend;
	ui_vtable_update_fn update;
	ui_vtable_log_fn log;
	ui_vtable_finish_fn finish;
	ui_vtable_destroy_fn destroy;
	void *impl;
};

typedef struct {
	void *dl_handle;
	void *ctx;
	init_fn init;
	update_fn update;
	log_fn log;
	finish_fn finish;
	destroy_fn destroy;
} QsTuiImpl;

static void *resolve_sym(void *handle, const char *primary, const char *fallback)
{
	void *sym = dlsym(handle, primary);
	if (sym == nullptr && fallback != nullptr) {
		sym = dlsym(handle, fallback);
	}
	return sym;
}

static void tui_backend_update(void *impl, const QsUiTelemetry *telemetry)
{
	QsTuiImpl *tui = impl;
	if (tui != nullptr && tui->update != nullptr) {
		tui->update(tui->ctx, telemetry);
	}
}

static void tui_backend_log(void *impl, const char *msg)
{
	QsTuiImpl *tui = impl;
	if (tui != nullptr && tui->log != nullptr) {
		tui->log(tui->ctx, msg);
	}
}

static void tui_backend_finish(void *impl, const char *summary)
{
	QsTuiImpl *tui = impl;
	if (tui != nullptr && tui->finish != nullptr) {
		tui->finish(tui->ctx, summary);
	}
}

static void tui_backend_destroy(void *impl)
{
	QsTuiImpl *tui = impl;
	if (tui == nullptr) {
		return;
	}
	if (tui->destroy != nullptr && tui->ctx != nullptr) {
		tui->destroy(tui->ctx);
	}
	if (tui->dl_handle != nullptr) {
		dlclose(tui->dl_handle);
	}
	free(tui);
}

static void pbar_backend_update(void *impl, const QsUiTelemetry *telemetry)
{
	QsPbar *pb = impl;
	if (pb == nullptr || telemetry == nullptr) {
		return;
	}
	if (telemetry->total_steps > 0) {
		pb->total = telemetry->total_steps;
	}

	char label[128];
	const char *bench = telemetry->benchmark_name != nullptr ? telemetry->benchmark_name : "qs";
	const char *var = telemetry->variant_name != nullptr ? telemetry->variant_name : "default";
	const char *ds = telemetry->dataset_name != nullptr ? telemetry->dataset_name : "data";
	snprintf(label, sizeof(label), "%s:%s/%s (n=%zu)", bench, var, ds, telemetry->array_size);

	qs_pbar_update(pb, telemetry->current_step, label, telemetry->last_time_ns);
}

static void pbar_backend_log(void *impl, const char *msg)
{
	QsPbar *pb = impl;
	if (pb == nullptr || !pb->enabled || msg == nullptr) {
		return;
	}
	fprintf(stderr, "\r\033[K[qs] %s\n", msg);
	pb->last_render_ns = 0;
}

static void pbar_backend_finish(void *impl, const char *summary)
{
	QsPbar *pb = impl;
	qs_pbar_finish(pb, summary);
}

static void pbar_backend_destroy(void *impl)
{
	free(impl);
}

static void headless_backend_update([[maybe_unused]] void *impl,
				    [[maybe_unused]] const QsUiTelemetry *telemetry)
{
}

static void headless_backend_log([[maybe_unused]] void *impl, [[maybe_unused]] const char *msg)
{
}

static void headless_backend_finish([[maybe_unused]] void *impl,
				    [[maybe_unused]] const char *summary)
{
}

static void headless_backend_destroy(void *impl)
{
	free(impl);
}

static QsTuiImpl *try_load_tui(size_t total_steps, const char *so_path, const char **err_out)
{
	const char *path = (so_path != nullptr && so_path[0] != '\0') ? so_path :
									"build/libqs_tui.so";
	dlerror();
	void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
	if (handle == nullptr) {
		const char *dl_err = dlerror();
		*err_out = dl_err != nullptr ? dl_err : "dlopen failed";
		return nullptr;
	}

	QsTuiImpl *tui = calloc(1, sizeof(*tui));
	if (tui == nullptr) {
		*err_out = "out of memory";
		dlclose(handle);
		return nullptr;
	}
	tui->dl_handle = handle;

	*(void **)(&tui->init) = resolve_sym(handle, "qs_tui_init", "init_fn");
	*(void **)(&tui->update) = resolve_sym(handle, "qs_tui_update", "update_fn");
	*(void **)(&tui->log) = resolve_sym(handle, "qs_tui_log", "log_fn");
	*(void **)(&tui->finish) = resolve_sym(handle, "qs_tui_finish", "finish_fn");
	*(void **)(&tui->destroy) = resolve_sym(handle, "qs_tui_destroy", "destroy_fn");

	if (tui->init == nullptr || tui->update == nullptr || tui->log == nullptr ||
	    tui->finish == nullptr || tui->destroy == nullptr) {
		const char *dl_err = dlerror();
		*err_out = dl_err != nullptr ? dl_err : "missing required TUI symbols";
		dlclose(handle);
		free(tui);
		return nullptr;
	}

	tui->ctx = tui->init(total_steps);
	if (tui->ctx == nullptr) {
		*err_out = "qs_tui_init returned nullptr";
		dlclose(handle);
		free(tui);
		return nullptr;
	}

	return tui;
}

[[nodiscard("Using UI requires holding its opaque handle")]]
QsUi *qs_ui_create(size_t total_steps, bool prefer_tui, const char *so_path)
{
	QsUi *ui = calloc(1, sizeof(*ui));
	if (ui == nullptr) {
		return nullptr;
	}

	const char *quiet_env = getenv("__QS_UI_SHUT_UP");
	bool quiet = (quiet_env != nullptr && quiet_env[0] != '\0' && quiet_env[0] != '0');
	bool is_tty = (isatty(STDERR_FILENO) != 0);

	if (quiet) {
		ui->backend = QS_UI_BACKEND_HEADLESS;
		ui->update = headless_backend_update;
		ui->log = headless_backend_log;
		ui->finish = headless_backend_finish;
		ui->destroy = headless_backend_destroy;
		ui->impl = nullptr;
		return ui;
	}

	if (prefer_tui && (is_tty || so_path != nullptr)) {
		const char *err_msg = "unknown error";
		QsTuiImpl *tui = try_load_tui(total_steps, so_path, &err_msg);
		if (tui != nullptr) {
			ui->backend = QS_UI_BACKEND_TUI;
			ui->update = tui_backend_update;
			ui->log = tui_backend_log;
			ui->finish = tui_backend_finish;
			ui->destroy = tui_backend_destroy;
			ui->impl = tui;
			return ui;
		}
		fprintf(stderr, "[ui] OpenTUI plugin unavailable (%s); falling back to pbar.\n",
			err_msg);
	}

	if (!is_tty) {
		ui->backend = QS_UI_BACKEND_HEADLESS;
		ui->update = headless_backend_update;
		ui->log = headless_backend_log;
		ui->finish = headless_backend_finish;
		ui->destroy = headless_backend_destroy;
		ui->impl = nullptr;
		return ui;
	}

	QsPbar *pb = calloc(1, sizeof(*pb));
	if (pb == nullptr) {
		free(ui);
		return nullptr;
	}
	qs_pbar_init(pb, total_steps, 36U, true);

	ui->backend = QS_UI_BACKEND_PBAR;
	ui->update = pbar_backend_update;
	ui->log = pbar_backend_log;
	ui->finish = pbar_backend_finish;
	ui->destroy = pbar_backend_destroy;
	ui->impl = pb;
	return ui;
}

void qs_ui_update(QsUi *ui, const QsUiTelemetry *telemetry)
{
	if (ui != nullptr && ui->update != nullptr) {
		ui->update(ui->impl, telemetry);
	}
}

void qs_ui_log(QsUi *ui, const char *fmt, ...)
{
	if (ui == nullptr || ui->log == nullptr || fmt == nullptr) {
		return;
	}

	char buf[512];
	va_list args;
	va_start(args, fmt);
	vsnprintf(buf, sizeof(buf), fmt, args);
	va_end(args);

	ui->log(ui->impl, buf);
}

void qs_ui_finish(QsUi *ui, const char *summary)
{
	if (ui != nullptr && ui->finish != nullptr) {
		ui->finish(ui->impl, summary);
	}
}

void qs_ui_destroy(QsUi *ui)
{
	if (ui == nullptr) {
		return;
	}
	if (ui->destroy != nullptr) {
		ui->destroy(ui->impl);
	}
	free(ui);
}

[[nodiscard]]
bool qs_ui_is_tui(const QsUi *ui)
{
	return ui != nullptr && ui->backend == QS_UI_BACKEND_TUI;
}
