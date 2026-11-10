# SPDX-License-Identifier: ISC
# SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>

from pygments.lexer import RegexLexer, words
from pygments.token import (
    Comment,
    Keyword,
    Name,
    Number,
    Operator,
    Punctuation,
    String,
    Text,
)


class QsLexer(RegexLexer):
  """Pygments Lexer for the Quicksort simulation DSL (*.qs)."""

  name = "Quicksort"
  aliases = ["qs", "quicksort"]
  filenames = ["*.qs"]

  tokens = {
      "root": [
          (r"\s+", Text),
          (r"#.*", Comment.Single),
          (r"//.*", Comment.Single),
          (r"/\*[\s\S]*?\*/", Comment.Multiline),
          (
              words(
                  ("host", "let", "dataset", "variant", "benchmark"),
                  prefix=r"\b",
                  suffix=r"\b",
              ),
              Keyword.Declaration,
          ),
          (
              words(
                  (
                      "random",
                      "sorted",
                      "reverse",
                      "repeated",
                      "constant",
                      "organ_pipe",
                      "sawtooth",
                      "adversarial_med3",
                      "partial_sort",
                  ),
                  prefix=r"\b",
                  suffix=r"\b",
              ),
              Name.Builtin,
          ),
          (words(("true", "false"), prefix=r"\b", suffix=r"\b"), Keyword.Constant),
          (
              words(
                  (
                      "hoare",
                      "lomuto",
                      "three_way",
                      "pdq",
                      "first",
                      "last",
                      "middle",
                      "median3",
                      "median_of_three",
                      "ninther",
                      "none",
                      "insertion",
                      "binary_insertion",
                      "shell",
                      "heapsort",
                      "recursive",
                      "tail_call",
                      "iterative",
                      "parallel",
                      "asc",
                      "ascending",
                      "desc",
                      "descending",
                      "monotonic_ns",
                      "comparisons",
                      "swaps",
                      "moves",
                      "cycles",
                      "instructions",
                      "branches",
                      "branch_misses",
                      "l1d_misses",
                      "llc_misses",
                      "all",
                      "no_unroll",
                      "vectorize",
                      "no_vectorize",
                  ),
                  prefix=r"\b",
                  suffix=r"\b",
              ),
              Name.Constant,
          ),
          (
              r"\b(unroll\(\d+\)|unroll\(disable\)|vectorize\((enable|disable)\))\b",
              Name.Constant,
          ),
          (
              words(
                  (
                      "pin_cpus",
                      "cold_cache",
                      "repetitions",
                      "warmup",
                      "enable_pmu",
                      "sizes",
                      "expr",
                      "partition",
                      "pivot",
                      "cutoff",
                      "small_sort",
                      "execution",
                      "threads",
                      "cflags",
                      "pragmas",
                      "order",
                      "parallel_threshold",
                      "max_depth",
                      "datasets",
                      "variants",
                      "metrics",
                      "output_csv",
                      "output_latex",
                      "output_asm_dir",
                      "emit_asm",
                      "min",
                      "max",
                      "seed",
                      "step",
                      "unique",
                      "value",
                      "period",
                      "factor",
                  ),
                  prefix=r"\b",
                  suffix=r"\b",
              ),
              Name.Attribute,
          ),
          (r'"(\\.|[^"\\])*"', String),
          (r"-?\d+\.\d+([eE][-+]?\d+)?", Number.Float),
          (r"-?\d+", Number.Integer),
          (r"(\+\+|\*\*|\|>|\.\.|\^|~|=)", Operator),
          (r"[{}\[\](),;]", Punctuation),
          (r"[A-Za-z_][A-Za-z0-9_-]*", Name),
      ]
  }
