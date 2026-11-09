/*
 * Reentrant Bison grammar for the *.qs simulation DSL.
 *
 *   program   : (host_block | let_stmt | dataset_block | variant_block
 *                | benchmark_block)*
 *   host      : host { pin_cpus=[...]; cold_cache=true; repetitions=...; ... }
 *   let       : let name = <vexpr>;
 *   dataset   : dataset name { sizes=[...]; expr=<vexpr>; }
 *   variant   : variant name { partition=...; pivot=...; ... }
 *   benchmark : benchmark name { datasets=[...]; variants=[...]; ... }
 *
 * Vector expressions compose generators with postfix slices, unary '~',
 * '^' (blend), '**' (interleave), '++' (concat) and '|> partial_sort(...)'.
 */

%define api.pure full
%define api.location.type {QS_YYLTYPE}
%define parse.error verbose
%locations
%lex-param { void *scanner }
%parse-param { void *scanner } { QsParseContext *ctx }

%code requires {
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "parser.h"
#include "parser_internal.h"

typedef struct QS_YYLTYPE {
	int first_line;
	int first_column;
	int last_line;
	int last_column;
} QS_YYLTYPE;

enum QsvKind {
	QSV_NONE = 0,
	QSV_INT,
	QSV_FLOAT,
	QSV_BOOL,
	QSV_STRING,
	QSV_IDENT,
	QSV_INT_LIST,
	QSV_IDENT_LIST,
	QSV_STRING_LIST,
	QSV_VEXPR,
};

typedef struct QsNamedArg {
	char name[40];
	int kind;
	int64_t i64;
	double f64;
	bool b;
	char str[96];
} QsNamedArg;

typedef struct QsValue {
	int kind;
	int64_t i64;
	double f64;
	bool b;
	char str[256];
	int64_t ints[32];
	size_t n_ints;
	char list[16][64];
	size_t n_list;
	QsNamedArg args[8];
	size_t n_args;
	QsVecExpr *vexpr;
} QsValue;

typedef struct QsLexState {
	QsParseContext *ctx;
	int line;
	int col;
} QsLexState;
}

%union {
	QsValue val;
	QsSizeSpec size;
}

%token T_HOST T_LET T_DATASET T_VARIANT T_BENCHMARK T_TRUE T_FALSE
%token T_CONCAT T_INTERLEAVE T_PIPE T_DOTDOT
%token T_CARET T_TILDE T_ASSIGN T_SEMI T_COMMA
%token T_LBRACE T_RBRACE T_LBRACKET T_RBRACKET T_LPAREN T_RPAREN
%token <val> T_INT T_FLOAT T_STRING T_IDENT T_GENFN T_PARTIAL

%type <val> vexpr pipe_expr concat_expr interleave_expr blend_expr unary_expr
%type <val> postfix_expr primary_expr gen_call pipe_call gen_args pipe_args
%type <val> arg_list named_arg value scalar variant_value benchmark_value name
%type <val> int_list int_items ident_list ident_items string_list string_items
%type <size> size_arg

