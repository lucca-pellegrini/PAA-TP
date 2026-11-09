# Compare all 4 partition schemes: hoare, lomuto, three_way, pdq
host {
	pin_cpus = [0];
	cold_cache = false;
	repetitions = 3;
	warmup = 1;
}

dataset d_rand {
	sizes = [1000, 4000];
	expr = random(n, min=0, max=100000, seed=606);
}

dataset d_dups {
	sizes = [1000, 4000];
	expr = repeated(n, unique=8, seed=606);
}

variant part_hoare     { partition = hoare;     pivot = median3; cutoff = 16; small_sort = insertion; }
variant part_lomuto    { partition = lomuto;    pivot = median3; cutoff = 16; small_sort = insertion; }
variant part_three_way { partition = three_way; pivot = median3; cutoff = 16; small_sort = insertion; }
variant part_pdq       { partition = pdq;       pivot = ninther; cutoff = 16; small_sort = insertion; }

benchmark partition_comparison {
	datasets = [d_rand, d_dups];
	variants = [part_hoare, part_lomuto, part_three_way, part_pdq];
	metrics = [monotonic_ns, comparisons, swaps, moves];
}
