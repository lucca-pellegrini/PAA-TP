# Compare execution modes: recursive, tail_call (Sedgewick), iterative (explicit heap stack)
host {
	pin_cpus = [0];
	cold_cache = false;
	repetitions = 3;
	warmup = 1;
}

dataset d_rand {
	sizes = [1000, 5000];
	expr = random(n, min=0, max=100000, seed=808);
}

variant exec_rec  { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; execution = recursive; }
variant exec_tail { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; execution = tail_call; }
variant exec_iter { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; execution = iterative; }

benchmark execution_modes {
	datasets = [d_rand];
	variants = [exec_rec, exec_tail, exec_iter];
	metrics = [monotonic_ns, comparisons, swaps, l1d_misses];
}
