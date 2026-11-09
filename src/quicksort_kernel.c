#include "quicksort.h"

#include <errno.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "util.h"

#if defined(QS_PRAGMA_UNROLL_COUNT) && (QS_PRAGMA_UNROLL_COUNT > 1)
#define QS_STR_HELPER(x) #x
#define QS_STR(x) QS_STR_HELPER(x)
#define QS_PRAGMA_UNROLL_PART _Pragma(QS_STR(clang loop unroll_count(QS_PRAGMA_UNROLL_COUNT)))
#elif defined(QS_PRAGMA_UNROLL_FULL)
#define QS_PRAGMA_UNROLL_PART _Pragma("clang loop unroll_count(4)")
#elif defined(QS_PRAGMA_NO_UNROLL)
#define QS_PRAGMA_UNROLL_PART _Pragma("clang loop unroll(disable)")
#else
#define QS_PRAGMA_UNROLL_PART
#endif

#if defined(QS_PRAGMA_VECTORIZE)
#define QS_PRAGMA_VEC_PART _Pragma("clang loop vectorize(enable)")
#elif defined(QS_PRAGMA_NO_VECTORIZE)
#define QS_PRAGMA_VEC_PART _Pragma("clang loop vectorize(disable)")
#else
#define QS_PRAGMA_VEC_PART
#endif

#define QS_LOOP_PRAGMA QS_PRAGMA_UNROLL_PART QS_PRAGMA_VEC_PART

constexpr size_t QS_MAX_PARALLEL_TASKS = 256;
constexpr size_t QS_MAX_PARALLEL_DEPTH = 6;
constexpr size_t QS_DEFAULT_PARALLEL_THRESHOLD = 2048;
constexpr size_t QS_ITER_STACK_INIT_CAP = 128;

typedef struct {
	size_t l1;
	size_t h1;
	bool has_left;
	size_t l2;
	size_t h2;
	bool has_right;
} QsPartResult;

typedef struct {
	size_t low;
	size_t high;
	size_t depth;
	bool leftmost;
} QsStackFrame;

struct QsParallelShared;

typedef struct {
	struct QsParallelShared *shared;
	int *arr;
	size_t low;
	size_t high;
	size_t depth;
	bool leftmost;
	QsRng rng;
	QsRunStats stats;
} QsParallelTask;

typedef struct QsParallelShared {
	const QsConfig *cfg;
	size_t introsort_limit;
	size_t bad_allowed;
	size_t parallel_threshold;
	bool count_ops;
	atomic_size_t task_count;
	QsParallelTask tasks[QS_MAX_PARALLEL_TASKS];
} QsParallelShared;

static inline size_t qs_floor_log2(size_t n)
{
	size_t log = 0;
	while (n > 1) {
		n >>= 1;
		log++;
	}
	return log;
}

[[gnu::always_inline]] static inline bool qs_cmp_lt(int a, int b, QsOrder order, QsRunStats *stats,
						    const bool count_ops)
{
	if (count_ops) {
		stats->comparisons++;
	}
	return (order == QS_ORDER_ASC) ? (a < b) : (a > b);
}

[[gnu::always_inline]] static inline bool qs_cmp_gt(int a, int b, QsOrder order, QsRunStats *stats,
						    const bool count_ops)
{
	if (count_ops) {
		stats->comparisons++;
	}
	return (order == QS_ORDER_ASC) ? (a > b) : (a < b);
}

[[gnu::always_inline]] static inline void qs_swap(int *a, int *b, QsRunStats *stats,
						  const bool count_ops)
{
	int tmp = *a;
	*a = *b;
	*b = tmp;
	if (count_ops) {
		stats->swaps++;
		stats->moves += 3;
	}
}

[[gnu::always_inline]] static inline void qs_move(int *dst, int val, QsRunStats *stats,
						  const bool count_ops)
{
	*dst = val;
	if (count_ops) {
		stats->moves++;
	}
}

[[gnu::always_inline]] static inline void qs_sort3(int *arr, size_t a, size_t b, size_t c,
						   QsOrder order, QsRunStats *stats,
						   const bool count_ops)
{
	if (qs_cmp_lt(arr[b], arr[a], order, stats, count_ops)) {
		qs_swap(&arr[a], &arr[b], stats, count_ops);
	}
	if (qs_cmp_lt(arr[c], arr[b], order, stats, count_ops)) {
		qs_swap(&arr[b], &arr[c], stats, count_ops);
		if (qs_cmp_lt(arr[b], arr[a], order, stats, count_ops)) {
			qs_swap(&arr[a], &arr[b], stats, count_ops);
		}
	}
}

[[gnu::always_inline]] static inline void qs_insertion_sort(int *arr, size_t len, QsOrder order,
							    QsRunStats *stats, const bool count_ops)
{
	for (size_t i = 1; i < len; i++) {
		int key = arr[i];
		size_t j = i;
		QS_LOOP_PRAGMA
		while (j > 0 && qs_cmp_gt(arr[j - 1], key, order, stats, count_ops)) {
			qs_move(&arr[j], arr[j - 1], stats, count_ops);
			if (count_ops) {
				stats->swaps++;
			}
			j--;
		}
		if (j != i) {
			qs_move(&arr[j], key, stats, count_ops);
			if (count_ops) {
				stats->moves++;
			}
		}
	}
}

