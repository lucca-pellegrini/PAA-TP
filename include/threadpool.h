#pragma once

#include <stddef.h>

typedef struct QsThreadPool QsThreadPool;

typedef void (*QsTaskFn)(void *arg);

bool qs_pin_current_thread(int cpu_id);

[[nodiscard]] QsThreadPool *qs_threadpool_create(size_t num_threads, const int *pin_cpus,
						 size_t num_pin_cpus);
void qs_threadpool_destroy(QsThreadPool *pool);

bool qs_threadpool_submit(QsThreadPool *pool, QsTaskFn fn, void *arg);
void qs_threadpool_wait_all(QsThreadPool *pool);

[[nodiscard]] size_t qs_threadpool_num_threads(const QsThreadPool *pool);
[[nodiscard]] size_t qs_threadpool_pending_tasks(const QsThreadPool *pool);
[[nodiscard]] int qs_threadpool_worker_cpu(const QsThreadPool *pool, size_t worker_idx);
