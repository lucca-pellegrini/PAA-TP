# Adversarial workloads and recursion depth guard verification
host {
	pin_cpus = [0];
	cold_cache = false;
	repetitions = 3;
	warmup = 0;
}

dataset killer_sorted {
	sizes = [1000, 3000];
	expr = sorted(n, order=asc);
}

dataset killer_med3 {
	sizes = [1000, 3000];
	expr = adversarial_med3(n);
}

variant naive_first_guarded {
	partition = lomuto;
	pivot = first;
	cutoff = 0;
	small_sort = none;
	execution = recursive;
	max_depth = 512;
}

variant pdq_resilient {
	partition = pdq;
	pivot = ninther;
	cutoff = 16;
	small_sort = insertion;
	execution = tail_call;
}

benchmark adversarial_defense {
	datasets = [killer_sorted, killer_med3];
	variants = [naive_first_guarded, pdq_resilient];
	metrics = [monotonic_ns, comparisons, swaps];
}