%code {
#include <stdio.h>
#include <stdlib.h>

int yylex(YYSTYPE *yylval_param, YYLTYPE *yylloc_param, void *scanner);
void yyerror(YYLTYPE *loc, void *scanner, QsParseContext *ctx, const char *msg);

static void
copy_str(char *dst, size_t cap, const char *src)
{
	if (cap == 0)
		return;
	snprintf(dst, cap, "%s", src ? src : "");
}

static QsValue
mk_int(int64_t v)
{
	QsValue r = { 0 };

	r.kind = QSV_INT;
	r.i64 = v;
	return r;
}

static void
list_push_int(QsValue *v, int64_t x)
{
	if (v->n_ints < sizeof(v->ints) / sizeof(v->ints[0]))
		v->ints[v->n_ints++] = x;
}

static void
list_push_str(QsValue *v, const char *s)
{
	if (v->n_list < sizeof(v->list) / sizeof(v->list[0]))
		copy_str(v->list[v->n_list++], sizeof(v->list[0]), s);
}

static int64_t
arg_i64(const QsNamedArg *a, int64_t dflt)
{
	if (a->kind == QSV_INT)
		return a->i64;
	if (a->kind == QSV_FLOAT)
		return (int64_t)a->f64;
	if (a->kind == QSV_BOOL)
		return a->b ? 1 : 0;
	return dflt;
}

static double
arg_f64(const QsNamedArg *a, double dflt)
{
	if (a->kind == QSV_FLOAT)
		return a->f64;
	if (a->kind == QSV_INT)
		return (double)a->i64;
	return dflt;
}

static bool
arg_bool(const QsNamedArg *a, bool dflt)
{
	if (a->kind == QSV_BOOL)
		return a->b;
	if (a->kind == QSV_INT)
		return a->i64 != 0;
	return dflt;
}

static QsOrder
parse_order(const char *s, QsOrder dflt)
{
	if (strcmp(s, "asc") == 0 || strcmp(s, "ascending") == 0)
		return QS_ORDER_ASC;
	if (strcmp(s, "desc") == 0 || strcmp(s, "descending") == 0)
		return QS_ORDER_DESC;
	return dflt;
}

static void
gen_defaults(QsVecExpr *e)
{
	e->min_val = 0;
	e->max_val = 1000000;
	e->step = 1;
	e->value = 0;
	e->unique_count = 10;
	e->period = 16;
	e->factor = 0.5;
	e->order = QS_ORDER_ASC;
	e->seed = 42;
	e->has_seed = false;
}

static void
gen_apply_args(QsParseContext *ctx, QsVecExpr *e, const QsValue *args, QS_YYLTYPE loc)
{
	for (size_t i = 0; i < args->n_args; i++) {
		const QsNamedArg *a = &args->args[i];

		if (e->kind == QS_VEXPR_RANDOM) {
			if (strcmp(a->name, "min") == 0)
				e->min_val = (int)arg_i64(a, e->min_val);
			else if (strcmp(a->name, "max") == 0)
				e->max_val = (int)arg_i64(a, e->max_val);
			else if (strcmp(a->name, "seed") == 0) {
				e->seed = (uint64_t)arg_i64(a, (int64_t)e->seed);
				e->has_seed = true;
			} else
				qs_parse_warning(ctx, loc, "unknown random() argument '%s'", a->name);
		} else if (e->kind == QS_VEXPR_SORTED) {
			if (strcmp(a->name, "order") == 0)
				e->order = parse_order(a->str, e->order);
			else if (strcmp(a->name, "step") == 0)
				e->step = (int)arg_i64(a, e->step);
			else
				qs_parse_warning(ctx, loc, "unknown sorted() argument '%s'", a->name);
		} else if (e->kind == QS_VEXPR_REVERSE) {
			if (strcmp(a->name, "step") == 0)
				e->step = (int)arg_i64(a, e->step);
			else
				qs_parse_warning(ctx, loc, "unknown reverse() argument '%s'", a->name);
		} else if (e->kind == QS_VEXPR_REPEATED) {
			if (strcmp(a->name, "unique") == 0)
				e->unique_count = (size_t)arg_i64(a, (int64_t)e->unique_count);
			else if (strcmp(a->name, "seed") == 0) {
				e->seed = (uint64_t)arg_i64(a, (int64_t)e->seed);
				e->has_seed = true;
			} else
				qs_parse_warning(ctx, loc, "unknown repeated() argument '%s'", a->name);
		} else if (e->kind == QS_VEXPR_CONSTANT) {
			if (strcmp(a->name, "value") == 0)
				e->value = (int)arg_i64(a, e->value);
			else
				qs_parse_warning(ctx, loc,
						 "unknown constant() argument '%s'", a->name);
		} else if (e->kind == QS_VEXPR_SAWTOOTH) {
			if (strcmp(a->name, "period") == 0)
				e->period = (size_t)arg_i64(a, (int64_t)e->period);
			else
				qs_parse_warning(ctx, loc, "unknown sawtooth() argument '%s'", a->name);
		} else {
			qs_parse_warning(ctx, loc, "generator does not accept argument '%s'",
					 a->name);
		}
	}
}

static void
partial_apply_args(QsParseContext *ctx, QsVecExpr *e, const QsValue *args,
		   QS_YYLTYPE loc)
{
	e->factor = 0.5;
	e->order = QS_ORDER_ASC;
	e->seed = 42;
	e->has_seed = false;

	for (size_t i = 0; i < args->n_args; i++) {
		const QsNamedArg *a = &args->args[i];

		if (strcmp(a->name, "factor") == 0)
			e->factor = arg_f64(a, e->factor);
		else if (strcmp(a->name, "order") == 0)
			e->order = parse_order(a->str, e->order);
		else if (strcmp(a->name, "seed") == 0) {
			e->seed = (uint64_t)arg_i64(a, (int64_t)e->seed);
			e->has_seed = true;
		} else
			qs_parse_warning(ctx, loc, "unknown partial_sort() argument '%s'",
					 a->name);
	}
}

static void
let_add(QsParseContext *ctx, const QsValue *name, QsVecExpr *expr, QS_YYLTYPE loc)
{
	QsSimPlan *plan = ctx->plan;

	if (!expr)
		return;
	if (plan->num_bindings >= sizeof(plan->bindings) / sizeof(plan->bindings[0])) {
		qs_parse_error(ctx, loc, "too many let bindings (max %zu)",
			       sizeof(plan->bindings) / sizeof(plan->bindings[0]));
		qs_vexpr_free(expr);
		return;
	}
	for (size_t i = 0; i < plan->num_bindings; i++) {
		if (strcmp(plan->bindings[i].name, name->str) == 0) {
			qs_parse_warning(ctx, loc, "duplicate let binding '%s'", name->str);
			break;
		}
	}
	QsLetBinding *b = &plan->bindings[plan->num_bindings++];

	copy_str(b->name, sizeof(b->name), name->str);
	b->expr = expr;
}

static bool
dataset_begin(QsParseContext *ctx, const QsValue *name, QS_YYLTYPE loc)
{
	QsSimPlan *plan = ctx->plan;

	if (plan->num_datasets >= sizeof(plan->datasets) / sizeof(plan->datasets[0])) {
		qs_parse_error(ctx, loc, "too many datasets (max %zu)",
			       sizeof(plan->datasets) / sizeof(plan->datasets[0]));
		return false;
	}
	QsDatasetSpec *d = &plan->datasets[plan->num_datasets++];

	memset(d, 0, sizeof(*d));
	copy_str(d->name, sizeof(d->name), name->str);
	return true;
}

static void
dataset_sizes(QsParseContext *ctx, const QsValue *vals, QS_YYLTYPE loc)
{
	QsDatasetSpec *d = &ctx->plan->datasets[ctx->plan->num_datasets - 1];

	d->num_sizes = 0;
	for (size_t i = 0; i < vals->n_ints; i++) {
		if (vals->ints[i] < 0) {
			qs_parse_error(ctx, loc, "dataset size must be non-negative");
			continue;
		}
		if (d->num_sizes < sizeof(d->sizes) / sizeof(d->sizes[0]))
			d->sizes[d->num_sizes++] = (size_t)vals->ints[i];
	}
}

static void
dataset_expr(QsParseContext *ctx, QsVecExpr *expr)
{
	QsDatasetSpec *d = &ctx->plan->datasets[ctx->plan->num_datasets - 1];

	qs_vexpr_free(d->expr);
	d->expr = expr;
}

static bool
variant_begin(QsParseContext *ctx, const QsValue *name, QS_YYLTYPE loc)
{
	QsSimPlan *plan = ctx->plan;

	if (plan->num_variants >= sizeof(plan->variants) / sizeof(plan->variants[0])) {
		qs_parse_error(ctx, loc, "too many variants (max %zu)",
			       sizeof(plan->variants) / sizeof(plan->variants[0]));
		return false;
	}
	QsVariantSpec *v = &plan->variants[plan->num_variants++];

	memset(v, 0, sizeof(*v));
	copy_str(v->name, sizeof(v->name), name->str);
	v->cfg = qs_config_default();
	v->cfg.order = QS_ORDER_ASC;
	v->jit = qs_jit_options_default();
	v->jit.cflags = v->cflags_buf;
	v->jit.cc = v->cc_buf;
	return true;
}

static QsPartition
parse_partition(const char *s, bool *ok)
{
	if (strcmp(s, "hoare") == 0)
		return QS_PART_HOARE;
	if (strcmp(s, "lomuto") == 0)
		return QS_PART_LOMUTO;
	if (strcmp(s, "three_way") == 0)
		return QS_PART_THREE_WAY;
	if (strcmp(s, "pdq") == 0)
		return QS_PART_PDQ;
	*ok = false;
	return QS_PART_HOARE;
}

static QsPivot
parse_pivot(const char *s, bool *ok)
{
	if (strcmp(s, "first") == 0)
		return QS_PIVOT_FIRST;
	if (strcmp(s, "last") == 0)
		return QS_PIVOT_LAST;
	if (strcmp(s, "middle") == 0)
		return QS_PIVOT_MIDDLE;
	if (strcmp(s, "random") == 0)
		return QS_PIVOT_RANDOM;
	if (strcmp(s, "median3") == 0 || strcmp(s, "median_of_three") == 0)
		return QS_PIVOT_MEDIAN3;
	if (strcmp(s, "ninther") == 0)
		return QS_PIVOT_NINTHER;
	*ok = false;
	return QS_PIVOT_MEDIAN3;
}

static QsSmallSort
parse_small_sort(const char *s, bool *ok)
{
	if (strcmp(s, "none") == 0)
		return QS_SMALL_NONE;
	if (strcmp(s, "insertion") == 0)
		return QS_SMALL_INSERTION;
	if (strcmp(s, "binary_insertion") == 0)
		return QS_SMALL_BINARY_INSERTION;
	if (strcmp(s, "shell") == 0)
		return QS_SMALL_SHELL;
	if (strcmp(s, "heapsort") == 0)
		return QS_SMALL_HEAPSORT;
	*ok = false;
	return QS_SMALL_INSERTION;
}

static QsExecMode
parse_exec(const char *s, bool *ok)
{
	if (strcmp(s, "recursive") == 0)
		return QS_EXEC_RECURSIVE;
	if (strcmp(s, "tail_call") == 0)
		return QS_EXEC_TAIL_CALL;
	if (strcmp(s, "iterative") == 0)
		return QS_EXEC_ITERATIVE;
	if (strcmp(s, "parallel") == 0)
		return QS_EXEC_PARALLEL;
	*ok = false;
	return QS_EXEC_RECURSIVE;
}

static void
variant_pragmas(QsParseContext *ctx, const QsValue *vals, QS_YYLTYPE loc)
{
	QsVariantSpec *v = &ctx->plan->variants[ctx->plan->num_variants - 1];

	for (size_t i = 0; i < vals->n_list; i++) {
		const char *s = vals->list[i];

		if (strcmp(s, "unroll_full") == 0)
			v->jit.pragma_unroll_full = true;
		else if (strcmp(s, "no_unroll") == 0)
			v->jit.pragma_no_unroll = true;
		else if (strcmp(s, "vectorize") == 0)
			v->jit.pragma_vectorize = true;
		else if (strcmp(s, "no_vectorize") == 0)
			v->jit.pragma_no_vectorize = true;
		else
			qs_parse_warning(ctx, loc, "unknown pragma '%s'", s);
	}
}

static void
variant_item(QsParseContext *ctx, const QsValue *key, const QsValue *val,
	     QS_YYLTYPE loc)
{
	QsVariantSpec *v = &ctx->plan->variants[ctx->plan->num_variants - 1];
	const char *k = key->str;
	bool ok = true;

	if (strcmp(k, "partition") == 0) {
		v->cfg.partition = parse_partition(val->str, &ok);
	} else if (strcmp(k, "pivot") == 0) {
		v->cfg.pivot = parse_pivot(val->str, &ok);
	} else if (strcmp(k, "cutoff") == 0) {
		v->cfg.cutoff = (size_t)arg_i64(&(QsNamedArg){ .kind = val->kind,
							       .i64 = val->i64,
							       .f64 = val->f64,
							       .b = val->b },
						(int64_t)v->cfg.cutoff);
	} else if (strcmp(k, "small_sort") == 0) {
		v->cfg.small_sort = parse_small_sort(val->str, &ok);
	} else if (strcmp(k, "execution") == 0) {
		v->cfg.exec_mode = parse_exec(val->str, &ok);
	} else if (strcmp(k, "threads") == 0) {
		/* QsConfig has no dedicated thread-count field in the current
		 * header; keep it in parallel_threshold so it is not lost.
		 * shortcut: store thread count in parallel_threshold, upgrade
		 * when QsConfig grows an explicit threads member. */
		v->cfg.parallel_threshold = (size_t)arg_i64(
			&(QsNamedArg){ .kind = val->kind, .i64 = val->i64 }, 1);
	} else if (strcmp(k, "max_depth") == 0) {
		v->cfg.max_depth = (size_t)arg_i64(
			&(QsNamedArg){ .kind = val->kind, .i64 = val->i64 },
			(int64_t)v->cfg.max_depth);
	} else if (strcmp(k, "cflags") == 0) {
		copy_str(v->cflags_buf, sizeof(v->cflags_buf), val->str);
		v->jit.cflags = v->cflags_buf;
	} else if (strcmp(k, "cc") == 0) {
		copy_str(v->cc_buf, sizeof(v->cc_buf), val->str);
		v->jit.cc = v->cc_buf;
	} else if (strcmp(k, "pragmas") == 0) {
		variant_pragmas(ctx, val, loc);
	} else if (strcmp(k, "emit_asm") == 0) {
		v->jit.emit_asm = val->b;
	} else if (strcmp(k, "force_recompile") == 0) {
		v->jit.force_recompile = val->b;
	} else {
		qs_parse_warning(ctx, loc, "unknown variant option '%s'", k);
	}

	if (!ok)
		qs_parse_error(ctx, loc, "invalid value '%s' for variant option '%s'",
			       val->str, k);
}

static bool
benchmark_begin(QsParseContext *ctx, const QsValue *name, QS_YYLTYPE loc)
{
	QsSimPlan *plan = ctx->plan;

	if (plan->num_benchmarks >=
	    sizeof(plan->benchmarks) / sizeof(plan->benchmarks[0])) {
		qs_parse_error(ctx, loc, "too many benchmarks (max %zu)",
			       sizeof(plan->benchmarks) / sizeof(plan->benchmarks[0]));
		return false;
	}
	QsBenchmarkSpec *b = &plan->benchmarks[plan->num_benchmarks++];

	memset(b, 0, sizeof(*b));
	copy_str(b->name, sizeof(b->name), name->str);
	b->metrics_mask = QS_METRIC_MONOTONIC_NS | QS_METRIC_COMPARISONS;
	return true;
}

static void
benchmark_names(QsParseContext *ctx, const QsValue *vals, bool datasets,
		QS_YYLTYPE loc)
{
	QsBenchmarkSpec *b = &ctx->plan->benchmarks[ctx->plan->num_benchmarks - 1];

	(void)loc;
	if (datasets)
		b->num_datasets = 0;
	else
		b->num_variants = 0;

	for (size_t i = 0; i < vals->n_list; i++) {
		if (datasets) {
			if (b->num_datasets < sizeof(b->dataset_names) /
						      sizeof(b->dataset_names[0]))
				copy_str(b->dataset_names[b->num_datasets++],
					 sizeof(b->dataset_names[0]), vals->list[i]);
		} else {
			if (b->num_variants <
			    sizeof(b->variant_names) / sizeof(b->variant_names[0]))
				copy_str(b->variant_names[b->num_variants++],
					 sizeof(b->variant_names[0]), vals->list[i]);
		}
	}
}

static uint32_t
metric_flag(const char *s, bool *ok)
{
	if (strcmp(s, "all") == 0)
		return QS_METRIC_ALL;
	if (strcmp(s, "monotonic_ns") == 0)
		return QS_METRIC_MONOTONIC_NS;
	if (strcmp(s, "comparisons") == 0)
		return QS_METRIC_COMPARISONS;
	if (strcmp(s, "swaps") == 0)
		return QS_METRIC_SWAPS;
	if (strcmp(s, "moves") == 0)
		return QS_METRIC_MOVES;
	if (strcmp(s, "cycles") == 0)
		return QS_METRIC_CYCLES;
	if (strcmp(s, "instructions") == 0)
		return QS_METRIC_INSTRUCTIONS;
	if (strcmp(s, "branches") == 0)
		return QS_METRIC_BRANCHES;
	if (strcmp(s, "branch_misses") == 0)
		return QS_METRIC_BRANCH_MISSES;
	if (strcmp(s, "l1d_misses") == 0)
		return QS_METRIC_L1D_MISSES;
	if (strcmp(s, "llc_misses") == 0)
		return QS_METRIC_LLC_MISSES;
	*ok = false;
	return 0;
}

static void
benchmark_metrics(QsParseContext *ctx, const QsValue *vals, QS_YYLTYPE loc)
{
	QsBenchmarkSpec *b = &ctx->plan->benchmarks[ctx->plan->num_benchmarks - 1];
	uint32_t mask = 0;

	for (size_t i = 0; i < vals->n_list; i++) {
		bool ok = true;
		uint32_t f = metric_flag(vals->list[i], &ok);

		if (!ok)
			qs_parse_warning(ctx, loc, "unknown metric '%s'", vals->list[i]);
		mask |= f;
	}
	if (mask)
		b->metrics_mask = mask;
}

static void
benchmark_item(QsParseContext *ctx, const QsValue *key, const QsValue *val,
	       QS_YYLTYPE loc)
{
	QsBenchmarkSpec *b = &ctx->plan->benchmarks[ctx->plan->num_benchmarks - 1];
	const char *k = key->str;

	if (strcmp(k, "datasets") == 0) {
		benchmark_names(ctx, val, true, loc);
	} else if (strcmp(k, "variants") == 0) {
		benchmark_names(ctx, val, false, loc);
	} else if (strcmp(k, "metrics") == 0) {
		benchmark_metrics(ctx, val, loc);
	} else if (strcmp(k, "output_csv") == 0) {
		copy_str(b->output_csv, sizeof(b->output_csv), val->str);
	} else if (strcmp(k, "output_latex") == 0) {
		copy_str(b->output_latex, sizeof(b->output_latex), val->str);
	} else if (strcmp(k, "output_asm_dir") == 0) {
		copy_str(b->output_asm_dir, sizeof(b->output_asm_dir), val->str);
	} else if (strcmp(k, "emit_asm") == 0) {
		/* QsBenchmarkSpec has no emit_asm flag; a non-empty assembly
		 * directory is the closest semantic carrier. */
		/* shortcut: emit_asm -> output_asm_dir sentinel, upgrade when the
		 * header gains an explicit flag. */
		copy_str(b->output_asm_dir, sizeof(b->output_asm_dir),
			 val->b ? "build/jit" : "");
	} else if (strcmp(k, "repetitions") == 0) {
		b->repetitions = (size_t)arg_i64(
			&(QsNamedArg){ .kind = val->kind, .i64 = val->i64 }, 0);
	} else if (strcmp(k, "cold_cache") == 0) {
		b->cold_cache_override = val->b ? 1 : 0;
	} else {
		qs_parse_warning(ctx, loc, "unknown benchmark option '%s'", k);
	}
}
}

