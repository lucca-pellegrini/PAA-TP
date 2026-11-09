#include "vec.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include "util.h"

static void internal_shell_sort(int *arr, size_t n, QsOrder order)
{
	if (arr == nullptr || n < 2) {
		return;
	}

	size_t gap = 1;
	while (gap < n / 3) {
		gap = gap * 3 + 1;
	}

	while (gap >= 1) {
		for (size_t i = gap; i < n; i++) {
			int v = arr[i];
			size_t j = i;
			if (order == QS_ORDER_ASC) {
				while (j >= gap && arr[j - gap] > v) {
					arr[j] = arr[j - gap];
					j -= gap;
				}
			} else {
				while (j >= gap && arr[j - gap] < v) {
					arr[j] = arr[j - gap];
					j -= gap;
				}
			}
			arr[j] = v;
		}
		gap /= 3;
	}
}

QsVec *qs_vec_create(size_t len)
{
	QsVec *vec = calloc(1, sizeof(*vec));
	ERRNOCHECK(vec == nullptr, ENOMEM, err_out);

	size_t alloc_cap = len > 0 ? len : 1;
	vec->data = calloc(alloc_cap, sizeof(*vec->data));
	ERRNOCHECK(vec->data == nullptr, ENOMEM, err_vec);

	vec->len = len;
	vec->cap = alloc_cap;
	vec->multiset_hash = qs_vec_multiset_hash(vec->data, vec->len);
	return vec;

err_vec:
	free(vec);
err_out:
	return nullptr;
}

void qs_vec_destroy(QsVec *vec)
{
	if (vec == nullptr) {
		return;
	}
	free(vec->data);
	free(vec);
}

QsVec *qs_vec_clone(const QsVec *src)
{
	if (src == nullptr) {
		errno = EINVAL;
		return nullptr;
	}

	QsVec *dst = qs_vec_create(src->len);
	if (dst == nullptr) {
		return nullptr;
	}

	if (src->len > 0) {
		memcpy(dst->data, src->data, src->len * sizeof(*dst->data));
	}
	dst->multiset_hash = src->multiset_hash;
	return dst;
}

bool qs_vec_copy_data(int *dst, size_t dst_len, const QsVec *src)
{
	if (dst == nullptr || src == nullptr || dst_len < src->len) {
		errno = EINVAL;
		return false;
	}
	if (src->len > 0) {
		memcpy(dst, src->data, src->len * sizeof(*dst));
	}
	return true;
}

uint64_t qs_vec_multiset_hash(const int *arr, size_t n)
{
	if (arr == nullptr || n == 0) {
		return 0;
	}

	uint64_t sum = 0;
	uint64_t xor_acc = 0;
	for (size_t i = 0; i < n; i++) {
		uint64_t state = (uint64_t)(uint32_t)arr[i];
		uint64_t mix = qs_splitmix64_next(&state);
		sum += mix;
		xor_acc ^= (mix * 0xbf58476d1ce4e5b9ULL);
	}
	return sum ^ qs_rotl64(xor_acc, 1) ^ (uint64_t)n;
}

void qs_vec_rehash(QsVec *vec)
{
	if (vec == nullptr) {
		return;
	}
	vec->multiset_hash = qs_vec_multiset_hash(vec->data, vec->len);
}

bool qs_vec_is_sorted(const int *arr, size_t n, QsOrder order)
{
	if (arr == nullptr && n > 0) {
		return false;
	}
	if (n < 2) {
		return true;
	}

	if (order == QS_ORDER_ASC) {
		for (size_t i = 1; i < n; i++) {
			if (arr[i - 1] > arr[i]) {
				return false;
			}
		}
	} else {
		for (size_t i = 1; i < n; i++) {
			if (arr[i - 1] < arr[i]) {
				return false;
			}
		}
	}
	return true;
}

bool qs_vec_verify(const int *sorted_arr, size_t n, QsOrder order, uint64_t expected_hash)
{
	if (!qs_vec_is_sorted(sorted_arr, n, order)) {
		return false;
	}
	return qs_vec_multiset_hash(sorted_arr, n) == expected_hash;
}

