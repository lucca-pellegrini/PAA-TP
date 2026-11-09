# Quicksort Simulation Suite (`simulations/*.qs`)

This directory contains the declarative simulation configurations parsed by the
reentrant Flex + Bison DSL (`src/parser.l`, `src/parser.y`).

## Exploratory & Coverage / PGO Training Suites (`01_*.qs` – `14_*.qs`)

Used by `make cov` and `make pgo` to exercise every parser production, vector
algebra combinator, partitioning scheme, pivot selector, small-subarray fallback,
execution mode, hardware performance counter, and dynamic `.so` JIT flag:

- `01_minimal.qs`: Smoke test with default Hoare + Median-of-Three configuration.
- `02_presets_basic.qs`: Exercises `random`, `sorted`, `reverse`, `repeated`, `constant`, `organ_pipe`, `sawtooth`, and `adversarial_med3`.
- `03_partial_sort.qs`: Sweeps the continuous `partial_sort(factor=...)` pipeline from `0.0` to `1.0` in ascending and descending order.
- `04_vec_algebra.qs`: Exercises `let` bindings, concatenation (`++`), interleaving (`**`), blending (`^`), reversal (`~`), and slice indexing (`[lo..hi]`).
- `05_pivots.qs`: Compares `first`, `last`, `middle`, `random`, `median3`, and `ninther`.
- `06_partitions.qs`: Compares `hoare`, `lomuto`, `three_way`, and `pdq`.
- `07_hybrid_cutoffs.qs`: Compares `none`, `insertion`, `binary_insertion`, `shell`, and `heapsort` base cases.
- `08_execution_modes.qs`: Compares `recursive`, `tail_call` (Sedgewick), and `iterative` (heap stack).
- `09_parallel_pool.qs`: Exercises the C23 `<threads.h>` thread pool across 1, 2, 4, and 6 pinned cores.
- `10_adversarial.qs`: Tests quadratic inputs and recursion-depth guards (`max_depth`).
- `11_cold_vs_warm.qs`: Exercises the pure-C23 $2 \times \text{LLC}$ cache-thrashing buffer.
- `12_pmu_telemetry.qs`: Exercises `perf_event_open` hardware and cache counters.
- `13_jit_flags.qs`: Exercises on-demand `.so` compilation across `-O1`, `-O2`, and `-O3 -march=native`.
- `14_jit_pragmas.qs`: Exercises loop unrolling (`unroll(N)`, e.g. `unroll(4)`) and vectorization `#pragma` flags with `.s` assembly output.

## Canonical Manuscript Suites

Executed by `make report` to populate `report/data/*.csv`:

- `calibration_m.qs`: Sweeps $M \in \{0, 4, 8, 10, 12, 16, 20, 24, 30, 40, 50, 64\}$ on an independent calibration dataset.
- `tp_official.qs`: Official specification benchmark comparing Traditional, Hybrid, and Hybrid + Median-of-Three across all mandatory workloads and sizes.
- `extensions_pdq.qs`: Extended study of Bentley-McIlroy 3-Way, Or Peters PDQSort, Tukey's Ninther, Iterative stack, and C23 Parallel Quicksort.
- `jit_assembly.qs`: Compiler optimization level, loop `#pragma`, and generated x86-64 assembly study.