%%

program:
	%empty
	| program top_stmt opt_semi
	;

opt_semi:
	%empty
	| T_SEMI
	;

top_stmt:
	host_block
	| let_stmt
	| dataset_block
	| variant_block
	| benchmark_block
	;

/* ── host { ... } ─────────────────────────────────────────────────── */

host_block:
	T_HOST T_LBRACE host_items T_RBRACE
	;

host_items:
	%empty
	| host_items host_item
	;

host_item:
	T_IDENT T_ASSIGN value opt_semi
	{
		QsHostConfig *h = &ctx->plan->host;
		const char *k = $1.str;

		if (strcmp(k, "pin_cpus") == 0) {
			if ($3.kind != QSV_INT_LIST) {
				qs_parse_error(ctx, @3, "pin_cpus expects an integer list");
			} else {
				size_t lim = sizeof(h->pin_cpus) / sizeof(h->pin_cpus[0]);
				h->num_pin_cpus = 0;
				for (size_t i = 0; i < $3.n_ints && i < lim; i++)
					h->pin_cpus[h->num_pin_cpus++] = (int)$3.ints[i];
			}
		} else if (strcmp(k, "cold_cache") == 0) {
			h->cold_cache = $3.b;
		} else if (strcmp(k, "enable_pmu") == 0) {
			h->enable_pmu = $3.b;
		} else if (strcmp(k, "repetitions") == 0) {
			h->repetitions = (size_t)($3.i64 > 0 ? $3.i64 : 1);
		} else if (strcmp(k, "warmup") == 0) {
			h->warmup = (size_t)($3.i64 > 0 ? $3.i64 : 0);
		} else if (strcmp(k, "seed") == 0) {
			h->seed = (uint64_t)$3.i64;
		} else {
			qs_parse_warning(ctx, @1, "unknown host option '%s'", k);
		}
	}
	;

