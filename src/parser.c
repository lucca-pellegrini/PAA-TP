/*
 * Driver, diagnostics, and evaluator for the *.qs simulation DSL.
 */

#include "parser.h"
#include "parser_internal.h"

#include "parser.tab.h"
#include "parser.lex.h"

#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define QS_SNIPPET_LINES 2
#define QS_MAX_LINE 512

static bool g_parser_quiet = false;
static int g_last_warning_count = 0;

/* ── Identifier normalization ─────────────────────────────────────── */

void qs_ident_normalize(char *s)
{
	if (!s)
		return;
	for (; *s; s++) {
		unsigned char c = (unsigned char)*s;

		if (c == '-' || c == '.')
			c = '_';
		*s = (char)tolower(c);
	}
}

/* ── Diagnostics ──────────────────────────────────────────────────── */

#define ANSI_RESET "\x1b[0m"
#define ANSI_BOLD "\x1b[1m"
#define ANSI_DIM "\x1b[2m"
#define ANSI_RED "\x1b[31m"
#define ANSI_YELLOW "\x1b[33m"

static bool diagnostics_enabled(const QsParseContext *ctx)
{
	const char *shut_up = getenv("__QS_PARSER_SHUT_UP");

	if (shut_up && *shut_up)
		return false;
	return ctx && !ctx->quiet;
}

static const char *line_at(const char *src, int line, size_t *out_len)
{
	if (!src || line < 1) {
		*out_len = 0;
		return "";
	}

	const char *p = src;
	for (int cur = 1; cur < line && *p; cur++) {
		const char *nl = strchr(p, '\n');

		if (!nl) {
			p += strlen(p);
			break;
		}
		p = nl + 1;
	}

	const char *end = p;
	while (*end && *end != '\n')
		end++;
	*out_len = (size_t)(end - p);
	return p;
}

static void print_snippet(const QsParseContext *ctx, const QS_YYLTYPE *loc, const char *color,
			  const char *kind, const char *msg)
{
	if (!ctx || !loc || !ctx->source_buf)
		return;

	int line = loc->first_line > 0 ? loc->first_line : 1;
	int first = line - QS_SNIPPET_LINES;
	int last = line + QS_SNIPPET_LINES;

	if (first < 1)
		first = 1;

	fprintf(stderr, "%s:%d: %s%s%s %s%s%s\n", ctx->filename ? ctx->filename : "<input>", line,
		ANSI_BOLD, color, kind, ANSI_RESET, msg, ANSI_RESET);

	for (int ln = first; ln <= last; ln++) {
		size_t len = 0;
		const char *text = line_at(ctx->source_buf, ln, &len);

		if (ln > line && *text == '\0')
			break;
		if (len > QS_MAX_LINE)
			len = QS_MAX_LINE;

		fprintf(stderr, "%s%4d |%s ", ANSI_DIM, ln, ANSI_RESET);
		if (ln == line) {
			fprintf(stderr, "%s%.*s%s\n", ANSI_BOLD, (int)len, text, ANSI_RESET);
			int col = loc->first_column > 0 ? loc->first_column : 1;

			fprintf(stderr, "%s     |%s ", ANSI_DIM, ANSI_RESET);
			for (int i = 1; i < col; i++)
				fputc(' ', stderr);
			fprintf(stderr, "%s^%s %s%s:%s %s\n", color && *color ? color : "",
				ANSI_RESET, ANSI_BOLD, kind, ANSI_RESET, msg);
		} else {
			fprintf(stderr, "%.*s\n", (int)len, text);
		}
	}
}

void qs_parse_print_error(QsParseContext *ctx, const struct QS_YYLTYPE *loc, const char *msg)
{
	if (diagnostics_enabled(ctx))
		print_snippet(ctx, loc, ANSI_RED, "error", msg);
	if (ctx)
		ctx->errors++;
}

void qs_parse_print_warning(QsParseContext *ctx, const struct QS_YYLTYPE *loc, const char *msg)
{
	if (diagnostics_enabled(ctx))
		print_snippet(ctx, loc, ANSI_YELLOW, "warning", msg);
	if (ctx)
		ctx->warnings++;
}

void qs_parse_error_at(QsParseContext *ctx, const struct QS_YYLTYPE *loc, const char *fmt, ...)
{
	char msg[QS_MAX_LINE];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(msg, sizeof(msg), fmt, ap);
	va_end(ap);

	qs_parse_print_error(ctx, loc, msg);
}

void qs_parse_warning_at(QsParseContext *ctx, const struct QS_YYLTYPE *loc, const char *fmt, ...)
{
	char msg[QS_MAX_LINE];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(msg, sizeof(msg), fmt, ap);
	va_end(ap);

	qs_parse_print_warning(ctx, loc, msg);
}

/* ── Plan lifetime ────────────────────────────────────────────────── */

void qs_sim_plan_init(QsSimPlan *plan)
{
	if (!plan)
		return;
	memset(plan, 0, sizeof(*plan));
	plan->host.repetitions = 5;
	plan->host.warmup = 1;
	plan->host.seed = 42;
}

