# Exercise all built-in vector generator presets
host {
	pin_cpus = [0];
	cold_cache = false;
	repetitions = 3;
	warmup = 1;
}

dataset d_random {
	sizes = [500, 2000];
	expr = random(n, min=-5000, max=5000, seed=101);
}

dataset d_sorted {
	sizes = [500, 2000];
	expr = sorted(n, order=asc, step=2);
}

dataset d_reverse {
	sizes = [500, 2000];
	expr = reverse(n, step=1);
}

dataset d_repeated {
	sizes = [500, 2000];
	expr = repeated(n, unique=16, seed=202);
}

dataset d_constant {
	sizes = [500, 2000];
	expr = constant(n, value=77);
}

dataset d_organ_pipe {
	sizes = [500, 2000];
	expr = organ_pipe(n);
}

dataset d_sawtooth {
	sizes = [500, 2000];
	expr = sawtooth(n, period=32);
}

dataset d_adv_med3 {
	sizes = [500, 2000];
	expr = adversarial_med3(n);
}

variant pdq_var {
	partition = pdq;
	pivot = ninther;
	cutoff = 16;
	small_sort = insertion;
}

benchmark presets_suite {
	datasets = [d_random, d_sorted, d_reverse, d_repeated, d_constant, d_organ_pipe, d_sawtooth, d_adv_med3];
	variants = [pdq_var];
	metrics = [monotonic_ns, comparisons, swaps];
}
