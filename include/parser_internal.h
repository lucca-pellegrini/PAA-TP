#pragma once

#include <stdbool.h>

#include "parser.h"

typedef struct QsParseContext {
	const char *filename;
	const char *source_buf;
	QsSimPlan *plan;
	bool quiet;
	int errors;
	int warnings;
} QsParseContext;

struct QS_YYLTYPE;

void qs_parse_error_at(QsParseContext *ctx, const struct QS_YYLTYPE *loc, const char *fmt, ...)
	__attribute__((format(printf, 3, 4)));

void qs_parse_warning_at(QsParseContext *ctx, const struct QS_YYLTYPE *loc, const char *fmt, ...)
	__attribute__((format(printf, 3, 4)));

#define qs_parse_error(ctx, loc, ...) qs_parse_error_at((ctx), &(loc), __VA_ARGS__)
#define qs_parse_warning(ctx, loc, ...) qs_parse_warning_at((ctx), &(loc), __VA_ARGS__)

[[nodiscard]]
QsVecExpr *qs_vexpr_alloc(QsVecExprKind kind);
void qs_vexpr_free(QsVecExpr *expr);