[[gnu::always_inline]] static inline void qs_binary_insertion_sort(int *arr, size_t len,
								   QsOrder order, QsRunStats *stats,
								   const bool count_ops)
{
	for (size_t i = 1; i < len; i++) {
		int key = arr[i];
		size_t lo = 0;
		size_t hi = i;
		while (lo < hi) {
			size_t mid = lo + (hi - lo) / 2;
			if (qs_cmp_lt(key, arr[mid], order, stats, count_ops)) {
				hi = mid;
			} else {
				lo = mid + 1;
			}
		}
		if (lo < i) {
			QS_LOOP_PRAGMA
			for (size_t j = i; j > lo; j--) {
				qs_move(&arr[j], arr[j - 1], stats, count_ops);
				if (count_ops) {
					stats->swaps++;
				}
			}
			qs_move(&arr[lo], key, stats, count_ops);
			if (count_ops) {
				stats->moves++;
			}
		}
	}
}

[[gnu::always_inline]] static inline void qs_shell_sort(int *arr, size_t len, QsOrder order,
							QsRunStats *stats, const bool count_ops)
{
	static const size_t gaps[] = { 701, 301, 132, 57, 23, 10, 4, 1 };
	for (size_t g = 0; g < sizeof(gaps) / sizeof(gaps[0]); g++) {
		size_t gap = gaps[g];
		if (gap >= len) {
			continue;
		}
		for (size_t i = gap; i < len; i++) {
			int key = arr[i];
			size_t j = i;
			QS_LOOP_PRAGMA
			while (j >= gap && qs_cmp_gt(arr[j - gap], key, order, stats, count_ops)) {
				qs_move(&arr[j], arr[j - gap], stats, count_ops);
				if (count_ops) {
					stats->swaps++;
				}
				j -= gap;
			}
			if (j != i) {
				qs_move(&arr[j], key, stats, count_ops);
				if (count_ops) {
					stats->moves++;
				}
			}
		}
	}
}

[[gnu::always_inline]] static inline void qs_sift_down(int *arr, size_t start, size_t end,
						       QsOrder order, QsRunStats *stats,
						       const bool count_ops)
{
	size_t root = start;
	QS_LOOP_PRAGMA
	while (2 * root + 1 <= end) {
		size_t child = 2 * root + 1;
		size_t swap_idx = root;
		if (qs_cmp_lt(arr[swap_idx], arr[child], order, stats, count_ops)) {
			swap_idx = child;
		}
		if (child + 1 <= end &&
		    qs_cmp_lt(arr[swap_idx], arr[child + 1], order, stats, count_ops)) {
			swap_idx = child + 1;
		}
		if (swap_idx == root) {
			return;
		}
		qs_swap(&arr[root], &arr[swap_idx], stats, count_ops);
		root = swap_idx;
	}
}

[[gnu::always_inline]] static inline void qs_heapsort(int *arr, size_t len, QsOrder order,
						      QsRunStats *stats, const bool count_ops)
{
	if (len < 2) {
		return;
	}
	for (size_t start = (len - 2) / 2 + 1; start > 0; start--) {
		qs_sift_down(arr, start - 1, len - 1, order, stats, count_ops);
	}
	for (size_t end = len - 1; end > 0; end--) {
		qs_swap(&arr[end], &arr[0], stats, count_ops);
		qs_sift_down(arr, 0, end - 1, order, stats, count_ops);
	}
}

[[gnu::always_inline]] static inline void qs_run_small_sort(int *arr, size_t len, QsSmallSort small,
							    QsOrder order, QsRunStats *stats,
							    const bool count_ops)
{
	if (len < 2) {
		return;
	}
	switch (small) {
	case QS_SMALL_INSERTION:
		qs_insertion_sort(arr, len, order, stats, count_ops);
		break;
	case QS_SMALL_BINARY_INSERTION:
		qs_binary_insertion_sort(arr, len, order, stats, count_ops);
		break;
	case QS_SMALL_SHELL:
		qs_shell_sort(arr, len, order, stats, count_ops);
		break;
	case QS_SMALL_HEAPSORT:
		qs_heapsort(arr, len, order, stats, count_ops);
		break;
	case QS_SMALL_NONE:
	default:
		break;
	}
}

[[gnu::always_inline]] static inline bool qs_partial_insertion_sort(int *arr, size_t len,
								    QsOrder order,
								    QsRunStats *stats,
								    const bool count_ops)
{
	if (len < 2) {
		return true;
	}
	size_t misplaced = 0;
	size_t shifts = 0;
	for (size_t i = 1; i < len; i++) {
		if (qs_cmp_gt(arr[i - 1], arr[i], order, stats, count_ops)) {
			if (++misplaced > 8) {
				return false;
			}
			int key = arr[i];
			size_t j = i;
			do {
				qs_move(&arr[j], arr[j - 1], stats, count_ops);
				if (count_ops) {
					stats->swaps++;
				}
				j--;
				if (++shifts > 64) {
					qs_move(&arr[j], key, stats, count_ops);
					if (count_ops) {
						stats->moves++;
					}
					return false;
				}
			} while (j > 0 && qs_cmp_gt(arr[j - 1], key, order, stats, count_ops));
			qs_move(&arr[j], key, stats, count_ops);
			if (count_ops) {
				stats->moves++;
			}
		}
	}
	return true;
}

