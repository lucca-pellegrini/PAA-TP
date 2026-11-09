#include "jit.h"
#include "metrics.h"
#include "parser.h"
#include "quicksort.h"
#include "sysinfo.h"
#include "threadpool.h"
#include "ui.h"
#include "util.h"
#include "vec.h"

#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static void mkdir_parents(const char *file_path)
{
	if (!file_path)
		return;
	char tmp[512];
	snprintf(tmp, sizeof(tmp), "%s", file_path);
	for (char *p = tmp + 1; *p; p++) {
		if (*p == '/') {
			*p = '\0';
			(void)mkdir(tmp, 0755);
			*p = '/';
		}
	}
}

static size_t count_plan_steps(const QsSimPlan *plan)
{
	size_t total = 0;
	size_t default_reps = plan->host.repetitions > 0 ? plan->host.repetitions : 5;
	size_t warmup = plan->host.warmup;

	for (size_t bi = 0; bi < plan->num_benchmarks; bi++) {
		const QsBenchmarkSpec *bm = &plan->benchmarks[bi];
		size_t reps = bm->repetitions > 0 ? bm->repetitions : default_reps;
		for (size_t di = 0; di < bm->num_datasets; di++) {
			const char *ds_name = bm->dataset_names[di];
			const QsDatasetSpec *ds = nullptr;
			for (size_t k = 0; k < plan->num_datasets; k++) {
				if (strcmp(plan->datasets[k].name, ds_name) == 0) {
					ds = &plan->datasets[k];
					break;
				}
			}
			if (!ds)
				continue;
			size_t n_sizes = ds->num_sizes > 0 ? ds->num_sizes : 1;
			total += n_sizes * bm->num_variants * (warmup + reps);
		}
	}
	return total > 0 ? total : 1;
}

typedef struct {
	bool no_tui;
	bool headless;
	bool force_static_jit;
	bool dry_run;
	const char *sysinfo_csv;
	const char *sysinfo_tex;
	const char **files;
	size_t n_files;
} CliArgs;

static void print_usage(const char *prog)
{
	fprintf(stderr,
		"Usage: %s [options] <simulation.qs> [more.qs ...]\n"
		"Options:\n"
		"  --no-tui             Force fallback to stderr progress bar\n"
		"  --headless, -q       Disable interactive progress UI\n"
		"  --no-jit             Use static built-in kernels even with custom flags\n"
		"  --dry-run, --check   Parse and validate .qs files without running\n"
		"  --sysinfo-csv <f>    Write host topology CSV to <f>\n"
		"  --sysinfo-tex <f>    Write host topology LaTeX table to <f>\n"
		"  --help, -h           Show this help message\n",
		prog);
}