QsVec *qs_vec_preset_random(size_t n, int min_val, int max_val, uint64_t seed)
{
	QsVec *vec = qs_vec_create(n);
	if (vec == nullptr) {
		return nullptr;
	}

	if (max_val < min_val) {
		int tmp = min_val;
		min_val = max_val;
		max_val = tmp;
	}

	QsRng rng;
	qs_rng_seed(&rng, seed);
	for (size_t i = 0; i < n; i++) {
		vec->data[i] = (int)qs_rng_range(&rng, (int64_t)min_val, (int64_t)max_val);
	}
	qs_vec_rehash(vec);
	return vec;
}

QsVec *qs_vec_preset_sorted(size_t n, QsOrder order, int start, int step)
{
	QsVec *vec = qs_vec_create(n);
	if (vec == nullptr) {
		return nullptr;
	}

	int s = step == 0 ? 1 : step;
	for (size_t i = 0; i < n; i++) {
		size_t idx = (order == QS_ORDER_ASC) ? i : (n - 1 - i);
		vec->data[i] = (int)((int64_t)start + (int64_t)idx * (int64_t)s);
	}
	qs_vec_rehash(vec);
	return vec;
}

QsVec *qs_vec_preset_reverse(size_t n)
{
	QsVec *vec = qs_vec_create(n);
	if (vec == nullptr) {
		return nullptr;
	}

	for (size_t i = 0; i < n; i++) {
		vec->data[i] = (int)(n - i);
	}
	qs_vec_rehash(vec);
	return vec;
}

QsVec *qs_vec_preset_repeated(size_t n, size_t unique_values, uint64_t seed)
{
	QsVec *vec = qs_vec_create(n);
	if (vec == nullptr) {
		return nullptr;
	}

	size_t k = unique_values > 0 ? unique_values : 1;
	QsRng rng;
	qs_rng_seed(&rng, seed);
	for (size_t i = 0; i < n; i++) {
		vec->data[i] = (int)qs_rng_bounded(&rng, (uint64_t)k) + 1;
	}
	qs_vec_rehash(vec);
	return vec;
}

QsVec *qs_vec_preset_constant(size_t n, int value)
{
	QsVec *vec = qs_vec_create(n);
	if (vec == nullptr) {
		return nullptr;
	}

	for (size_t i = 0; i < n; i++) {
		vec->data[i] = value;
	}
	qs_vec_rehash(vec);
	return vec;
}

QsVec *qs_vec_preset_organ_pipe(size_t n)
{
	QsVec *vec = qs_vec_create(n);
	if (vec == nullptr) {
		return nullptr;
	}

	for (size_t i = 0; i < n; i++) {
		size_t mirror = n - 1 - i;
		vec->data[i] = (int)(i < mirror ? i : mirror);
	}
	qs_vec_rehash(vec);
	return vec;
}

QsVec *qs_vec_preset_sawtooth(size_t n, size_t period, QsOrder order)
{
	QsVec *vec = qs_vec_create(n);
	if (vec == nullptr) {
		return nullptr;
	}

	size_t p = period > 0 ? period : 1;
	for (size_t i = 0; i < n; i++) {
		size_t r = i % p;
		vec->data[i] = (int)(order == QS_ORDER_ASC ? r : (p - 1 - r));
	}
	qs_vec_rehash(vec);
	return vec;
}

QsVec *qs_vec_preset_adversarial_med3(size_t n)
{
	QsVec *vec = qs_vec_create(n);
	if (vec == nullptr) {
		return nullptr;
	}

	for (size_t i = 0; i < n; i++) {
		vec->data[i] = (int)(i + 1);
	}
	if (n >= 3) {
		for (size_t i = n - 2; i > 0; i--) {
			size_t prev = i - 1;
			size_t mid = prev + (n - 1 - prev) / 2;
			int tmp = vec->data[i];
			vec->data[i] = vec->data[mid];
			vec->data[mid] = tmp;
		}
	}
	qs_vec_rehash(vec);
	return vec;
}

bool qs_vec_partial_sort(QsVec *vec, double factor, QsOrder order, uint64_t seed)
{
	if (vec == nullptr) {
		errno = EINVAL;
		return false;
	}
	if (vec->len < 2) {
		return true;
	}

	internal_shell_sort(vec->data, vec->len, order);
	if (factor >= 1.0) {
		return true;
	}

	QsRng rng;
	qs_rng_seed(&rng, seed);

	if (factor <= 0.0) {
		for (size_t i = vec->len - 1; i > 0; i--) {
			size_t j = (size_t)qs_rng_bounded(&rng, (uint64_t)(i + 1));
			int tmp = vec->data[i];
			vec->data[i] = vec->data[j];
			vec->data[j] = tmp;
		}
		return true;
	}

	double disorder = 1.0 - factor;
	size_t swaps = (size_t)(disorder * (double)(vec->len / 2));
	if (swaps == 0 && disorder > 0.0) {
		swaps = 1;
	}
	for (size_t k = 0; k < swaps; k++) {
		size_t i = (size_t)qs_rng_bounded(&rng, (uint64_t)vec->len);
		size_t j = (size_t)qs_rng_bounded(&rng, (uint64_t)vec->len);
		int tmp = vec->data[i];
		vec->data[i] = vec->data[j];
		vec->data[j] = tmp;
	}
	return true;
}

