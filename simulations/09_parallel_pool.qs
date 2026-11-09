# Parallel Quicksort on C23 <threads.h> thread pool with CPU pinning
host {
	pin_cpus = [0, 1, 2, 3, 4, 5];
	cold_cache = false;
	repetitions = 3;
	warmup = 1;
}

dataset d_large {
	sizes = [10000, 40000];
	expr = random(n, min=0, max=1000000, seed=909);
}

variant par_1t { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; execution = tail_call; threads = 1; }
variant par_2t { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; execution = parallel;  threads = 2; }
variant par_4t { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; execution = parallel;  threads = 4; }
variant par_6t { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; execution = parallel;  threads = 6; }

benchmark parallel_scaling {
	datasets = [d_large];
	variants = [par_1t, par_2t, par_4t, par_6t];
	metrics = [monotonic_ns, comparisons, swaps];
}