[[gnu::always_inline]] static inline size_t qs_select_pivot_idx(int *arr, size_t low, size_t high,
								QsPivot pivot, QsOrder order,
								QsRng *rng, QsRunStats *stats,
								const bool count_ops)
{
	size_t len = high - low + 1;
	size_t mid = low + (high - low) / 2;

	switch (pivot) {
	case QS_PIVOT_FIRST:
		return low;
	case QS_PIVOT_LAST:
		return high;
	case QS_PIVOT_MIDDLE:
		return mid;
	case QS_PIVOT_RANDOM:
		return low + (size_t)qs_rng_bounded(rng, (uint64_t)len);
	case QS_PIVOT_NINTHER:
		if (len >= 40) {
			size_t step = len / 8;
			qs_sort3(arr, low, low + step, low + 2 * step, order, stats, count_ops);
			qs_sort3(arr, mid - step, mid, mid + step, order, stats, count_ops);
			qs_sort3(arr, high - 2 * step, high - step, high, order, stats, count_ops);
			qs_sort3(arr, low + step, mid, high - step, order, stats, count_ops);
			return mid;
		}
		qs_sort3(arr, low, mid, high, order, stats, count_ops);
		return mid;
	case QS_PIVOT_MEDIAN3:
	default:
		qs_sort3(arr, low, mid, high, order, stats, count_ops);
		return mid;
	}
}

[[gnu::always_inline]] static inline QsPartResult
qs_partition_hoare(int *arr, size_t low, size_t high, const QsConfig *cfg, QsRng *rng,
		   QsRunStats *stats, const bool count_ops)
{
	size_t p_idx =
		qs_select_pivot_idx(arr, low, high, cfg->pivot, cfg->order, rng, stats, count_ops);
	int pivot = arr[p_idx];
	size_t i = low;
	size_t j = high;

	QS_LOOP_PRAGMA
	while (i <= j) {
		QS_LOOP_PRAGMA
		while (qs_cmp_lt(arr[i], pivot, cfg->order, stats, count_ops)) {
			i++;
		}
		QS_LOOP_PRAGMA
		while (qs_cmp_gt(arr[j], pivot, cfg->order, stats, count_ops)) {
			j--;
		}
		if (i <= j) {
			qs_swap(&arr[i], &arr[j], stats, count_ops);
			i++;
			if (j == 0) {
				j = SIZE_MAX;
				break;
			}
			j--;
		}
	}

	return (QsPartResult){
		.l1 = low,
		.h1 = j,
		.has_left = (j != SIZE_MAX && low < j),
		.l2 = i,
		.h2 = high,
		.has_right = (i < high),
	};
}

[[gnu::always_inline]] static inline QsPartResult
qs_partition_lomuto(int *arr, size_t low, size_t high, const QsConfig *cfg, QsRng *rng,
		    QsRunStats *stats, const bool count_ops)
{
	size_t p_idx =
		qs_select_pivot_idx(arr, low, high, cfg->pivot, cfg->order, rng, stats, count_ops);
	if (p_idx != high) {
		qs_swap(&arr[p_idx], &arr[high], stats, count_ops);
	}
	int pivot = arr[high];
	size_t i = low;

	QS_LOOP_PRAGMA
	for (size_t j = low; j < high; j++) {
		if (qs_cmp_lt(arr[j], pivot, cfg->order, stats, count_ops)) {
			qs_swap(&arr[i], &arr[j], stats, count_ops);
			i++;
		}
	}
	qs_swap(&arr[i], &arr[high], stats, count_ops);

	return (QsPartResult){
		.l1 = low,
		.h1 = i > 0 ? i - 1 : 0,
		.has_left = (i > low),
		.l2 = i + 1,
		.h2 = high,
		.has_right = (i < high),
	};
}

[[gnu::always_inline]] static inline QsPartResult
qs_partition_three_way(int *arr, size_t low, size_t high, const QsConfig *cfg, QsRng *rng,
		       QsRunStats *stats, const bool count_ops)
{
	size_t p_idx =
		qs_select_pivot_idx(arr, low, high, cfg->pivot, cfg->order, rng, stats, count_ops);
	if (p_idx != low) {
		qs_swap(&arr[low], &arr[p_idx], stats, count_ops);
	}
	int pivot = arr[low];
	size_t lt = low;
	size_t i = low + 1;
	size_t gt = high;

	QS_LOOP_PRAGMA
	while (i <= gt) {
		if (qs_cmp_lt(arr[i], pivot, cfg->order, stats, count_ops)) {
			qs_swap(&arr[lt], &arr[i], stats, count_ops);
			lt++;
			i++;
		} else if (qs_cmp_gt(arr[i], pivot, cfg->order, stats, count_ops)) {
			qs_swap(&arr[i], &arr[gt], stats, count_ops);
			if (gt == 0) {
				break;
			}
			gt--;
		} else {
			i++;
		}
	}

	return (QsPartResult){
		.l1 = low,
		.h1 = lt > 0 ? lt - 1 : 0,
		.has_left = (lt > low),
		.l2 = gt + 1,
		.h2 = high,
		.has_right = (gt < high),
	};
}