/* ── let name = <vexpr>; ─────────────────────────────────────────── */

let_stmt:
	T_LET name T_ASSIGN vexpr
	{
		let_add(ctx, &$2, $4.vexpr, @1);
	}
	;

/* ── dataset name { ... } ────────────────────────────────────────── */

dataset_block:
	T_DATASET name
	{
		if (!dataset_begin(ctx, &$2, @2))
			YYERROR;
	}
	T_LBRACE dataset_items T_RBRACE
	;

dataset_items:
	%empty
	| dataset_items dataset_item
	;

dataset_item:
	T_IDENT T_ASSIGN int_list opt_semi
	{
		if (strcmp($1.str, "sizes") == 0)
			dataset_sizes(ctx, &$3, @3);
		else
			qs_parse_warning(ctx, @1, "unknown dataset option '%s'", $1.str);
	}
	| T_IDENT T_ASSIGN vexpr opt_semi
	{
		if (strcmp($1.str, "expr") == 0)
			dataset_expr(ctx, $3.vexpr);
		else {
			qs_parse_warning(ctx, @1, "unknown dataset option '%s'", $1.str);
			qs_vexpr_free($3.vexpr);
		}
	}
	;

/* ── variant name { ... } ────────────────────────────────────────── */

variant_block:
	T_VARIANT name
	{
		if (!variant_begin(ctx, &$2, @2))
			YYERROR;
	}
	T_LBRACE variant_items T_RBRACE
	;

