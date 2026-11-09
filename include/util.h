#pragma once

#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define ERRNOCHECK(cond, val, label) \
	do {                         \
		if (cond) {          \
			errno = val; \
			goto label;  \
		}                    \
	} while (0)

typedef struct {
	uint64_t s[4];
} QsRng;

static inline uint64_t qs_rotl64(uint64_t x, int k)
{
	return (x << k) | (x >> (64 - k));
}

static inline uint64_t qs_splitmix64_next(uint64_t *state)
{
	uint64_t z = (*state += 0x9e3779b97f4a7c15ULL);
	z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
	z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
	return z ^ (z >> 31);
}

static inline void qs_rng_seed(QsRng *rng, uint64_t seed)
{
	uint64_t sm = seed;
	rng->s[0] = qs_splitmix64_next(&sm);
	rng->s[1] = qs_splitmix64_next(&sm);
	rng->s[2] = qs_splitmix64_next(&sm);
	rng->s[3] = qs_splitmix64_next(&sm);
}

static inline uint64_t qs_rng_next_u64(QsRng *rng)
{
	const uint64_t result = qs_rotl64(rng->s[1] * 5ULL, 7) * 9ULL;
	const uint64_t t = rng->s[1] << 17;

	rng->s[2] ^= rng->s[0];
	rng->s[3] ^= rng->s[1];
	rng->s[1] ^= rng->s[2];
	rng->s[0] ^= rng->s[3];

	rng->s[2] ^= t;
	rng->s[3] = qs_rotl64(rng->s[3], 45);

	return result;
}

static inline uint64_t qs_rng_bounded(QsRng *rng, uint64_t bound)
{
	if (bound <= 1) {
		return 0;
	}
	const uint64_t threshold = (0ULL - bound) % bound;
	for (;;) {
		uint64_t r = qs_rng_next_u64(rng);
		if (r >= threshold) {
			return r % bound;
		}
	}
}

static inline int64_t qs_rng_range(QsRng *rng, int64_t min_val, int64_t max_val)
{
	if (max_val <= min_val) {
		return min_val;
	}
	uint64_t span = (uint64_t)max_val - (uint64_t)min_val;
	if (span == UINT64_MAX) {
		return (int64_t)qs_rng_next_u64(rng);
	}
	return (int64_t)((uint64_t)min_val + qs_rng_bounded(rng, span + 1ULL));
}

static inline double qs_rng_uniform01(QsRng *rng)
{
	return (double)(qs_rng_next_u64(rng) >> 11) * 0x1.0p-53;
}

constexpr uint64_t QS_FNV1A_OFFSET = 14695981039346656037ULL;
constexpr uint64_t QS_FNV1A_PRIME = 1099511628211ULL;

static inline uint64_t qs_hash_bytes(const void *data, size_t len, uint64_t basis)
{
	const uint8_t *bytes = (const uint8_t *)data;
	uint64_t h = basis ? basis : QS_FNV1A_OFFSET;
	for (size_t i = 0; i < len; i++) {
		h ^= (uint64_t)bytes[i];
		h *= QS_FNV1A_PRIME;
	}
	return h;
}

static inline uint64_t qs_hash_str(const char *s, uint64_t basis)
{
	if (s == nullptr) {
		return basis ? basis : QS_FNV1A_OFFSET;
	}
	return qs_hash_bytes(s, strlen(s), basis);
}

static inline uint64_t qs_monotonic_ns(void)
{
	struct timespec ts = { 0 };
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}