[[gnu::always_inline]] static inline QsPartResult
qs_partition_pdq(int *arr, size_t low, size_t high, bool leftmost, size_t bad_allowed,
		 const QsConfig *cfg, QsRng *rng, QsRunStats *stats, const bool count_ops)
{
	size_t len = high - low + 1;
	size_t mid = low + len / 2;

	if (cfg->pivot == QS_PIVOT_FIRST || cfg->pivot == QS_PIVOT_LAST ||
	    cfg->pivot == QS_PIVOT_RANDOM) {
		size_t p_idx = qs_select_pivot_idx(arr, low, high, cfg->pivot, cfg->order, rng,
						   stats, count_ops);
		if (p_idx != low) {
			qs_swap(&arr[low], &arr[p_idx], stats, count_ops);
		}
	} else if (len >= 64 || cfg->pivot == QS_PIVOT_NINTHER) {
		size_t step = len / 8;
		if (step > 0) {
			qs_sort3(arr, low, low + step, low + 2 * step, cfg->order, stats,
				 count_ops);
			qs_sort3(arr, mid - step, mid, mid + step, cfg->order, stats, count_ops);
			qs_sort3(arr, high - 2 * step, high - step, high, cfg->order, stats,
				 count_ops);
			qs_sort3(arr, low + step, mid, high - step, cfg->order, stats, count_ops);
		} else {
			qs_sort3(arr, low, mid, high, cfg->order, stats, count_ops);
		}
		qs_swap(&arr[low], &arr[mid], stats, count_ops);
	} else {
		qs_sort3(arr, mid, low, high, cfg->order, stats, count_ops);
	}

	int pivot = arr[low];

	if (!leftmost && !qs_cmp_lt(arr[low - 1], pivot, cfg->order, stats, count_ops)) {
		size_t i = low + 1;
		size_t j = high;
		for (;;) {
			QS_LOOP_PRAGMA
			while (i <= j && !qs_cmp_lt(pivot, arr[i], cfg->order, stats, count_ops)) {
				i++;
			}
			QS_LOOP_PRAGMA
			while (i <= j && qs_cmp_lt(pivot, arr[j], cfg->order, stats, count_ops)) {
				j--;
			}
			if (i > j) {
				break;
			}
			qs_swap(&arr[i], &arr[j], stats, count_ops);
			i++;
			j--;
		}
		return (QsPartResult){
			.l1 = 0,
			.h1 = 0,
			.has_left = false,
			.l2 = i,
			.h2 = high,
			.has_right = (i < high),
		};
	}

	size_t i = low + 1;
	size_t j = high;
	QS_LOOP_PRAGMA
	while (i <= j && qs_cmp_lt(arr[i], pivot, cfg->order, stats, count_ops)) {
		i++;
	}
	QS_LOOP_PRAGMA
	while (i <= j && !qs_cmp_lt(arr[j], pivot, cfg->order, stats, count_ops)) {
		j--;
	}

	bool already_partitioned = (i > j);

	while (i < j) {
		qs_swap(&arr[i], &arr[j], stats, count_ops);
		i++;
		j--;
		QS_LOOP_PRAGMA
		while (qs_cmp_lt(arr[i], pivot, cfg->order, stats, count_ops)) {
			i++;
		}
		QS_LOOP_PRAGMA
		while (!qs_cmp_lt(arr[j], pivot, cfg->order, stats, count_ops)) {
			j--;
		}
	}

	size_t pivot_pos = i - 1;
	if (pivot_pos != low) {
		qs_swap(&arr[low], &arr[pivot_pos], stats, count_ops);
	}

	size_t left_len = pivot_pos - low;
	size_t right_len = high - pivot_pos;
	bool unbalanced = (left_len < len / 8) || (right_len < len / 8);

	if (unbalanced) {
		stats->bad_partitions++;
		if (stats->bad_partitions > bad_allowed) {
			stats->heapsort_fallbacks++;
			qs_heapsort(arr + low, len, cfg->order, stats, count_ops);
			return (QsPartResult){ 0 };
		}

		if (left_len >= 8) {
			qs_swap(&arr[low], &arr[low + left_len / 4], stats, count_ops);
			qs_swap(&arr[pivot_pos - 1], &arr[pivot_pos - left_len / 4], stats,
				count_ops);
			if (left_len > 64) {
				qs_swap(&arr[low + 1], &arr[low + left_len / 4 + 1], stats,
					count_ops);
				qs_swap(&arr[low + 2], &arr[low + left_len / 4 + 2], stats,
					count_ops);
				qs_swap(&arr[pivot_pos - 2], &arr[pivot_pos - left_len / 4 - 1],
					stats, count_ops);
				qs_swap(&arr[pivot_pos - 3], &arr[pivot_pos - left_len / 4 - 2],
					stats, count_ops);
			}
		}
		if (right_len >= 8) {
			qs_swap(&arr[pivot_pos + 1], &arr[pivot_pos + 1 + right_len / 4], stats,
				count_ops);
			qs_swap(&arr[high], &arr[high - right_len / 4], stats, count_ops);
			if (right_len > 64) {
				qs_swap(&arr[pivot_pos + 2], &arr[pivot_pos + 2 + right_len / 4],
					stats, count_ops);
				qs_swap(&arr[pivot_pos + 3], &arr[pivot_pos + 3 + right_len / 4],
					stats, count_ops);
				qs_swap(&arr[high - 1], &arr[high - right_len / 4 - 1], stats,
					count_ops);
				qs_swap(&arr[high - 2], &arr[high - right_len / 4 - 2], stats,
					count_ops);
			}
		}
	} else if (already_partitioned) {
		bool left_ok = qs_partial_insertion_sort(arr + low, left_len, cfg->order, stats,
							 count_ops);
		bool right_ok = left_ok && qs_partial_insertion_sort(arr + pivot_pos + 1, right_len,
								     cfg->order, stats, count_ops);
		if (left_ok && right_ok) {
			return (QsPartResult){ 0 };
		}
	}

	return (QsPartResult){
		.l1 = low,
		.h1 = pivot_pos > 0 ? pivot_pos - 1 : 0,
		.has_left = (left_len > 1),
		.l2 = pivot_pos + 1,
		.h2 = high,
		.has_right = (right_len > 1),
	};
}

