// SPDX-License-Identifier: ISC

#pragma once
#ifndef PBAR_H
#define PBAR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
	size_t total;
	size_t current;
	uint64_t start_ns;
	uint64_t last_render_ns;
	uint32_t width;
	bool enabled;
} QsPbar;

void qs_pbar_init(QsPbar *pb, size_t total, uint32_t width, bool enabled);
void qs_pbar_update(QsPbar *pb, size_t current, const char *status_label, double last_ns);
void qs_pbar_finish(QsPbar *pb, const char *summary_label);

#endif // !PBAR_H