void qs_sim_plan_destroy(QsSimPlan *plan)
{
	if (!plan)
		return;
	for (size_t i = 0; i < plan->num_bindings; i++) {
		qs_vexpr_free(plan->bindings[i].expr);
		plan->bindings[i].expr = nullptr;
	}
	for (size_t i = 0; i < plan->num_datasets; i++) {
		qs_vexpr_free(plan->datasets[i].expr);
		plan->datasets[i].expr = nullptr;
	}
	memset(plan, 0, sizeof(*plan));
}

/* ── Expression allocation / ownership ───────────────────────────── */

QsVecExpr *qs_vexpr_alloc(QsVecExprKind kind)
{
	QsVecExpr *e = calloc(1, sizeof(*e));

	if (!e)
		return nullptr;
	e->kind = kind;
	e->step = 1;
	e->period = 16;
	e->unique_count = 10;
	e->factor = 0.5;
	e->order = QS_ORDER_ASC;
	e->seed = 42;
	return e;
}

void qs_vexpr_free(QsVecExpr *expr)
{
	if (!expr)
		return;
	qs_vexpr_free(expr->left);
	qs_vexpr_free(expr->right);
	free(expr);
}

void qs_vexpr_destroy(QsVecExpr *expr)
{
	qs_vexpr_free(expr);
}

QsVecExpr *qs_vexpr_clone(const QsVecExpr *src)
{
	if (!src)
		return nullptr;

	QsVecExpr *dst = qs_vexpr_alloc(src->kind);

	if (!dst)
		return nullptr;
	*dst = *src;
	dst->left = qs_vexpr_clone(src->left);
	dst->right = qs_vexpr_clone(src->right);
	return dst;
}

/* ── Evaluation ───────────────────────────────────────────────────── */

static QsVec vec_from_ptr(QsVec *p)
{
	QsVec out = { 0 };

	if (!p)
		return out;
	out = *p;
	free(p);
	return out;
}

static size_t resolve_len(const QsSizeSpec *size, size_t target_n)
{
	if (size->is_relative) {
		double n = (double)target_n * size->n_scale;

		return n > 0.0 ? (size_t)n : 0;
	}
	return size->fixed_len;
}

static QsVec eval_expr(const QsVecExpr *e, size_t target_n, const QsSimPlan *plan,
		       uint64_t run_seed, int depth);

static QsVec eval_var(const QsVecExpr *e, size_t target_n, const QsSimPlan *plan, uint64_t run_seed,
		      int depth)
{
	if (!plan || depth > 32)
		return (QsVec){ 0 };

	for (size_t i = 0; i < plan->num_bindings; i++) {
		if (strcmp(plan->bindings[i].name, e->var_name) == 0)
			return eval_expr(plan->bindings[i].expr, target_n, plan, run_seed,
					 depth + 1);
	}
	return (QsVec){ 0 };
}

static QsVec eval_binary(const QsVecExpr *e, size_t target_n, const QsSimPlan *plan,
			 uint64_t run_seed, int depth)
{
	QsVec a = eval_expr(e->left, target_n, plan, run_seed, depth + 1);
	QsVec b = eval_expr(e->right, target_n, plan, run_seed, depth + 1);
	QsVec *r = nullptr;

	switch (e->kind) {
	case QS_VEXPR_CONCAT:
		r = qs_vec_concat(&a, &b);
		break;
	case QS_VEXPR_INTERLEAVE:
		r = qs_vec_interleave(&a, &b);
		break;
	case QS_VEXPR_BLEND:
		r = qs_vec_blend(&a, &b, e->factor, e->seed + run_seed);
		break;
	default:
		break;
	}

	free(a.data);
	free(b.data);
	return vec_from_ptr(r);
}