void qs_vec_reverse_in_place(QsVec *vec)
{
	if (vec == nullptr || vec->len < 2) {
		return;
	}

	for (size_t i = 0; i < vec->len / 2; i++) {
		size_t j = vec->len - 1 - i;
		int tmp = vec->data[i];
		vec->data[i] = vec->data[j];
		vec->data[j] = tmp;
	}
}

QsVec *qs_vec_reversed(const QsVec *src)
{
	QsVec *dst = qs_vec_clone(src);
	if (dst == nullptr) {
		return nullptr;
	}
	qs_vec_reverse_in_place(dst);
	return dst;
}

QsVec *qs_vec_concat(const QsVec *a, const QsVec *b)
{
	if (a == nullptr || b == nullptr) {
		errno = EINVAL;
		return nullptr;
	}

	QsVec *dst = qs_vec_create(a->len + b->len);
	if (dst == nullptr) {
		return nullptr;
	}

	if (a->len > 0) {
		memcpy(dst->data, a->data, a->len * sizeof(*dst->data));
	}
	if (b->len > 0) {
		memcpy(dst->data + a->len, b->data, b->len * sizeof(*dst->data));
	}
	qs_vec_rehash(dst);
	return dst;
}

QsVec *qs_vec_interleave(const QsVec *a, const QsVec *b)
{
	if (a == nullptr || b == nullptr) {
		errno = EINVAL;
		return nullptr;
	}

	QsVec *dst = qs_vec_create(a->len + b->len);
	if (dst == nullptr) {
		return nullptr;
	}

	size_t ia = 0;
	size_t ib = 0;
	size_t out = 0;
	while (ia < a->len && ib < b->len) {
		dst->data[out++] = a->data[ia++];
		dst->data[out++] = b->data[ib++];
	}
	while (ia < a->len) {
		dst->data[out++] = a->data[ia++];
	}
	while (ib < b->len) {
		dst->data[out++] = b->data[ib++];
	}
	qs_vec_rehash(dst);
	return dst;
}

QsVec *qs_vec_blend(const QsVec *a, const QsVec *b, double ratio_a, uint64_t seed)
{
	if (a == nullptr || b == nullptr) {
		errno = EINVAL;
		return nullptr;
	}

	QsVec *dst = qs_vec_create(a->len + b->len);
	if (dst == nullptr) {
		return nullptr;
	}

	double p = ratio_a;
	if (p < 0.0) {
		p = 0.0;
	} else if (p > 1.0) {
		p = 1.0;
	}

	QsRng rng;
	qs_rng_seed(&rng, seed);

	size_t ia = 0;
	size_t ib = 0;
	size_t out = 0;
	while (ia < a->len && ib < b->len) {
		if (qs_rng_uniform01(&rng) < p) {
			dst->data[out++] = a->data[ia++];
		} else {
			dst->data[out++] = b->data[ib++];
		}
	}
	while (ia < a->len) {
		dst->data[out++] = a->data[ia++];
	}
	while (ib < b->len) {
		dst->data[out++] = b->data[ib++];
	}
	qs_vec_rehash(dst);
	return dst;
}

QsVec *qs_vec_slice(const QsVec *src, size_t start, size_t end)
{
	if (src == nullptr) {
		errno = EINVAL;
		return nullptr;
	}

	size_t s = start > src->len ? src->len : start;
	size_t e = end > src->len ? src->len : end;
	if (e < s) {
		e = s;
	}

	size_t slice_len = e - s;
	QsVec *dst = qs_vec_create(slice_len);
	if (dst == nullptr) {
		return nullptr;
	}

	if (slice_len > 0) {
		memcpy(dst->data, src->data + s, slice_len * sizeof(*dst->data));
	}
	qs_vec_rehash(dst);
	return dst;
}