[[gnu::always_inline]] static inline QsPartResult
qs_partition_range(int *arr, size_t low, size_t high, bool leftmost, size_t bad_allowed,
		   const QsConfig *cfg, QsRng *rng, QsRunStats *stats, const bool count_ops)
{
	switch (cfg->partition) {
	case QS_PART_LOMUTO:
		return qs_partition_lomuto(arr, low, high, cfg, rng, stats, count_ops);
	case QS_PART_THREE_WAY:
		return qs_partition_three_way(arr, low, high, cfg, rng, stats, count_ops);
	case QS_PART_PDQ:
		return qs_partition_pdq(arr, low, high, leftmost, bad_allowed, cfg, rng, stats,
					count_ops);
	case QS_PART_HOARE:
	default:
		return qs_partition_hoare(arr, low, high, cfg, rng, stats, count_ops);
	}
}

[[gnu::always_inline]] static inline bool
qs_check_leaf_or_fallback(int *arr, size_t low, size_t high, size_t depth, size_t introsort_limit,
			  const QsConfig *cfg, QsRunStats *stats, const bool count_ops)
{
	if (depth > stats->max_depth_reached) {
		stats->max_depth_reached = depth;
	}
	if (low >= high) {
		return true;
	}

	size_t len = high - low + 1;
	if (cfg->small_sort != QS_SMALL_NONE && cfg->cutoff > 1 && len <= cfg->cutoff) {
		qs_run_small_sort(arr + low, len, cfg->small_sort, cfg->order, stats, count_ops);
		return true;
	}

	if (cfg->max_depth > 0 && depth >= cfg->max_depth) {
		stats->depth_limit_exceeded = true;
		stats->heapsort_fallbacks++;
		qs_heapsort(arr + low, len, cfg->order, stats, count_ops);
		return true;
	}

	if (cfg->introsort_fallback && depth > introsort_limit) {
		stats->heapsort_fallbacks++;
		qs_heapsort(arr + low, len, cfg->order, stats, count_ops);
		return true;
	}

	return false;
}

static void qs_rec_clean(int *arr, size_t low, size_t high, size_t depth, bool leftmost,
			 size_t introsort_limit, size_t bad_allowed, const QsConfig *cfg,
			 QsRng *rng, QsRunStats *stats)
{
	if (qs_check_leaf_or_fallback(arr, low, high, depth, introsort_limit, cfg, stats, false)) {
		return;
	}
	QsPartResult res =
		qs_partition_range(arr, low, high, leftmost, bad_allowed, cfg, rng, stats, false);
	if (res.has_left) {
		qs_rec_clean(arr, res.l1, res.h1, depth + 1, leftmost, introsort_limit, bad_allowed,
			     cfg, rng, stats);
	}
	if (res.has_right) {
		qs_rec_clean(arr, res.l2, res.h2, depth + 1, false, introsort_limit, bad_allowed,
			     cfg, rng, stats);
	}
}

static void qs_rec_counted(int *arr, size_t low, size_t high, size_t depth, bool leftmost,
			   size_t introsort_limit, size_t bad_allowed, const QsConfig *cfg,
			   QsRng *rng, QsRunStats *stats)
{
	if (qs_check_leaf_or_fallback(arr, low, high, depth, introsort_limit, cfg, stats, true)) {
		return;
	}
	QsPartResult res =
		qs_partition_range(arr, low, high, leftmost, bad_allowed, cfg, rng, stats, true);
	if (res.has_left) {
		qs_rec_counted(arr, res.l1, res.h1, depth + 1, leftmost, introsort_limit,
			       bad_allowed, cfg, rng, stats);
	}
	if (res.has_right) {
		qs_rec_counted(arr, res.l2, res.h2, depth + 1, false, introsort_limit, bad_allowed,
			       cfg, rng, stats);
	}
}

