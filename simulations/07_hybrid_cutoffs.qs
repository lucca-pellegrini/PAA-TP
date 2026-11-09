# Compare hybrid small-subarray fallback algorithms: none, insertion, binary_insertion, shell, heapsort
host {
	pin_cpus = [0];
	cold_cache = false;
	repetitions = 3;
	warmup = 1;
}

dataset d_mix {
	sizes = [1000, 4000];
	expr = random(n, min=0, max=50000, seed=707);
}

variant ss_none      { partition = hoare; pivot = median3; cutoff = 0;  small_sort = none; }
variant ss_insertion { partition = hoare; pivot = median3; cutoff = 20; small_sort = insertion; }
variant ss_bin_ins   { partition = hoare; pivot = median3; cutoff = 20; small_sort = binary_insertion; }
variant ss_shell     { partition = hoare; pivot = median3; cutoff = 32; small_sort = shell; }
variant ss_heapsort  { partition = hoare; pivot = median3; cutoff = 24; small_sort = heapsort; }

benchmark small_sort_comparison {
	datasets = [d_mix];
	variants = [ss_none, ss_insertion, ss_bin_ins, ss_shell, ss_heapsort];
	metrics = [monotonic_ns, comparisons, swaps, moves];
}