static int run_simulation_file(const char *sim_path, const CliArgs *cli,
			       const QsHostInfo *host_info, QsJitCache *jit_cache, QsUi *ui)
{
	QsSimPlan *plan = calloc(1, sizeof(*plan));
	if (!plan)
		return -1;

	if (qs_parse_file(sim_path, plan) != 0) {
		free(plan);
		return -1;
	}

	if (cli->dry_run) {
		qs_sim_plan_destroy(plan);
		free(plan);
		return 0;
	}

	if (plan->host.num_pin_cpus > 0) {
		(void)qs_pin_current_thread(plan->host.pin_cpus[0]);
	} else {
		(void)qs_pin_current_thread(0);
	}

	size_t max_threads = 1;
	for (size_t vi = 0; vi < plan->num_variants; vi++) {
		if (plan->variants[vi].cfg.exec_mode == QS_EXEC_PARALLEL &&
		    plan->variants[vi].cfg.parallel_threshold > max_threads) {
			max_threads = plan->variants[vi].cfg.parallel_threshold;
		}
	}

	QsThreadPool *pool = nullptr;
	if (max_threads > 1) {
		pool = qs_threadpool_create(max_threads, plan->host.pin_cpus,
					    plan->host.num_pin_cpus);
	}

	size_t llc_bytes = host_info->l3_bytes > 0 ? host_info->l3_bytes :
						     (32ULL * 1024ULL * 1024ULL);
	QsMetricsCtx *metrics = qs_metrics_create(plan->host.enable_pmu, llc_bytes);
	if (!metrics) {
		qs_threadpool_destroy(pool);
		qs_sim_plan_destroy(plan);
		free(plan);
		return -1;
	}

	size_t total_steps = count_plan_steps(plan);
	size_t completed_steps = 0;
	size_t default_reps = plan->host.repetitions > 0 ? plan->host.repetitions : 5;
	size_t warmup = plan->host.warmup;

	for (size_t bi = 0; bi < plan->num_benchmarks; bi++) {
		const QsBenchmarkSpec *bm = &plan->benchmarks[bi];
		size_t reps = bm->repetitions > 0 ? bm->repetitions : default_reps;
		bool bm_cold_cache = (bm->cold_cache_override >= 0) ?
					     (bool)bm->cold_cache_override :
					     plan->host.cold_cache;

		FILE *csv_fp = nullptr;
		if (bm->output_csv[0] != '\0') {
			mkdir_parents(bm->output_csv);
			csv_fp = fopen(bm->output_csv, "w");
			if (csv_fp) {
				fprintf(csv_fp,
					"benchmark,dataset,variant,partition,pivot,cutoff,"
					"small_sort,execution,threads,n,repetitions,sorted_ok,"
					"depth_exceeded,max_depth,comparisons,swaps,moves,"
					"mean_ns,stddev_ns,min_ns,max_ns,mean_ms,mean_us,"
					"mean_cycles,mean_instructions,ipc,mean_branches,"
					"mean_branch_misses,branch_miss_pct,mean_l1d_misses,"
					"mean_llc_misses,jit_hash\n");
			}
		}

		for (size_t di = 0; di < bm->num_datasets; di++) {
			const char *ds_name = bm->dataset_names[di];
			const QsDatasetSpec *ds = nullptr;
			for (size_t k = 0; k < plan->num_datasets; k++) {
				if (strcmp(plan->datasets[k].name, ds_name) == 0) {
					ds = &plan->datasets[k];
					break;
				}
			}
			if (!ds)
				continue;

			size_t default_sz = 1000;
			const size_t *sizes = ds->num_sizes > 0 ? ds->sizes : &default_sz;
			size_t n_sizes = ds->num_sizes > 0 ? ds->num_sizes : 1;

			for (size_t si = 0; si < n_sizes; si++) {
				size_t n = sizes[si];

				/* Pre-generate identical input vectors for all variants */
				QsVec *rep_vecs = calloc(reps, sizeof(*rep_vecs));
				if (!rep_vecs)
					continue;

				bool gen_ok = true;
				for (size_t r = 0; r < reps; r++) {
					uint64_t seed_override =
						(r == 0) ? 0 : (0x9E3779B97F4A7C15ULL * (r + 1));
					rep_vecs[r] =
						qs_vexpr_eval(ds->expr, n, plan, seed_override);
					if (n > 0 && !rep_vecs[r].data) {
						gen_ok = false;
						break;
					}
				}
				if (!gen_ok) {
					for (size_t r = 0; r < reps; r++)
						free(rep_vecs[r].data);
					free(rep_vecs);
					continue;
				}

				for (size_t vi = 0; vi < bm->num_variants; vi++) {
					const char *var_name = bm->variant_names[vi];
					const QsVariantSpec *var = nullptr;
					for (size_t k = 0; k < plan->num_variants; k++) {
						if (strcmp(plan->variants[k].name, var_name) == 0) {
							var = &plan->variants[k];
							break;
						}
					}
					if (!var)
						continue;

					QsJitOptions jopts = var->jit;
					if (cli->force_static_jit) {
						jopts = qs_jit_options_default();
					}

					const QsJitModule *mod = qs_jit_acquire(jit_cache, &jopts);
					if (!mod)
						continue;

					QsConfig cfg = var->cfg;
					cfg.pool = pool;
					cfg.seed = 0xC0FFEE123456ULL;
					size_t threads = (cfg.exec_mode == QS_EXEC_PARALLEL &&
							  cfg.parallel_threshold > 0) ?
								 cfg.parallel_threshold :
								 1;

					/* Warmup passes */
					for (size_t w = 0; w < warmup; w++) {
						QsVec *work = qs_vec_clone(&rep_vecs[0]);
						if (work) {
							QsRunStats st = { 0 };
							(void)mod->run_clean(work->data, work->len,
									     &cfg, &st);
							qs_vec_destroy(work);
						}
						completed_steps++;
					}

					double *ns_samples = calloc(reps, sizeof(double));
					double sum_ns = 0.0;
					double min_ns = 1e30;
					double max_ns = 0.0;
					double sum_cycles = 0.0;
					double sum_inst = 0.0;
					double sum_branches = 0.0;
					double sum_bmisses = 0.0;
					double sum_l1d = 0.0;
					double sum_llc = 0.0;
					uint64_t total_cmp = 0;
					uint64_t total_swp = 0;
					uint64_t total_mov = 0;
					uint64_t max_depth_obs = 0;
					bool all_sorted = true;
					bool any_depth_exceeded = false;

					for (size_t r = 0; r < reps; r++) {
						QsVec *work = qs_vec_clone(&rep_vecs[r]);
						if (!work)
							continue;

						if (bm_cold_cache)
							qs_metrics_thrash_cache(metrics);

						cfg.seed = 0xC0FFEE123456ULL + r;
						QsRunStats clean_st = { 0 };

						qs_metrics_begin(metrics);
						(void)mod->run_clean(work->data, work->len, &cfg,
								     &clean_st);
						QsPerfSnapshot snap = qs_metrics_end(metrics);

						if (clean_st.depth_limit_exceeded)
							any_depth_exceeded = true;
						if (clean_st.max_depth_reached > max_depth_obs)
							max_depth_obs = clean_st.max_depth_reached;

						if (!clean_st.depth_limit_exceeded &&
						    !qs_vec_verify(work->data, work->len, cfg.order,
								   rep_vecs[r].multiset_hash)) {
							all_sorted = false;
							fprintf(stderr,
								"[error] sort verification failed: "
								"benchmark=%s dataset=%s variant=%s "
								"n=%zu rep=%zu\n",
								bm->name, ds->name, var->name, n,
								r);
						}
						qs_vec_destroy(work);

						/* Second pass for exact comparisons/swaps/moves */
						uint64_t rep_cmp = 0;
						uint64_t rep_swp = 0;
						uint64_t rep_mov = 0;
						if (bm->metrics_mask &
						    (QS_METRIC_COMPARISONS | QS_METRIC_SWAPS |
						     QS_METRIC_MOVES)) {
							QsVec *cwork = qs_vec_clone(&rep_vecs[r]);
							if (cwork) {
								cfg.seed = 0xC0FFEE123456ULL + r;
								QsRunStats cnt_st = { 0 };
								(void)mod->run_counted(cwork->data,
										       cwork->len,
										       &cfg,
										       &cnt_st);
								rep_cmp = cnt_st.comparisons;
								rep_swp = cnt_st.swaps;
								rep_mov = cnt_st.moves;
								if (cnt_st.max_depth_reached >
								    max_depth_obs) {
									max_depth_obs =
										cnt_st.max_depth_reached;
								}
								qs_vec_destroy(cwork);
							}
						}

						double dns = (double)snap.monotonic_ns;
						if (ns_samples)
							ns_samples[r] = dns;
						sum_ns += dns;
						if (dns < min_ns)
							min_ns = dns;
						if (dns > max_ns)
							max_ns = dns;
						sum_cycles += (double)snap.cpu_cycles;
						sum_inst += (double)snap.instructions;
						sum_branches += (double)snap.branch_instructions;
						sum_bmisses += (double)snap.branch_misses;
						sum_l1d += (double)snap.l1d_misses;
						sum_llc += (double)snap.llc_misses;
						total_cmp += rep_cmp;
						total_swp += rep_swp;
						total_mov += rep_mov;

						completed_steps++;
						if (ui) {
							int pin = plan->host.num_pin_cpus > 0 ?
									  plan->host.pin_cpus[0] :
									  0;
							QsUiTelemetry tel = {
								.benchmark_name = bm->name,
								.dataset_name = ds->name,
								.variant_name = var->name,
								.current_step = completed_steps,
								.total_steps = total_steps,
								.current_rep = r + 1,
								.total_reps = reps,
								.array_size = n,
								.active_threads = (uint32_t)threads,
								.pinned_cpu = pin,
								.last_time_ns = dns,
								.comparisons = rep_cmp,
								.swaps = rep_swp,
								.cycles = snap.cpu_cycles,
								.instructions = snap.instructions,
								.branch_misses = snap.branch_misses,
								.l1d_misses = snap.l1d_misses,
								.llc_misses = snap.llc_misses,
							};
							qs_ui_update(ui, &tel);
						}
					}

					double mean_ns = sum_ns / (double)reps;
					double var_ns = 0.0;
					if (ns_samples && reps > 1) {
						for (size_t r = 0; r < reps; r++) {
							double d = ns_samples[r] - mean_ns;
							var_ns += d * d;
						}
						var_ns /= (double)(reps - 1);
					}
					double stddev_ns = sqrt(var_ns);
					free(ns_samples);

					double mean_cyc = sum_cycles / (double)reps;
					double mean_ins = sum_inst / (double)reps;
					double ipc = mean_cyc > 0.0 ? (mean_ins / mean_cyc) : 0.0;
					double mean_br = sum_branches / (double)reps;
					double mean_bm = sum_bmisses / (double)reps;
					double bm_pct =
						mean_br > 0.0 ? (100.0 * mean_bm / mean_br) : 0.0;

					if (csv_fp) {
						fprintf(csv_fp,
							"%s,%s,%s,%s,%s,%zu,%s,%s,%zu,%zu,%zu,"
							"%d,%d,%llu,%llu,%llu,%llu,"
							"%.2f,%.2f,%.2f,%.2f,%.6f,%.3f,"
							"%.1f,%.1f,%.3f,%.1f,%.1f,%.3f,%.1f,%.1f,"
							"%016llx\n",
							bm->name, ds->name, var->name,
							qs_partition_name(cfg.partition),
							qs_pivot_name(cfg.pivot), cfg.cutoff,
							qs_small_sort_name(cfg.small_sort),
							qs_exec_mode_name(cfg.exec_mode), threads,
							n, reps, all_sorted ? 1 : 0,
							any_depth_exceeded ? 1 : 0,
							(unsigned long long)max_depth_obs,
							(unsigned long long)(total_cmp / reps),
							(unsigned long long)(total_swp / reps),
							(unsigned long long)(total_mov / reps),
							mean_ns, stddev_ns, min_ns, max_ns,
							mean_ns / 1e6, mean_ns / 1e3, mean_cyc,
							mean_ins, ipc, mean_br, mean_bm, bm_pct,
							sum_l1d / (double)reps,
							sum_llc / (double)reps,
							(unsigned long long)mod->key_hash);
						fflush(csv_fp);
					}
				}

				for (size_t r = 0; r < reps; r++)
					free(rep_vecs[r].data);
				free(rep_vecs);
			}
		}

		if (csv_fp)
			fclose(csv_fp);
	}

	qs_metrics_destroy(metrics);
	qs_threadpool_destroy(pool);
	qs_sim_plan_destroy(plan);
	free(plan);
	return 0;
}