static void qs_tail_clean(int *arr, size_t low, size_t high, size_t depth, bool leftmost,
			  size_t introsort_limit, size_t bad_allowed, const QsConfig *cfg,
			  QsRng *rng, QsRunStats *stats)
{
	while (low < high) {
		if (qs_check_leaf_or_fallback(arr, low, high, depth, introsort_limit, cfg, stats,
					      false)) {
			return;
		}
		QsPartResult res = qs_partition_range(arr, low, high, leftmost, bad_allowed, cfg,
						      rng, stats, false);
		depth++;
		if (res.has_left && res.has_right) {
			if (res.h1 - res.l1 < res.h2 - res.l2) {
				qs_tail_clean(arr, res.l1, res.h1, depth, leftmost, introsort_limit,
					      bad_allowed, cfg, rng, stats);
				low = res.l2;
				high = res.h2;
				leftmost = false;
			} else {
				qs_tail_clean(arr, res.l2, res.h2, depth, false, introsort_limit,
					      bad_allowed, cfg, rng, stats);
				low = res.l1;
				high = res.h1;
			}
		} else if (res.has_left) {
			low = res.l1;
			high = res.h1;
		} else if (res.has_right) {
			low = res.l2;
			high = res.h2;
			leftmost = false;
		} else {
			return;
		}
	}
}

static void qs_tail_counted(int *arr, size_t low, size_t high, size_t depth, bool leftmost,
			    size_t introsort_limit, size_t bad_allowed, const QsConfig *cfg,
			    QsRng *rng, QsRunStats *stats)
{
	while (low < high) {
		if (qs_check_leaf_or_fallback(arr, low, high, depth, introsort_limit, cfg, stats,
					      true)) {
			return;
		}
		QsPartResult res = qs_partition_range(arr, low, high, leftmost, bad_allowed, cfg,
						      rng, stats, true);
		depth++;
		if (res.has_left && res.has_right) {
			if (res.h1 - res.l1 < res.h2 - res.l2) {
				qs_tail_counted(arr, res.l1, res.h1, depth, leftmost,
						introsort_limit, bad_allowed, cfg, rng, stats);
				low = res.l2;
				high = res.h2;
				leftmost = false;
			} else {
				qs_tail_counted(arr, res.l2, res.h2, depth, false, introsort_limit,
						bad_allowed, cfg, rng, stats);
				low = res.l1;
				high = res.h1;
			}
		} else if (res.has_left) {
			low = res.l1;
			high = res.h1;
		} else if (res.has_right) {
			low = res.l2;
			high = res.h2;
			leftmost = false;
		} else {
			return;
		}
	}
}

[[gnu::always_inline]] static inline bool
qs_iterative_impl(int *arr, size_t n, size_t introsort_limit, size_t bad_allowed,
		  const QsConfig *cfg, QsRng *rng, QsRunStats *stats, const bool count_ops)
{
	size_t cap = QS_ITER_STACK_INIT_CAP;
	QsStackFrame *stack = calloc(cap, sizeof(*stack));
	if (stack == nullptr) {
		errno = ENOMEM;
		return false;
	}

	size_t sp = 0;
	stack[sp++] = (QsStackFrame){ .low = 0, .high = n - 1, .depth = 0, .leftmost = true };

	while (sp > 0) {
		QsStackFrame frame = stack[--sp];
		size_t low = frame.low;
		size_t high = frame.high;
		size_t depth = frame.depth;
		bool leftmost = frame.leftmost;

		while (low < high) {
			if (qs_check_leaf_or_fallback(arr, low, high, depth, introsort_limit, cfg,
						      stats, count_ops)) {
				break;
			}
			QsPartResult res = qs_partition_range(arr, low, high, leftmost, bad_allowed,
							      cfg, rng, stats, count_ops);
			depth++;
			if (res.has_left && res.has_right) {
				if (sp == cap) {
					size_t new_cap = cap * 2;
					QsStackFrame *grown =
						realloc(stack, new_cap * sizeof(*stack));
					if (grown == nullptr) {
						free(stack);
						errno = ENOMEM;
						return false;
					}
					stack = grown;
					cap = new_cap;
				}
				if (res.h1 - res.l1 < res.h2 - res.l2) {
					stack[sp++] = (QsStackFrame){
						.low = res.l2,
						.high = res.h2,
						.depth = depth,
						.leftmost = false,
					};
					low = res.l1;
					high = res.h1;
				} else {
					stack[sp++] = (QsStackFrame){
						.low = res.l1,
						.high = res.h1,
						.depth = depth,
						.leftmost = leftmost,
					};
					low = res.l2;
					high = res.h2;
					leftmost = false;
				}
			} else if (res.has_left) {
				low = res.l1;
				high = res.h1;
			} else if (res.has_right) {
				low = res.l2;
				high = res.h2;
				leftmost = false;
			} else {
				break;
			}
		}
	}

	free(stack);
	return true;
}

