#include "sysinfo.h"
#include "util.h"

#include <ctype.h>
#include <sys/utsname.h>
#include <unistd.h>

static void trim_newline(char *s)
{
	size_t len = strlen(s);
	while (len > 0 &&
	       (s[len - 1] == '\n' || s[len - 1] == '\r' || isspace((unsigned char)s[len - 1]))) {
		s[--len] = '\0';
	}
}

static int read_first_line(const char *path, char *buf, size_t cap)
{
	if (cap == 0) {
		return -1;
	}
	buf[0] = '\0';
	FILE *fp = fopen(path, "r");
	if (fp == nullptr) {
		return -1;
	}
	if (fgets(buf, (int)cap, fp) == nullptr) {
		fclose(fp);
		return -1;
	}
	fclose(fp);
	trim_newline(buf);
	return 0;
}

static size_t parse_cache_size(const char *s)
{
	char *end = nullptr;
	unsigned long long val = strtoull(s, &end, 10);
	if (end != nullptr) {
		if (*end == 'K' || *end == 'k') {
			val *= 1024ULL;
		} else if (*end == 'M' || *end == 'm') {
			val *= 1024ULL * 1024ULL;
		} else if (*end == 'G' || *end == 'g') {
			val *= 1024ULL * 1024ULL * 1024ULL;
		}
	}
	return (size_t)val;
}

static void detect_cpuinfo(QsHostInfo *out)
{
	FILE *fp = fopen("/proc/cpuinfo", "r");
	if (fp == nullptr) {
		return;
	}
	char line[256];
	bool model_set = false;
	bool cores_set = false;

	while (fgets(line, sizeof(line), fp) != nullptr) {
		char *colon = strchr(line, ':');
		if (colon == nullptr) {
			continue;
		}
		*colon = '\0';
		char *val = colon + 1;
		while (*val && isspace((unsigned char)*val)) {
			val++;
		}
		trim_newline(val);

		if (!model_set && strncmp(line, "model name", 10) == 0) {
			snprintf(out->cpu_model, sizeof(out->cpu_model), "%s", val);
			model_set = true;
		} else if (!cores_set && strncmp(line, "cpu cores", 9) == 0) {
			unsigned long c = strtoul(val, nullptr, 10);
			if (c > 0) {
				out->physical_cores = (uint32_t)c;
				cores_set = true;
			}
		}
		if (model_set && cores_set) {
			break;
		}
	}
	fclose(fp);
}

static void detect_caches(QsHostInfo *out)
{
	for (uint32_t idx = 0; idx < 8; idx++) {
		char path[128];
		char buf[64];

		snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu0/cache/index%u/level",
			 idx);
		if (read_first_line(path, buf, sizeof(buf)) != 0) {
			continue;
		}
		QsCacheLevel *cl = &out->caches[out->num_caches];
		cl->level = (uint32_t)strtoul(buf, nullptr, 10);

		snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu0/cache/index%u/type",
			 idx);
		if (read_first_line(path, buf, sizeof(buf)) == 0) {
			snprintf(cl->type, sizeof(cl->type), "%s", buf);
		} else {
			snprintf(cl->type, sizeof(cl->type), "Unified");
		}

		snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu0/cache/index%u/size",
			 idx);
		if (read_first_line(path, buf, sizeof(buf)) == 0) {
			cl->size_bytes = parse_cache_size(buf);
		}

		snprintf(path, sizeof(path),
			 "/sys/devices/system/cpu/cpu0/cache/index%u/coherency_line_size", idx);
		if (read_first_line(path, buf, sizeof(buf)) == 0) {
			cl->line_size = (uint32_t)strtoul(buf, nullptr, 10);
		}

		snprintf(path, sizeof(path),
			 "/sys/devices/system/cpu/cpu0/cache/index%u/ways_of_associativity", idx);
		if (read_first_line(path, buf, sizeof(buf)) == 0) {
			cl->ways = (uint32_t)strtoul(buf, nullptr, 10);
		}

		if (cl->line_size > 0 && out->cache_line_bytes == 0) {
			out->cache_line_bytes = cl->line_size;
		}
		if (cl->level == 1 && strcmp(cl->type, "Data") == 0) {
			out->l1d_bytes = cl->size_bytes;
		} else if (cl->level == 1 && strcmp(cl->type, "Instruction") == 0) {
			out->l1i_bytes = cl->size_bytes;
		} else if (cl->level == 2) {
			out->l2_bytes = cl->size_bytes;
		} else if (cl->level == 3) {
			out->l3_bytes = cl->size_bytes;
		}
		out->num_caches++;
	}
}

