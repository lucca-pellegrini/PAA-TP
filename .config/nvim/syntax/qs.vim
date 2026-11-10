" SPDX-License-Identifier: ISC
" SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
" NOTE: Vim syntax definition for the Quicksort simulation DSL (*.qs)

if exists("b:current_syntax")
  finish
endif

" Block declarations
syntax keyword qsBlock host let dataset variant benchmark

" Built-in generators and transformation functions
syntax keyword qsFunction random sorted reverse repeated constant
syntax keyword qsFunction organ_pipe sawtooth adversarial_med3 partial_sort

" Boolean constants
syntax keyword qsBoolean true false

" Configuration keys
syntax keyword qsKey pin_cpus cold_cache repetitions warmup enable_pmu
syntax keyword qsKey sizes expr partition pivot cutoff small_sort execution
syntax keyword qsKey threads cflags pragmas order parallel_threshold max_depth
syntax keyword qsKey datasets variants metrics output_csv output_latex
syntax keyword qsKey output_asm_dir emit_asm min max seed step unique
syntax keyword qsKey value period factor

" Enumerations and known symbolic values
syntax keyword qsValue hoare lomuto three_way pdq
syntax keyword qsValue first last middle random median3 median_of_three ninther
syntax keyword qsValue none insertion binary_insertion shell heapsort
syntax keyword qsValue recursive tail_call iterative parallel
syntax keyword qsValue asc ascending desc descending
syntax keyword qsValue monotonic_ns comparisons swaps moves cycles
syntax keyword qsValue instructions branches branch_misses l1d_misses llc_misses all
syntax match qsValue /\v<unroll\(\d+\)>/
syntax match qsValue /\v<unroll\(disable\)>/
syntax match qsValue /\v<vectorize\((enable|disable)\)>/
syntax keyword qsValue no_unroll vectorize no_vectorize

" Numbers
syntax match qsNumber /\v<\d+>/
syntax match qsNumber /\v<\d+\.\d+([eE][-+]?\d+)?>/

" Strings
syntax region qsString start=/"/ skip=/\\"/ end=/"/

" Comments
syntax match qsComment /#.*/
syntax match qsComment /\/\/.*/
syntax region qsComment start=/\/\*/ end=/\*\//

" Operators and Delimiters
syntax match qsOperator /\v(\+\+|\*\*|\|\>|\.\.|\^|\~|\=)/
syntax match qsDelimiter /[{}()\[\],;]/

" Highlight links
highlight default link qsBlock Structure
highlight default link qsFunction Function
highlight default link qsBoolean Boolean
highlight default link qsKey Identifier
highlight default link qsValue Constant
highlight default link qsNumber Number
highlight default link qsString String
highlight default link qsComment Comment
highlight default link qsOperator Operator
highlight default link qsDelimiter Delimiter

let b:current_syntax = "qs"
