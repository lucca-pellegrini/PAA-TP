# Canonical Report Suite 2: Mandatory TP Specification Matrix
# Compares (a) Traditional, (b) Hybrid (M=50), and (c) Hybrid + Median-of-Three (M=50)
# across (a) random, (b) sorted, (c) reverse, (d) repeated, and (e) worst_case workloads.
# Note: Traditional and Hybrid share the exact same Lomuto + Last-element pivot strategy
# so that sorted/reverse inputs induce the canonical O(n^2) worst case, while organ_pipe /
# adversarial_med3 also stress-tests Median-of-Three.
host {
	pin_cpus = [0];
	cold_cache = true;
	repetitions = 5;
	warmup = 1;
}

dataset random {
	sizes = [1000, 5000, 10000, 50000];
	expr = random(n, min=0, max=1000000, seed=42001);
}

dataset sorted {
	sizes = [1000, 5000, 10000, 50000];
	expr = sorted(n, order=asc, step=1);
}

dataset reverse {
	sizes = [1000, 5000, 10000, 50000];
	expr = reverse(n, step=1);
}

dataset repeated {
	sizes = [1000, 5000, 10000, 50000];
	expr = repeated(n, unique=10, seed=42004);
}

dataset worst_case {
	sizes = [1000, 5000, 10000, 50000];
	expr = sorted(n, order=asc, step=1);
}

dataset worst_case_med3 {
	sizes = [1000, 5000, 10000, 50000];
	expr = adversarial_med3(n);
}

variant trad {
	partition = lomuto;
	pivot = last;
	cutoff = 0;
	small_sort = none;
	execution = recursive;
	max_depth = 4096; // stack-safe limit: records depth_exceeded instead of overflowing the 8 MB stack
}

variant hybrid {
	partition = lomuto;
	pivot = last;
	cutoff = 50;
	small_sort = insertion;
	execution = recursive;
	max_depth = 4096; // stack-safe limit: records depth_exceeded instead of overflowing the 8 MB stack
}

variant hybrid_med3 {
	partition = hoare;
	pivot = median3;
	cutoff = 50;
	small_sort = insertion;
	execution = recursive;
	max_depth = 4096; // stack-safe limit: records depth_exceeded instead of overflowing the 8 MB stack
}

benchmark tp_official {
	datasets = [random, sorted, reverse, repeated, worst_case, worst_case_med3];
	variants = [trad, hybrid, hybrid_med3];
	metrics = [monotonic_ns, comparisons, swaps, moves, cycles, instructions, branches, branch_misses, l1d_misses];
	output_csv = "report/data/tp_official.csv";
}