variant_items:
	%empty
	| variant_items variant_item
	;

variant_item:
	T_IDENT T_ASSIGN variant_value opt_semi
	{
		variant_item(ctx, &$1, &$3, @3);
	}
	;

/* ── benchmark name { ... } ──────────────────────────────────────── */

benchmark_block:
	T_BENCHMARK name
	{
		if (!benchmark_begin(ctx, &$2, @2))
			YYERROR;
	}
	T_LBRACE benchmark_items T_RBRACE
	;

benchmark_items:
	%empty
	| benchmark_items benchmark_item
	;

benchmark_item:
	T_IDENT T_ASSIGN benchmark_value opt_semi
	{
		benchmark_item(ctx, &$1, &$3, @3);
	}
	;

/* ── Values ──────────────────────────────────────────────────────── */

value:
	scalar
	| int_list
	;

variant_value:
	scalar
	| string_list
	;

benchmark_value:
	scalar
	| int_list
	| ident_list
	| string_list
	;

name:
	T_IDENT
	{
		$$ = $1;
	}
	| T_GENFN
	{
		$$ = $1;
		$$.kind = QSV_IDENT;
	}
	| T_PARTIAL
	{
		$$ = $1;
		$$.kind = QSV_IDENT;
	}
	;

scalar:
	T_INT
	{
		$$ = $1;
	}
	| T_FLOAT
	{
		$$ = $1;
	}
	| T_STRING
	{
		$$ = $1;
	}
	| name
	{
		$$ = $1;
	}
	| T_TRUE
	{
		$$ = (QsValue){ .kind = QSV_BOOL, .b = true };
	}
	| T_FALSE
	{
		$$ = (QsValue){ .kind = QSV_BOOL, .b = false };
	}
	;

