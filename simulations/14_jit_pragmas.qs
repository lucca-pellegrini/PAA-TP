# Dynamic JIT recompilation with loop unrolling and vectorization pragmas
host {
	pin_cpus = [0];
	cold_cache = false;
	repetitions = 3;
	warmup = 1;
}

dataset d_pragma {
	sizes = [2000, 8000];
	expr = random(n, min=0, max=100000, seed=1414);
}

variant pr_no_unroll   { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; pragmas = ["no_unroll"]; }
variant pr_unroll_4    { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; pragmas = ["unroll(4)"]; }
variant pr_vectorize   { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; pragmas = ["vectorize"]; }
variant pr_no_vec      { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; pragmas = ["no_vectorize"]; }

benchmark jit_pragma_study {
	datasets = [d_pragma];
	variants = [pr_no_unroll, pr_unroll_4, pr_vectorize, pr_no_vec];
	metrics = [monotonic_ns, cycles, instructions, branch_misses];
	emit_asm = true;
}
