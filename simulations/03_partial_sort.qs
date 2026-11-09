# Continuous partial sortedness factor sweep (0.0 to 1.0) in asc and desc order
host {
	pin_cpus = [0];
	cold_cache = false;
	repetitions = 3;
	warmup = 1;
}

dataset ps_00 {
	sizes = [1000, 4000];
	expr = random(n, seed=11) |> partial_sort(factor=0.0, order=asc, seed=11);
}

dataset ps_25 {
	sizes = [1000, 4000];
	expr = random(n, seed=11) |> partial_sort(factor=0.25, order=asc, seed=11);
}

dataset ps_50 {
	sizes = [1000, 4000];
	expr = random(n, seed=11) |> partial_sort(factor=0.50, order=asc, seed=11);
}

dataset ps_75 {
	sizes = [1000, 4000];
	expr = random(n, seed=11) |> partial_sort(factor=0.75, order=asc, seed=11);
}

dataset ps_95 {
	sizes = [1000, 4000];
	expr = random(n, seed=11) |> partial_sort(factor=0.95, order=asc, seed=11);
}

dataset ps_100_desc {
	sizes = [1000, 4000];
	expr = random(n, seed=11) |> partial_sort(factor=1.0, order=desc, seed=11);
}

variant hoare_med3 {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
}

variant pdq_adaptive {
	partition = pdq;
	pivot = ninther;
	cutoff = 24;
	small_sort = insertion;
}

benchmark partial_sort_sweep {
	datasets = [ps_00, ps_25, ps_50, ps_75, ps_95, ps_100_desc];
	variants = [hoare_med3, pdq_adaptive];
	metrics = [monotonic_ns, comparisons, swaps, branch_misses];
}