int_list:
	T_LBRACKET int_items T_RBRACKET
	{
		$$ = $2;
	}
	;

int_items:
	T_INT
	{
		$$ = (QsValue){ .kind = QSV_INT_LIST };
		list_push_int(&$$, $1.i64);
	}
	| int_items T_COMMA T_INT
	{
		$$ = $1;
		list_push_int(&$$, $3.i64);
	}
	;

ident_list:
	T_LBRACKET ident_items T_RBRACKET
	{
		$$ = $2;
	}
	;

ident_items:
	name
	{
		$$ = (QsValue){ .kind = QSV_IDENT_LIST };
		list_push_str(&$$, $1.str);
	}
	| ident_items T_COMMA name
	{
		$$ = $1;
		list_push_str(&$$, $3.str);
	}
	;

string_list:
	T_LBRACKET string_items T_RBRACKET
	{
		$$ = $2;
	}
	;

string_items:
	T_STRING
	{
		$$ = (QsValue){ .kind = QSV_STRING_LIST };
		list_push_str(&$$, $1.str);
	}
	| string_items T_COMMA T_STRING
	{
		$$ = $1;
		list_push_str(&$$, $3.str);
	}
	;

/* ── Vector expressions ─────────────────────────────────────────── */

vexpr:
	pipe_expr
	;