static QsVec eval_expr(const QsVecExpr *e, size_t target_n, const QsSimPlan *plan,
		       uint64_t run_seed, int depth)
{
	if (!e || depth > 64)
		return (QsVec){ 0 };

	size_t n = resolve_len(&e->size, target_n);
	uint64_t seed = e->has_seed ? (e->seed ^ (run_seed * 0x9E3779B97F4A7C15ULL)) :
				      (run_seed ? run_seed : e->seed);

	switch (e->kind) {
	case QS_VEXPR_RANDOM:
		return vec_from_ptr(qs_vec_preset_random(n, e->min_val, e->max_val, seed));
	case QS_VEXPR_SORTED:
		return vec_from_ptr(
			qs_vec_preset_sorted(n, e->order, e->min_val, e->step ? e->step : 1));
	case QS_VEXPR_REVERSE:
		if (e->step <= 1)
			return vec_from_ptr(qs_vec_preset_reverse(n));
		return vec_from_ptr(qs_vec_preset_sorted(n, QS_ORDER_DESC, 0, e->step));
	case QS_VEXPR_REPEATED:
		return vec_from_ptr(qs_vec_preset_repeated(n, e->unique_count, seed));
	case QS_VEXPR_CONSTANT:
		return vec_from_ptr(qs_vec_preset_constant(n, e->value));
	case QS_VEXPR_ORGAN_PIPE:
		return vec_from_ptr(qs_vec_preset_organ_pipe(n));
	case QS_VEXPR_SAWTOOTH:
		return vec_from_ptr(qs_vec_preset_sawtooth(n, e->period, e->order));
	case QS_VEXPR_ADVERSARIAL_MED3:
		return vec_from_ptr(qs_vec_preset_adversarial_med3(n));
	case QS_VEXPR_VAR:
		return eval_var(e, target_n, plan, run_seed, depth);
	case QS_VEXPR_CONCAT:
	case QS_VEXPR_INTERLEAVE:
	case QS_VEXPR_BLEND:
		return eval_binary(e, target_n, plan, run_seed, depth);
	case QS_VEXPR_REVERSED: {
		QsVec a = eval_expr(e->left, target_n, plan, run_seed, depth + 1);
		QsVec *r = qs_vec_reversed(&a);

		free(a.data);
		return vec_from_ptr(r);
	}
	case QS_VEXPR_PARTIAL_SORT: {
		QsVec a = eval_expr(e->left, target_n, plan, run_seed, depth + 1);

		(void)qs_vec_partial_sort(&a, e->factor, e->order, seed);
		return a;
	}
	case QS_VEXPR_SLICE: {
		QsVec a = eval_expr(e->left, target_n, plan, run_seed, depth + 1);
		size_t lo = e->slice_rel ? (size_t)((double)a.len * e->slice_start_ratio) :
					   e->slice_start;
		size_t hi = e->slice_rel ? (size_t)((double)a.len * e->slice_end_ratio) :
					   e->slice_end;
		QsVec *r = qs_vec_slice(&a, lo, hi);

		free(a.data);
		return vec_from_ptr(r);
	}
	default:
		break;
	}
	return (QsVec){ 0 };
}

QsVec qs_vexpr_eval(const QsVecExpr *expr, size_t target_n, const QsSimPlan *plan,
		    uint64_t run_seed)
{
	return eval_expr(expr, target_n, plan, run_seed, 0);
}

/* ── Parsing entry points ─────────────────────────────────────────── */

static bool parser_quiet(void)
{
	const char *shut_up = getenv("__QS_PARSER_SHUT_UP");

	return g_parser_quiet || (shut_up && *shut_up);
}

static int parse_buffer(const char *src, size_t len, const char *filename, QsSimPlan *plan)
{
	QsParseContext ctx = {
		.filename = filename,
		.source_buf = src,
		.plan = plan,
		.quiet = parser_quiet(),
		.errors = 0,
		.warnings = 0,
	};
	yyscan_t scanner;

	qs_sim_plan_init(plan);

	if (yylex_init(&scanner) != 0) {
		if (!ctx.quiet)
			fprintf(stderr, "error: cannot initialise scanner for '%s'\n",
				filename ? filename : "<input>");
		return -1;
	}

	QsLexState state = { .ctx = &ctx, .line = 1, .col = 1 };

	yyset_extra(&state, scanner);

	YY_BUFFER_STATE buf = yy_scan_bytes(src, (int)len, scanner);
	int rc = yyparse(scanner, &ctx);

	yy_delete_buffer(buf, scanner);
	yylex_destroy(scanner);

	g_last_warning_count = ctx.warnings;

	if (rc != 0 || ctx.errors > 0) {
		qs_sim_plan_destroy(plan);
		return -1;
	}
	return 0;
}

int qs_parse_string(const char *src, const char *virtual_filename, QsSimPlan *plan)
{
	if (!src || !plan) {
		errno = EINVAL;
		return -1;
	}
	return parse_buffer(src, strlen(src), virtual_filename ? virtual_filename : "<string>",
			    plan);
}

int qs_parse_file(const char *path, QsSimPlan *plan)
{
	if (!path || !plan) {
		errno = EINVAL;
		return -1;
	}

	FILE *f = fopen(path, "rb");
	if (!f) {
		if (!parser_quiet())
			fprintf(stderr, "error: cannot open '%s': %s\n", path, strerror(errno));
		return -1;
	}
	if (fseek(f, 0, SEEK_END) != 0) {
		fclose(f);
		return -1;
	}
	long sz = ftell(f);
	if (sz < 0) {
		fclose(f);
		return -1;
	}
	rewind(f);

	char *buf = malloc((size_t)sz + 1);
	if (!buf) {
		fclose(f);
		return -1;
	}
	size_t got = fread(buf, 1, (size_t)sz, f);
	fclose(f);
	buf[got] = '\0';

	int rc = parse_buffer(buf, got, path, plan);
	free(buf);
	return rc;
}

int qs_parse_last_warning_count(void)
{
	return g_last_warning_count;
}

void qs_parse_set_quiet(bool quiet)
{
	g_parser_quiet = quiet;
}
