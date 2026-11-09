# Canonical Report Suite 4: Dynamic JIT Compiler Flags, Loop Pragmas & Assembly Analysis
host {
	pin_cpus = [0];
	cold_cache = true;
	repetitions = 5;
	warmup = 1;
}

dataset jit_random {
	sizes = [10000, 50000, 100000];
	expr = random(n, min=0, max=1000000, seed=70001);
}

dataset jit_sorted {
	sizes = [10000, 50000, 100000];
	expr = sorted(n, order=asc);
}

variant cflags_O1 {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = tail_call;
	cflags = "-O1";
}

variant cflags_O2 {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = tail_call;
	cflags = "-O2";
}

variant cflags_O3_native {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = tail_call;
	cflags = "-O3 -march=native";
}

variant pragma_no_unroll {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = tail_call;
	cflags = "-O3 -march=native -fno-unroll-loops";
	pragmas = ["no_unroll"];
}

variant pragma_unroll_4 {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = tail_call;
	cflags = "-O3 -march=native -funroll-loops";
	pragmas = ["unroll(4)"];
}

variant pragma_no_vec {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = tail_call;
	cflags = "-O3 -march=native -fno-vectorize -fno-slp-vectorize";
	pragmas = ["no_vectorize"];
}

benchmark jit_assembly {
	datasets = [jit_random, jit_sorted];
	variants = [cflags_O1, cflags_O2, cflags_O3_native, pragma_no_unroll, pragma_unroll_4, pragma_no_vec];
	metrics = [monotonic_ns, comparisons, swaps, moves, cycles, instructions, branches, branch_misses, l1d_misses];
	output_csv = "report/data/jit_assembly.csv";
	emit_asm = true;
}