static void qs_parallel_worker(void *arg);

static void qs_parallel_range(QsParallelShared *shared, int *arr, size_t low, size_t high,
			      size_t depth, bool leftmost, QsRng *rng, QsRunStats *stats)
{
	const QsConfig *cfg = shared->cfg;
	const bool count_ops = shared->count_ops;

	while (low < high) {
		bool done = count_ops ? qs_check_leaf_or_fallback(arr, low, high, depth,
								  shared->introsort_limit, cfg,
								  stats, true) :
					qs_check_leaf_or_fallback(arr, low, high, depth,
								  shared->introsort_limit, cfg,
								  stats, false);
		if (done) {
			return;
		}

		QsPartResult res =
			count_ops ? qs_partition_range(arr, low, high, leftmost,
						       shared->bad_allowed, cfg, rng, stats, true) :
				    qs_partition_range(arr, low, high, leftmost,
						       shared->bad_allowed, cfg, rng, stats, false);
		depth++;

		if (res.has_left && res.has_right) {
			size_t len1 = res.h1 - res.l1 + 1;
			size_t len2 = res.h2 - res.l2 + 1;
			bool can_spawn = (cfg->pool != nullptr) &&
					 (depth <= QS_MAX_PARALLEL_DEPTH) &&
					 (len1 >= shared->parallel_threshold) &&
					 (len2 >= shared->parallel_threshold);

			if (can_spawn) {
				size_t idx = atomic_fetch_add_explicit(&shared->task_count, 1,
								       memory_order_relaxed);
				if (idx < QS_MAX_PARALLEL_TASKS) {
					QsParallelTask *task = &shared->tasks[idx];
					task->shared = shared;
					task->arr = arr;
					task->low = res.l1;
					task->high = res.h1;
					task->depth = depth;
					task->leftmost = leftmost;
					qs_rng_seed(&task->rng,
						    cfg->seed ^ ((uint64_t)res.l1 * 0x9e3779b9ULL) ^
							    ((uint64_t)depth << 32));
					memset(&task->stats, 0, sizeof(task->stats));
					if (qs_threadpool_submit(cfg->pool, qs_parallel_worker,
								 task)) {
						low = res.l2;
						high = res.h2;
						leftmost = false;
						continue;
					}
				}
			}

			if (len1 < len2) {
				qs_parallel_range(shared, arr, res.l1, res.h1, depth, leftmost, rng,
						  stats);
				low = res.l2;
				high = res.h2;
				leftmost = false;
			} else {
				qs_parallel_range(shared, arr, res.l2, res.h2, depth, false, rng,
						  stats);
				low = res.l1;
				high = res.h1;
			}
		} else if (res.has_left) {
			low = res.l1;
			high = res.h1;
		} else if (res.has_right) {
			low = res.l2;
			high = res.h2;
			leftmost = false;
		} else {
			return;
		}
	}
}

static void qs_parallel_worker(void *arg)
{
	QsParallelTask *task = (QsParallelTask *)arg;
	qs_parallel_range(task->shared, task->arr, task->low, task->high, task->depth,
			  task->leftmost, &task->rng, &task->stats);
}

static bool qs_run_parallel(int *arr, size_t n, size_t introsort_limit, size_t bad_allowed,
			    const QsConfig *cfg, QsRng *rng, QsRunStats *stats,
			    const bool count_ops)
{
	QsParallelShared *shared = calloc(1, sizeof(*shared));
	if (shared == nullptr) {
		errno = ENOMEM;
		return false;
	}

	shared->cfg = cfg;
	shared->introsort_limit = introsort_limit;
	shared->bad_allowed = bad_allowed;
	shared->parallel_threshold = cfg->parallel_threshold > 0 ? cfg->parallel_threshold :
								   QS_DEFAULT_PARALLEL_THRESHOLD;
	shared->count_ops = count_ops;
	atomic_init(&shared->task_count, 0);

	qs_parallel_range(shared, arr, 0, n - 1, 0, true, rng, stats);

	if (cfg->pool != nullptr) {
		qs_threadpool_wait_all(cfg->pool);
	}

	size_t spawned = atomic_load_explicit(&shared->task_count, memory_order_acquire);
	if (spawned > QS_MAX_PARALLEL_TASKS) {
		spawned = QS_MAX_PARALLEL_TASKS;
	}
	for (size_t i = 0; i < spawned; i++) {
		const QsRunStats *ts = &shared->tasks[i].stats;
		stats->comparisons += ts->comparisons;
		stats->swaps += ts->swaps;
		stats->moves += ts->moves;
		stats->bad_partitions += ts->bad_partitions;
		stats->heapsort_fallbacks += ts->heapsort_fallbacks;
		if (ts->max_depth_reached > stats->max_depth_reached) {
			stats->max_depth_reached = ts->max_depth_reached;
		}
		if (ts->depth_limit_exceeded) {
			stats->depth_limit_exceeded = true;
		}
	}

	free(shared);
	return true;
}