int qs_sysinfo_detect(QsHostInfo *out)
{
	int ret = 0;
	ERRNOCHECK(out == nullptr, EINVAL, err);

	memset(out, 0, sizeof(*out));
	snprintf(out->cpu_model, sizeof(out->cpu_model), "Unknown CPU");
	snprintf(out->kernel_release, sizeof(out->kernel_release), "Unknown");
	snprintf(out->compiler_version, sizeof(out->compiler_version), "%s", __VERSION__);
	out->perf_event_paranoid = 2;

	long nprocs = sysconf(_SC_NPROCESSORS_ONLN);
	out->logical_cpus = nprocs > 0 ? (uint32_t)nprocs : 1U;
	out->physical_cores = out->logical_cpus;

	long pages = sysconf(_SC_PHYS_PAGES);
	long page_sz = sysconf(_SC_PAGE_SIZE);
	if (pages > 0 && page_sz > 0) {
		out->total_ram_bytes = (size_t)pages * (size_t)page_sz;
	}

	struct utsname uts;
	if (uname(&uts) == 0) {
		snprintf(out->kernel_release, sizeof(out->kernel_release), "%s", uts.release);
	}

	char buf[64];
	if (read_first_line("/proc/sys/kernel/perf_event_paranoid", buf, sizeof(buf)) == 0) {
		out->perf_event_paranoid = (int)strtol(buf, nullptr, 10);
	}

	detect_cpuinfo(out);
	detect_caches(out);

	if (out->l1d_bytes == 0) {
		out->l1d_bytes = 32ULL * 1024ULL;
	}
	if (out->l1i_bytes == 0) {
		out->l1i_bytes = 32ULL * 1024ULL;
	}
	if (out->l2_bytes == 0) {
		out->l2_bytes = 512ULL * 1024ULL;
	}
	if (out->l3_bytes == 0) {
		out->l3_bytes = 8ULL * 1024ULL * 1024ULL;
	}
	if (out->cache_line_bytes == 0) {
		out->cache_line_bytes = 64U;
	}

	return 0;
err:
	ret = -1;
	return ret;
}

void qs_sysinfo_print(const QsHostInfo *info, FILE *stream)
{
	if (info == nullptr || stream == nullptr) {
		return;
	}
	fprintf(stream, "Host CPU      : %s (%u cores / %u threads)\n", info->cpu_model,
		info->physical_cores, info->logical_cpus);
	fprintf(stream,
		"Caches        : L1d=%zu KiB, L1i=%zu KiB, L2=%zu KiB, L3=%zu KiB (line=%u B)\n",
		info->l1d_bytes / 1024, info->l1i_bytes / 1024, info->l2_bytes / 1024,
		info->l3_bytes / 1024, info->cache_line_bytes);
	fprintf(stream, "Memory / OS   : %.2f GiB RAM | Linux %s | perf_paranoid=%d\n",
		(double)info->total_ram_bytes / (1024.0 * 1024.0 * 1024.0), info->kernel_release,
		info->perf_event_paranoid);
	fprintf(stream, "Compiler      : %s\n", info->compiler_version);
}

