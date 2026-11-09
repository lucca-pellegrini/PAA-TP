# Hardware performance counter group telemetry via perf_event_open
host {
	pin_cpus = [0];
	cold_cache = false;
	repetitions = 3;
	warmup = 1;
}

dataset d_branch_heavy {
	sizes = [2000, 8000];
	expr = random(n, min=0, max=100000, seed=1212);
}

dataset d_branch_predictable {
	sizes = [2000, 8000];
	expr = sorted(n, order=asc);
}

variant v_hoare { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; }
variant v_pdq   { partition = pdq;   pivot = ninther; cutoff = 16; small_sort = insertion; }

benchmark pmu_telemetry {
	datasets = [d_branch_heavy, d_branch_predictable];
	variants = [v_hoare, v_pdq];
	metrics = [monotonic_ns, cycles, instructions, branches, branch_misses, l1d_misses, llc_misses];
}
