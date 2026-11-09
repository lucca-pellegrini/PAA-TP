# Minimal smoke test simulation with default settings
host {
	pin_cpus = [0];
	cold_cache = false;
	repetitions = 3;
	warmup = 1;
}

dataset small_rand {
	sizes = [256, 1024];
	expr = random(n, min=0, max=10000, seed=42);
}

variant default_qs {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = tail_call;
}

benchmark smoke {
	datasets = [small_rand];
	variants = [default_qs];
	metrics = [monotonic_ns, comparisons, swaps, moves];
}
