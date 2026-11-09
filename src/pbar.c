// SPDX-License-Identifier: ISC

#include <stdio.h>
#include <time.h>

#include "pbar.h"

static uint64_t monotonic_ns(void)
{
	struct timespec ts = { 0 };
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

void qs_pbar_init(QsPbar *pb, size_t total, uint32_t width, bool enabled)
{
	if (pb == nullptr) {
		return;
	}

	pb->total = total;
	pb->current = 0;
	pb->start_ns = monotonic_ns();
	pb->last_render_ns = 0;
	pb->width = width > 0 ? width : 36U;
	pb->enabled = enabled;
}

void qs_pbar_update(QsPbar *pb, size_t current, const char *status_label, double last_ns)
{
	if (pb == nullptr) {
		return;
	}

	pb->current = current;
	if (!pb->enabled) {
		return;
	}

	constexpr uint64_t throttle_ns = 16000000ULL;
	uint64_t now = monotonic_ns();
	if (current < pb->total && pb->last_render_ns != 0 &&
	    (now - pb->last_render_ns) < throttle_ns) {
		return;
	}
	pb->last_render_ns = now;

	double pct = pb->total > 0 ? (double)current / (double)pb->total : 1.0;
	if (pct < 0.0) {
		pct = 0.0;
	} else if (pct > 1.0) {
		pct = 1.0;
	}

	uint32_t width = pb->width > 0 ? pb->width : 36U;
	uint32_t num_eighth_blocks = (uint32_t)(pct * (double)(width * 8U));
	uint32_t num_full_blocks = num_eighth_blocks / 8U;

	fputs("\r\033[K\342\224\244", stderr);
	for (uint32_t i = 0; i < width; ++i) {
		if (i < num_full_blocks) {
			fputs("\u2588", stderr);
		} else if (i == num_full_blocks) {
			switch (num_eighth_blocks % 8U) {
			case 0:
				fputs(" ", stderr);
				break;
			case 1:
				fputs("\u258F", stderr);
				break;
			case 2:
				fputs("\u258E", stderr);
				break;
			case 3:
				fputs("\u258D", stderr);
				break;
			case 4:
				fputs("\u258C", stderr);
				break;
			case 5:
				fputs("\u258B", stderr);
				break;
			case 6:
				fputs("\u258A", stderr);
				break;
			case 7:
				fputs("\u2589", stderr);
				break;
			}
		} else {
			fputs(" ", stderr);
		}
	}

	double elapsed_s = (double)(now - pb->start_ns) / 1e9;
	fprintf(stderr, "\342\224\234 %5.1f%% [%zu/%zu] %.2fs", pct * 100.0, current, pb->total,
		elapsed_s);

	if (status_label != nullptr && status_label[0] != '\0') {
		if (last_ns >= 1e6) {
			fprintf(stderr, " | %s (%.2f ms)", status_label, last_ns / 1e6);
		} else if (last_ns >= 1e3) {
			fprintf(stderr, " | %s (%.2f us)", status_label, last_ns / 1e3);
		} else if (last_ns > 0.0) {
			fprintf(stderr, " | %s (%.0f ns)", status_label, last_ns);
		} else {
			fprintf(stderr, " | %s", status_label);
		}
	}

	fflush(stderr);
}

void qs_pbar_finish(QsPbar *pb, const char *summary_label)
{
	if (pb == nullptr || !pb->enabled) {
		return;
	}

	pb->last_render_ns = 0;
	qs_pbar_update(pb, pb->total, summary_label != nullptr ? summary_label : "done", 0.0);
	fputc('\n', stderr);
	fflush(stderr);
}
