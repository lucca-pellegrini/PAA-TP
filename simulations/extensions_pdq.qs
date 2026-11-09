# Canonical Report Suite 3: Extended Algorithmic & Microarchitectural Matrix
# Evaluates Hoare vs Lomuto vs Bentley-McIlroy 3-Way vs PDQSort, Tukey's Ninther,
# Iterative vs Tail-Call vs Recursive, Partial Sortedness, and C23 Parallel Thread Pool.
host {
	pin_cpus = [0, 1, 2, 3, 4, 5];
	cold_cache = true;
	repetitions = 5;
	warmup = 1;
}

dataset ext_random {
	sizes = [1000, 5000, 10000, 50000, 100000];
	expr = random(n, min=0, max=1000000, seed=90001);
}

dataset ext_repeated {
	sizes = [1000, 5000, 10000, 50000, 100000];
	expr = repeated(n, unique=5, seed=90002);
}

dataset ext_organ_pipe {
	sizes = [1000, 5000, 10000, 50000, 100000];
	expr = organ_pipe(n);
}

dataset ext_killer_med3 {
	sizes = [1000, 5000, 10000, 50000];
	expr = adversarial_med3(n);
}

dataset ext_partial_80 {
	sizes = [1000, 5000, 10000, 50000, 100000];
	expr = random(n, min=0, max=1000000, seed=90005) |> partial_sort(factor=0.80, order=asc, seed=90005);
}

variant hoare_med3 {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = tail_call;
}

variant hoare_iter {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = iterative;
}

variant three_way_med3 {
	partition = three_way;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = tail_call;
}

variant ninther_hybrid {
	partition = hoare;
	pivot = ninther;
	cutoff = 20;
	small_sort = insertion;
	execution = tail_call;
}

variant pdq_sort {
	partition = pdq;
	pivot = ninther;
	cutoff = 24;
	small_sort = insertion;
	execution = tail_call;
}

variant parallel_4t {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = parallel;
	threads = 4;
}

variant parallel_6t {
	partition = hoare;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
	execution = parallel;
	threads = 6;
}

benchmark extensions_pdq {
	datasets = [ext_random, ext_repeated, ext_organ_pipe, ext_killer_med3, ext_partial_80];
	variants = [hoare_med3, hoare_iter, three_way_med3, ninther_hybrid, pdq_sort, parallel_4t, parallel_6t];
	metrics = [monotonic_ns, comparisons, swaps, moves, cycles, instructions, branches, branch_misses, l1d_misses];
	output_csv = "report/data/extensions_pdq.csv";
}
