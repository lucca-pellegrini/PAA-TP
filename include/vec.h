#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum QsOrder {
	QS_ORDER_ASC = 0,
	QS_ORDER_DESC = 1,
} QsOrder;

typedef struct QsVec {
	int *data;
	size_t len;
	size_t cap;
	uint64_t multiset_hash;
} QsVec;

[[nodiscard]] QsVec *qs_vec_create(size_t len);
void qs_vec_destroy(QsVec *vec);
[[nodiscard]] QsVec *qs_vec_clone(const QsVec *src);
bool qs_vec_copy_data(int *dst, size_t dst_len, const QsVec *src);

[[nodiscard]] uint64_t qs_vec_multiset_hash(const int *arr, size_t n);
void qs_vec_rehash(QsVec *vec);
[[nodiscard]] bool qs_vec_is_sorted(const int *arr, size_t n, QsOrder order);
[[nodiscard]] bool qs_vec_verify(const int *sorted_arr, size_t n, QsOrder order,
				 uint64_t expected_hash);

[[nodiscard]] QsVec *qs_vec_preset_random(size_t n, int min_val, int max_val, uint64_t seed);
[[nodiscard]] QsVec *qs_vec_preset_sorted(size_t n, QsOrder order, int start, int step);
[[nodiscard]] QsVec *qs_vec_preset_reverse(size_t n);
[[nodiscard]] QsVec *qs_vec_preset_repeated(size_t n, size_t unique_values, uint64_t seed);
[[nodiscard]] QsVec *qs_vec_preset_constant(size_t n, int value);
[[nodiscard]] QsVec *qs_vec_preset_organ_pipe(size_t n);
[[nodiscard]] QsVec *qs_vec_preset_sawtooth(size_t n, size_t period, QsOrder order);
[[nodiscard]] QsVec *qs_vec_preset_adversarial_med3(size_t n);

bool qs_vec_partial_sort(QsVec *vec, double factor, QsOrder order, uint64_t seed);
void qs_vec_reverse_in_place(QsVec *vec);
[[nodiscard]] QsVec *qs_vec_reversed(const QsVec *src);
[[nodiscard]] QsVec *qs_vec_concat(const QsVec *a, const QsVec *b);
[[nodiscard]] QsVec *qs_vec_interleave(const QsVec *a, const QsVec *b);
[[nodiscard]] QsVec *qs_vec_blend(const QsVec *a, const QsVec *b, double ratio_a, uint64_t seed);
[[nodiscard]] QsVec *qs_vec_slice(const QsVec *src, size_t start, size_t end);