int qs_sysinfo_write_csv(const QsHostInfo *info, const char *path)
{
	FILE *fp = nullptr;
	ERRNOCHECK(info == nullptr || path == nullptr, EINVAL, err);

	fp = fopen(path, "w");
	ERRNOCHECK(fp == nullptr, errno, err);

	fprintf(fp,
		"cpu_model,physical_cores,logical_cpus,l1d_bytes,l1i_bytes,l2_bytes,l3_bytes,"
		"cache_line_bytes,total_ram_bytes,kernel_release,perf_event_paranoid,compiler_version\n");
	fprintf(fp, "\"%s\",%u,%u,%zu,%zu,%zu,%zu,%u,%zu,\"%s\",%d,\"%s\"\n", info->cpu_model,
		info->physical_cores, info->logical_cpus, info->l1d_bytes, info->l1i_bytes,
		info->l2_bytes, info->l3_bytes, info->cache_line_bytes, info->total_ram_bytes,
		info->kernel_release, info->perf_event_paranoid, info->compiler_version);

	fclose(fp);
	return 0;
err:
	if (fp != nullptr) {
		fclose(fp);
	}
	return -1;
}

static uint32_t find_cache_ways(const QsHostInfo *info, uint32_t level, const char *type)
{
	for (size_t i = 0; i < info->num_caches; i++) {
		if (info->caches[i].level == level &&
		    (type == nullptr || strcmp(info->caches[i].type, type) == 0)) {
			return info->caches[i].ways;
		}
	}
	return 0;
}

int qs_sysinfo_write_latex(const QsHostInfo *info, const char *path)
{
	FILE *fp = nullptr;
	ERRNOCHECK(info == nullptr || path == nullptr, EINVAL, err);

	fp = fopen(path, "w");
	ERRNOCHECK(fp == nullptr, errno, err);

	uint32_t l1d_ways = find_cache_ways(info, 1, "Data");
	uint32_t l1i_ways = find_cache_ways(info, 1, "Instruction");
	uint32_t l2_ways = find_cache_ways(info, 2, nullptr);
	uint32_t l3_ways = find_cache_ways(info, 3, nullptr);

	fprintf(fp, "\\begin{tabular}{ll}\n");
	fprintf(fp, "\\toprule\n");
	fprintf(fp, "\\textbf{Par\\^ametro} & \\textbf{Especifica\\c{c}\\~ao do Host} \\\\\n");
	fprintf(fp, "\\midrule\n");
	fprintf(fp, "Processador & %s \\\\\n", info->cpu_model);
	fprintf(fp, "Topologia SMP & %u n\\'ucleos f\\'isicos / %u threads l\\'ogicas \\\\\n",
		info->physical_cores, info->logical_cpus);
	fprintf(fp, "Cache L1d / L1i & %zu KiB (%u-way) / %zu KiB (%u-way), linha %u B \\\\\n",
		info->l1d_bytes / 1024, l1d_ways, info->l1i_bytes / 1024, l1i_ways,
		info->cache_line_bytes);
	fprintf(fp, "Cache L2 (por n\\'ucleo) & %zu KiB (%u-way) \\\\\n", info->l2_bytes / 1024,
		l2_ways);
	fprintf(fp, "Cache L3 (LLC compartilhada) & %zu MiB (%u-way) \\\\\n",
		info->l3_bytes / (1024 * 1024), l3_ways);
	fprintf(fp, "Mem\\'oria Principal (RAM) & %.2f GiB \\\\\n",
		(double)info->total_ram_bytes / (1024.0 * 1024.0 * 1024.0));
	fprintf(fp, "Sistema Operacional & Linux %s (\\texttt{perf\\_paranoid=%d}) \\\\\n",
		info->kernel_release, info->perf_event_paranoid);
	fprintf(fp, "Compilador C23 & %s \\\\\n", info->compiler_version);
	fprintf(fp, "\\bottomrule\n");
	fprintf(fp, "\\end{tabular}\n");

	fclose(fp);
	return 0;
err:
	if (fp != nullptr) {
		fclose(fp);
	}
	return -1;
}