pipe_expr:
	concat_expr
	{
		$$ = $1;
	}
	| pipe_expr T_PIPE pipe_call
	{
		$$ = $3;
		if ($$.vexpr)
			$$.vexpr->left = $1.vexpr;
		else
			qs_vexpr_free($1.vexpr);
	}
	;

concat_expr:
	interleave_expr
	{
		$$ = $1;
	}
	| concat_expr T_CONCAT interleave_expr
	{
		QsVecExpr *e = qs_vexpr_alloc(QS_VEXPR_CONCAT);

		if (!e) {
			qs_parse_error(ctx, @2, "out of memory");
			qs_vexpr_free($1.vexpr);
			qs_vexpr_free($3.vexpr);
		} else {
			e->left = $1.vexpr;
			e->right = $3.vexpr;
		}
		$$ = (QsValue){ .kind = QSV_VEXPR, .vexpr = e };
	}
	;

interleave_expr:
	blend_expr
	{
		$$ = $1;
	}
	| interleave_expr T_INTERLEAVE blend_expr
	{
		QsVecExpr *e = qs_vexpr_alloc(QS_VEXPR_INTERLEAVE);

		if (!e) {
			qs_parse_error(ctx, @2, "out of memory");
			qs_vexpr_free($1.vexpr);
			qs_vexpr_free($3.vexpr);
		} else {
			e->left = $1.vexpr;
			e->right = $3.vexpr;
		}
		$$ = (QsValue){ .kind = QSV_VEXPR, .vexpr = e };
	}
	;

blend_expr:
	unary_expr
	{
		$$ = $1;
	}
	| blend_expr T_CARET unary_expr
	{
		QsVecExpr *e = qs_vexpr_alloc(QS_VEXPR_BLEND);

		if (!e) {
			qs_parse_error(ctx, @2, "out of memory");
			qs_vexpr_free($1.vexpr);
			qs_vexpr_free($3.vexpr);
		} else {
			e->left = $1.vexpr;
			e->right = $3.vexpr;
			e->factor = 0.5;
		}
		$$ = (QsValue){ .kind = QSV_VEXPR, .vexpr = e };
	}
	;

