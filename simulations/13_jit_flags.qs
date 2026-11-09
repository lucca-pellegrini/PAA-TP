# Dynamic JIT recompilation (.so) across compiler optimization levels
host {
	pin_cpus = [0];
	cold_cache = false;
	repetitions = 3;
	warmup = 1;
}

dataset d_jit {
	sizes = [2000, 8000];
	expr = random(n, min=0, max=100000, seed=1313);
}

variant jit_O1     { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; cflags = "-O1"; }
variant jit_O2     { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; cflags = "-O2"; }
variant jit_O3_nat { partition = hoare; pivot = median3; cutoff = 16; small_sort = insertion; cflags = "-O3 -march=native"; }

benchmark jit_opt_levels {
	datasets = [d_jit];
	variants = [jit_O1, jit_O2, jit_O3_nat];
	metrics = [monotonic_ns, cycles, instructions];
	emit_asm = false;
}
