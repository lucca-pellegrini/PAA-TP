# Compare all 6 pivot strategies: first, last, middle, random, median3, ninther
host {
	pin_cpus = [0];
	cold_cache = false;
	repetitions = 3;
	warmup = 1;
}

dataset rand_vec {
	sizes = [1000, 5000];
	expr = random(n, min=0, max=100000, seed=505);
}

dataset organ_vec {
	sizes = [1000, 5000];
	expr = organ_pipe(n);
}

variant p_first   { partition = hoare; pivot = first;   cutoff = 0; small_sort = none; }
variant p_last    { partition = hoare; pivot = last;    cutoff = 0; small_sort = none; }
variant p_middle  { partition = hoare; pivot = middle;  cutoff = 0; small_sort = none; }
variant p_random  { partition = hoare; pivot = random;  cutoff = 0; small_sort = none; }
variant p_median3 { partition = hoare; pivot = median3; cutoff = 0; small_sort = none; }
variant p_ninther { partition = hoare; pivot = ninther; cutoff = 0; small_sort = none; }

benchmark pivot_comparison {
	datasets = [rand_vec, organ_vec];
	variants = [p_first, p_last, p_middle, p_random, p_median3, p_ninther];
	metrics = [monotonic_ns, comparisons, swaps];
}