unary_expr:
	postfix_expr
	{
		$$ = $1;
	}
	| T_TILDE unary_expr
	{
		QsVecExpr *e = qs_vexpr_alloc(QS_VEXPR_REVERSED);

		if (!e) {
			qs_parse_error(ctx, @1, "out of memory");
			qs_vexpr_free($2.vexpr);
		} else {
			e->left = $2.vexpr;
		}
		$$ = (QsValue){ .kind = QSV_VEXPR, .vexpr = e };
	}
	;

postfix_expr:
	primary_expr
	{
		$$ = $1;
	}
	| postfix_expr T_LBRACKET T_INT T_DOTDOT T_INT T_RBRACKET
	{
		QsVecExpr *e = qs_vexpr_alloc(QS_VEXPR_SLICE);

		if ($3.i64 < 0 || $5.i64 < 0)
			qs_parse_error(ctx, @3, "slice bounds must be non-negative");
		if (!e) {
			qs_parse_error(ctx, @1, "out of memory");
			qs_vexpr_free($1.vexpr);
		} else {
			e->left = $1.vexpr;
			e->slice_rel = false;
			e->slice_start = $3.i64 < 0 ? 0 : (size_t)$3.i64;
			e->slice_end = $5.i64 < 0 ? 0 : (size_t)$5.i64;
		}
		$$ = (QsValue){ .kind = QSV_VEXPR, .vexpr = e };
	}
	;

primary_expr:
	T_LPAREN vexpr T_RPAREN
	{
		$$ = $2;
	}
	| gen_call
	| T_IDENT
	{
		QsVecExpr *e = qs_vexpr_alloc(QS_VEXPR_VAR);

		if (e)
			copy_str(e->var_name, sizeof(e->var_name), $1.str);
		$$ = (QsValue){ .kind = QSV_VEXPR, .vexpr = e };
	}
	;

gen_call:
	T_GENFN T_LPAREN size_arg gen_args T_RPAREN
	{
		QsVecExpr *e = qs_vexpr_alloc((QsVecExprKind)$1.i64);

		if (e) {
			e->size = $3;
			gen_defaults(e);
			if (e->kind == QS_VEXPR_REVERSE) {
				e->order = QS_ORDER_DESC;
				e->step = 1;
			}
			gen_apply_args(ctx, e, &$4, @1);
		} else {
			qs_parse_error(ctx, @1, "out of memory");
		}
		$$ = (QsValue){ .kind = QSV_VEXPR, .vexpr = e };
	}
	;

pipe_call:
	T_PARTIAL T_LPAREN pipe_args T_RPAREN
	{
		QsVecExpr *e = qs_vexpr_alloc(QS_VEXPR_PARTIAL_SORT);

		if (e)
			partial_apply_args(ctx, e, &$3, @1);
		else
			qs_parse_error(ctx, @1, "out of memory");
		$$ = (QsValue){ .kind = QSV_VEXPR, .vexpr = e };
	}
	;

gen_args:
	%empty
	{
		$$ = (QsValue){ 0 };
	}
	| T_COMMA arg_list
	{
		$$ = $2;
	}
	;

pipe_args:
	%empty
	{
		$$ = (QsValue){ 0 };
	}
	| arg_list
	{
		$$ = $1;
	}
	;

arg_list:
	named_arg
	{
		$$ = $1;
	}
	| arg_list T_COMMA named_arg
	{
		$$ = $1;
		if ($$.n_args < sizeof($$.args) / sizeof($$.args[0]))
			$$.args[$$.n_args++] = $3.args[0];
	}
	;

named_arg:
	T_IDENT T_ASSIGN scalar
	{
		QsNamedArg a = { 0 };

		copy_str(a.name, sizeof(a.name), $1.str);
		a.kind = $3.kind;
		a.i64 = $3.i64;
		a.f64 = $3.f64;
		a.b = $3.b;
		copy_str(a.str, sizeof(a.str), $3.str);
		$$ = (QsValue){ 0 };
		$$.args[0] = a;
		$$.n_args = 1;
	}
	;

size_arg:
	T_IDENT
	{
		if (strcmp($1.str, "n") != 0)
			qs_parse_error(ctx, @1, "expected size 'n' or an integer literal");
		$$ = (QsSizeSpec){ .is_relative = true, .fixed_len = 0, .n_scale = 1.0 };
	}
	| T_INT
	{
		if ($1.i64 < 0)
			qs_parse_error(ctx, @1, "size must be non-negative");
		$$ = (QsSizeSpec){ .is_relative = false,
				   .fixed_len = $1.i64 < 0 ? 0 : (size_t)$1.i64,
				   .n_scale = 1.0 };
	}
	;

%%

void
yyerror(YYLTYPE *loc, void *scanner, QsParseContext *ctx, const char *msg)
{
	(void)scanner;
	qs_parse_error_at(ctx, loc, "%s", msg);
}
