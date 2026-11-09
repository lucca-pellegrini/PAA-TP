# Cold cache (2x LLC thrashing buffer) vs warm cache behaviour
host {
	pin_cpus = [0];
	cold_cache = true;
	repetitions = 3;
	warmup = 0;
}

dataset d_cache_probe {
	sizes = [2000, 10000];
	expr = random(n, min=0, max=1000000, seed=1111);
}

variant hoare_cold {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = tail_call;
}

benchmark cold_cache_study {
	datasets = [d_cache_probe];
	variants = [hoare_cold];
	metrics = [monotonic_ns, cycles, instructions, l1d_misses, llc_misses];
}