int main(int argc, char **argv)
{
	CliArgs cli = { 0 };
	const char **files = calloc((size_t)argc, sizeof(*files));
	if (!files)
		return EXIT_FAILURE;
	cli.files = files;

	for (int i = 1; i < argc; i++) {
		const char *arg = argv[i];
		if (strcmp(arg, "--no-tui") == 0) {
			cli.no_tui = true;
		} else if (strcmp(arg, "--headless") == 0 || strcmp(arg, "-q") == 0) {
			cli.headless = true;
		} else if (strcmp(arg, "--no-jit") == 0) {
			cli.force_static_jit = true;
		} else if (strcmp(arg, "--dry-run") == 0 || strcmp(arg, "--check") == 0) {
			cli.dry_run = true;
		} else if (strcmp(arg, "--sysinfo-csv") == 0 && i + 1 < argc) {
			cli.sysinfo_csv = argv[++i];
		} else if (strcmp(arg, "--sysinfo-tex") == 0 && i + 1 < argc) {
			cli.sysinfo_tex = argv[++i];
		} else if (strcmp(arg, "--help") == 0 || strcmp(arg, "-h") == 0) {
			print_usage(argv[0]);
			free(files);
			return EXIT_SUCCESS;
		} else if (arg[0] == '-') {
			fprintf(stderr, "Unknown option: %s\n", arg);
			print_usage(argv[0]);
			free(files);
			return EXIT_FAILURE;
		} else {
			cli.files[cli.n_files++] = arg;
		}
	}

	QsHostInfo host_info = { 0 };
	(void)qs_sysinfo_detect(&host_info);

	if (cli.sysinfo_csv) {
		mkdir_parents(cli.sysinfo_csv);
		(void)qs_sysinfo_write_csv(&host_info, cli.sysinfo_csv);
	}
	if (cli.sysinfo_tex) {
		mkdir_parents(cli.sysinfo_tex);
		(void)qs_sysinfo_write_latex(&host_info, cli.sysinfo_tex);
	}

	if (cli.n_files == 0) {
		if (cli.sysinfo_csv || cli.sysinfo_tex) {
			free(files);
			return EXIT_SUCCESS;
		}
		print_usage(argv[0]);
		free(files);
		return EXIT_FAILURE;
	}

	QsJitCache *jit_cache = qs_jit_cache_create("build/jit");
	if (!jit_cache) {
		free(files);
		return EXIT_FAILURE;
	}

	QsUi *ui = nullptr;
	if (!cli.headless && !cli.dry_run) {
		ui = qs_ui_create(0, !cli.no_tui, nullptr);
	}

	int status = EXIT_SUCCESS;
	for (size_t i = 0; i < cli.n_files; i++) {
		if (run_simulation_file(cli.files[i], &cli, &host_info, jit_cache, ui) != 0) {
			status = EXIT_FAILURE;
		}
	}

	if (ui) {
		qs_ui_finish(ui, "done");
		qs_ui_destroy(ui);
	}
	qs_jit_cache_destroy(jit_cache);
	free(files);
	return status;
}
