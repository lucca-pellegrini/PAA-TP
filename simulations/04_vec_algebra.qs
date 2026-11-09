# Algebraic vector combinators: let bindings, ++ (concat), ** (interleave), ^ (blend), ~ (reverse), slices
host {
	pin_cpus = [0];
	cold_cache = false;
	repetitions = 3;
	warmup = 1;
}

let head_asc = sorted(500, order=asc, step=1);
let tail_desc = ~sorted(500, order=asc, step=2);
let noisy_mid = random(500, min=-100, max=100, seed=77);

dataset concat_ds {
	sizes = [1000];
	expr = head_asc ++ tail_desc;
}

dataset interleave_ds {
	sizes = [1000];
	expr = head_asc ** noisy_mid;
}

dataset blend_ds {
	sizes = [500];
	expr = head_asc ^ noisy_mid;
}

dataset slice_ds {
	sizes = [1000];
	expr = (head_asc ++ noisy_mid ++ tail_desc)[250..1250];
}

variant v_three_way {
	partition = three_way;
	pivot = median3;
	cutoff = 16;
	small_sort = insertion;
}

benchmark algebra_suite {
	datasets = [concat_ds, interleave_ds, blend_ds, slice_ds];
	variants = [v_three_way];
	metrics = [monotonic_ns, comparisons, swaps, moves];
}
