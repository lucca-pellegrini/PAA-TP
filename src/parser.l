/*
 * Reentrant Flex scanner for the *.qs simulation DSL.
 *
 * Identifiers are normalized (case folded, '-'/'_' unified) before being
 * classified, so keywords and names are case-insensitive.  Every token
 * carries a precise line/column range in yylloc.
 */

%option reentrant bison-bridge bison-locations noyywrap nounput noinput
%option never-interactive

%{
#include "parser.tab.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void qs_ident_normalize(char *s);

/* Line/column tracking.  `yyextra` points at the QsLexState installed by
 * src/parser.c; it is shared with the parser through parser.tab.h. */
#define YY_USER_ACTION                                                         \
	do {                                                                   \
		QsLexState *_st = (QsLexState *)yyextra;                       \
		int _nl = 0;                                                   \
		int _last = 1;                                                 \
		for (int _i = 0; _i < (int)yyleng; _i++) {                     \
			if (yytext[_i] == '\n') {                              \
				_nl++;                                         \
				_last = 1;                                     \
			} else {                                               \
				_last++;                                       \
			}                                                      \
		}                                                              \
		if (_st) {                                                     \
			yylloc->first_line = _st->line;                        \
			yylloc->first_column = _st->col;                       \
			if (_nl == 0) {                                        \
				yylloc->last_line = _st->line;                 \
				yylloc->last_column = _st->col + (int)yyleng - 1; \
				_st->col += (int)yyleng;                       \
			} else {                                               \
				yylloc->last_line = _st->line + _nl;           \
				yylloc->last_column = _last - 1;               \
				_st->line += _nl;                              \
				_st->col = _last;                              \
			}                                                      \
		}                                                              \
	} while (0);
%}

DIGIT		[0-9]
INT_LIT		-?{DIGIT}+
FLOAT_LIT	-?{DIGIT}+\.{DIGIT}+([eE][-+]?{DIGIT}+)?
ID		[A-Za-z_][A-Za-z0-9_]*

%%

[ \t\r\n]+		{ /* whitespace (newlines tracked above) */ }
#[^\n]*			{ /* shell-style comment */ }
"//"[^\n]*		{ /* C++-style comment */ }
"/*"([^*]|\*+[^*/])*\*+"/"	{ /* C-style comment, possibly multi-line */ }

"++"			{ return T_CONCAT; }
"**"			{ return T_INTERLEAVE; }
"|>"			{ return T_PIPE; }
".."			{ return T_DOTDOT; }

"^"			{ return T_CARET; }
"~"			{ return T_TILDE; }
"="			{ return T_ASSIGN; }
";"			{ return T_SEMI; }
","			{ return T_COMMA; }
"{"			{ return T_LBRACE; }
"}"			{ return T_RBRACE; }
"["			{ return T_LBRACKET; }
"]"			{ return T_RBRACKET; }
"("			{ return T_LPAREN; }
")"			{ return T_RPAREN; }

{FLOAT_LIT}		{
	yylval->val.kind = QSV_FLOAT;
	yylval->val.f64 = strtod(yytext, NULL);
	return T_FLOAT;
}

{INT_LIT}		{
	yylval->val.kind = QSV_INT;
	yylval->val.i64 = (int64_t)strtoll(yytext, NULL, 10);
	return T_INT;
}

\"([^"\\\n]|\\.)*\"	{
	size_t j = 0;
	const size_t n = (size_t)yyleng;

	for (size_t i = 1; i + 1 < n && j + 1 < sizeof(yylval->val.str); i++) {
		char c = yytext[i];
		if (c == '\\' && i + 2 < n) {
			char e = yytext[++i];
			switch (e) {
			case 'n': c = '\n'; break;
			case 't': c = '\t'; break;
			case 'r': c = '\r'; break;
			case '0': c = '\0'; break;
			default: c = e; break;
			}
		}
		yylval->val.str[j++] = c;
	}
	yylval->val.str[j] = '\0';
	yylval->val.kind = QSV_STRING;
	return T_STRING;
}

{ID}			{
	char norm[256];
	size_t n = strlen(yytext);

	if (n >= sizeof(norm))
		n = sizeof(norm) - 1;
	memcpy(norm, yytext, n);
	norm[n] = '\0';
	qs_ident_normalize(norm);

	if (strcmp(norm, "host") == 0)
		return T_HOST;
	if (strcmp(norm, "let") == 0)
		return T_LET;
	if (strcmp(norm, "dataset") == 0)
		return T_DATASET;
	if (strcmp(norm, "variant") == 0)
		return T_VARIANT;
	if (strcmp(norm, "benchmark") == 0)
		return T_BENCHMARK;
	if (strcmp(norm, "true") == 0)
		return T_TRUE;
	if (strcmp(norm, "false") == 0)
		return T_FALSE;

	snprintf(yylval->val.str, sizeof(yylval->val.str), "%s", norm);
	yylval->val.kind = QSV_INT;
	if (strcmp(norm, "random") == 0) {
		yylval->val.i64 = QS_VEXPR_RANDOM;
		return T_GENFN;
	}
	if (strcmp(norm, "sorted") == 0) {
		yylval->val.i64 = QS_VEXPR_SORTED;
		return T_GENFN;
	}
	if (strcmp(norm, "reverse") == 0) {
		yylval->val.i64 = QS_VEXPR_REVERSE;
		return T_GENFN;
	}
	if (strcmp(norm, "repeated") == 0) {
		yylval->val.i64 = QS_VEXPR_REPEATED;
		return T_GENFN;
	}
	if (strcmp(norm, "constant") == 0) {
		yylval->val.i64 = QS_VEXPR_CONSTANT;
		return T_GENFN;
	}
	if (strcmp(norm, "organ_pipe") == 0) {
		yylval->val.i64 = QS_VEXPR_ORGAN_PIPE;
		return T_GENFN;
	}
	if (strcmp(norm, "sawtooth") == 0) {
		yylval->val.i64 = QS_VEXPR_SAWTOOTH;
		return T_GENFN;
	}
	if (strcmp(norm, "adversarial_med3") == 0) {
		yylval->val.i64 = QS_VEXPR_ADVERSARIAL_MED3;
		return T_GENFN;
	}
	if (strcmp(norm, "partial_sort") == 0) {
		yylval->val.i64 = 0;
		return T_PARTIAL;
	}

	snprintf(yylval->val.str, sizeof(yylval->val.str), "%s", norm);
	yylval->val.kind = QSV_IDENT;
	return T_IDENT;
}

\"			{
	QsLexState *st = (QsLexState *)yyextra;

	if (st && st->ctx)
		qs_parse_error(st->ctx, *yylloc, "unterminated string literal");
	return YYerror;
}

.			{
	QsLexState *st = (QsLexState *)yyextra;

	if (st && st->ctx)
		qs_parse_error(st->ctx, *yylloc, "unexpected character '%c'",
			       (unsigned char)yytext[0]);
	return YYerror;
}

%%