QsConfig qs_config_default(void)
{
	return (QsConfig){
		.partition = QS_PART_HOARE,
		.pivot = QS_PIVOT_MEDIAN3,
		.small_sort = QS_SMALL_INSERTION,
		.exec_mode = QS_EXEC_TAIL_CALL,
		.order = QS_ORDER_ASC,
		.cutoff = 16,
		.max_depth = 0,
		.parallel_threshold = QS_DEFAULT_PARALLEL_THRESHOLD,
		.introsort_fallback = false,
		.seed = 42,
		.pool = nullptr,
	};
}

bool qs_run_clean(int *arr, size_t n, const QsConfig *cfg, QsRunStats *stats)
{
	if (cfg == nullptr || (arr == nullptr && n > 0)) {
		errno = EINVAL;
		return false;
	}

	QsRunStats local_stats = { 0 };
	QsRunStats *st = stats != nullptr ? stats : &local_stats;
	memset(st, 0, sizeof(*st));

	if (n < 2) {
		return true;
	}

	QsRng rng;
	qs_rng_seed(&rng, cfg->seed);

	size_t log_n = qs_floor_log2(n);
	size_t introsort_limit = 2 * log_n;
	size_t bad_allowed = log_n;

	switch (cfg->exec_mode) {
	case QS_EXEC_RECURSIVE:
		qs_rec_clean(arr, 0, n - 1, 0, true, introsort_limit, bad_allowed, cfg, &rng, st);
		return true;
	case QS_EXEC_ITERATIVE:
		return qs_iterative_impl(arr, n, introsort_limit, bad_allowed, cfg, &rng, st,
					 false);
	case QS_EXEC_PARALLEL:
		return qs_run_parallel(arr, n, introsort_limit, bad_allowed, cfg, &rng, st, false);
	case QS_EXEC_TAIL_CALL:
	default:
		qs_tail_clean(arr, 0, n - 1, 0, true, introsort_limit, bad_allowed, cfg, &rng, st);
		return true;
	}
}

bool qs_run_counted(int *arr, size_t n, const QsConfig *cfg, QsRunStats *stats)
{
	if (cfg == nullptr || (arr == nullptr && n > 0)) {
		errno = EINVAL;
		return false;
	}

	QsRunStats local_stats = { 0 };
	QsRunStats *st = stats != nullptr ? stats : &local_stats;
	memset(st, 0, sizeof(*st));

	if (n < 2) {
		return true;
	}

	QsRng rng;
	qs_rng_seed(&rng, cfg->seed);

	size_t log_n = qs_floor_log2(n);
	size_t introsort_limit = 2 * log_n;
	size_t bad_allowed = log_n;

	switch (cfg->exec_mode) {
	case QS_EXEC_RECURSIVE:
		qs_rec_counted(arr, 0, n - 1, 0, true, introsort_limit, bad_allowed, cfg, &rng, st);
		return true;
	case QS_EXEC_ITERATIVE:
		return qs_iterative_impl(arr, n, introsort_limit, bad_allowed, cfg, &rng, st, true);
	case QS_EXEC_PARALLEL:
		return qs_run_parallel(arr, n, introsort_limit, bad_allowed, cfg, &rng, st, true);
	case QS_EXEC_TAIL_CALL:
	default:
		qs_tail_counted(arr, 0, n - 1, 0, true, introsort_limit, bad_allowed, cfg, &rng,
				st);
		return true;
	}
}

const char *qs_partition_name(QsPartition part)
{
	switch (part) {
	case QS_PART_HOARE:
		return "hoare";
	case QS_PART_LOMUTO:
		return "lomuto";
	case QS_PART_THREE_WAY:
		return "three_way";
	case QS_PART_PDQ:
		return "pdq";
	default:
		return "unknown";
	}
}

const char *qs_pivot_name(QsPivot pivot)
{
	switch (pivot) {
	case QS_PIVOT_FIRST:
		return "first";
	case QS_PIVOT_LAST:
		return "last";
	case QS_PIVOT_MIDDLE:
		return "middle";
	case QS_PIVOT_RANDOM:
		return "random";
	case QS_PIVOT_MEDIAN3:
		return "median3";
	case QS_PIVOT_NINTHER:
		return "ninther";
	default:
		return "unknown";
	}
}

const char *qs_small_sort_name(QsSmallSort small)
{
	switch (small) {
	case QS_SMALL_NONE:
		return "none";
	case QS_SMALL_INSERTION:
		return "insertion";
	case QS_SMALL_BINARY_INSERTION:
		return "binary_insertion";
	case QS_SMALL_SHELL:
		return "shell";
	case QS_SMALL_HEAPSORT:
		return "heapsort";
	default:
		return "unknown";
	}
}

const char *qs_exec_mode_name(QsExecMode mode)
{
	switch (mode) {
	case QS_EXEC_RECURSIVE:
		return "recursive";
	case QS_EXEC_TAIL_CALL:
		return "tail_call";
	case QS_EXEC_ITERATIVE:
		return "iterative";
	case QS_EXEC_PARALLEL:
		return "parallel";
	default:
		return "unknown";
	}
}
