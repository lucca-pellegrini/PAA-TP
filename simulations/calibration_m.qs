# Canonical Report Suite 1: Empirical Cutoff M Calibration
# Sweeps M in {0, 4, 8, 10, 12, 16, 20, 24, 30, 40, 50, 64} on an independent calibration dataset
host {
	pin_cpus = [0];
	cold_cache = true;
	repetitions = 7;
	warmup = 2;
}

dataset cal_random {
	sizes = [10000, 50000];
	expr = random(n, min=0, max=1000000, seed=202601);
}

dataset cal_partial {
	sizes = [10000, 50000];
	expr = random(n, min=0, max=1000000, seed=202602) |> partial_sort(factor=0.5, order=asc, seed=202602);
}

dataset cal_repeated {
	sizes = [10000, 50000];
	expr = repeated(n, unique=100, seed=202603);
}

variant m_00 { partition = hoare; pivot = last; cutoff = 0;  small_sort = none;      execution = recursive; }
variant m_04 { partition = hoare; pivot = last; cutoff = 4;  small_sort = insertion; execution = recursive; }
variant m_08 { partition = hoare; pivot = last; cutoff = 8;  small_sort = insertion; execution = recursive; }
variant m_10 { partition = hoare; pivot = last; cutoff = 10; small_sort = insertion; execution = recursive; }
variant m_12 { partition = hoare; pivot = last; cutoff = 12; small_sort = insertion; execution = recursive; }
variant m_16 { partition = hoare; pivot = last; cutoff = 16; small_sort = insertion; execution = recursive; }
variant m_20 { partition = hoare; pivot = last; cutoff = 20; small_sort = insertion; execution = recursive; }
variant m_24 { partition = hoare; pivot = last; cutoff = 24; small_sort = insertion; execution = recursive; }
variant m_30 { partition = hoare; pivot = last; cutoff = 30; small_sort = insertion; execution = recursive; }
variant m_40 { partition = hoare; pivot = last; cutoff = 40; small_sort = insertion; execution = recursive; }
variant m_50 { partition = hoare; pivot = last; cutoff = 50; small_sort = insertion; execution = recursive; }
variant m_64 { partition = hoare; pivot = last; cutoff = 64; small_sort = insertion; execution = recursive; }

benchmark calibration_m {
	datasets = [cal_random, cal_partial, cal_repeated];
	variants = [m_00, m_04, m_08, m_10, m_12, m_16, m_20, m_24, m_30, m_40, m_50, m_64];
	metrics = [monotonic_ns, comparisons, swaps, moves, cycles, instructions, branch_misses, l1d_misses, llc_misses];
	output_csv = "report/data/calibration_m.csv";
}
