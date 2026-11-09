#include "threadpool.h"
#include "util.h"

#include <sched.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <threads.h>

constexpr size_t QS_TASK_QUEUE_CAP = 8192;

typedef struct {
	QsTaskFn fn;
	void *arg;
} QsTask;

typedef struct {
	QsThreadPool *pool;
	thrd_t thread;
	int cpu_id;
	bool started;
} QsWorker;

struct QsThreadPool {
	QsWorker *workers;
	size_t num_threads;
	QsTask *queue;
	size_t cap;
	size_t head;
	size_t tail;
	size_t count;
	atomic_size_t pending;
	atomic_size_t in_flight;
	mtx_t mtx;
	cnd_t work_cv;
	cnd_t done_cv;
	bool stop;
};

bool qs_pin_current_thread(int cpu_id)
{
	if (cpu_id < 0 || cpu_id >= CPU_SETSIZE) {
		return false;
	}
	cpu_set_t cpuset;
	CPU_ZERO(&cpuset);
	CPU_SET((size_t)cpu_id, &cpuset);
	return sched_setaffinity(0, sizeof(cpu_set_t), &cpuset) == 0;
}

static bool pop_task_locked(QsThreadPool *pool, QsTask *out)
{
	if (pool->count == 0) {
		return false;
	}
	*out = pool->queue[pool->head];
	pool->head = (pool->head + 1) % pool->cap;
	pool->count--;
	atomic_store_explicit(&pool->pending, pool->count, memory_order_relaxed);
	return true;
}

static void finish_task(QsThreadPool *pool)
{
	if (atomic_fetch_sub_explicit(&pool->in_flight, 1, memory_order_acq_rel) == 1) {
		mtx_lock(&pool->mtx);
		cnd_broadcast(&pool->done_cv);
		mtx_unlock(&pool->mtx);
	}
}

static int worker_main(void *arg)
{
	QsWorker *worker = (QsWorker *)arg;
	QsThreadPool *pool = worker->pool;

	if (worker->cpu_id >= 0) {
		(void)qs_pin_current_thread(worker->cpu_id);
	}

	for (;;) {
		QsTask task = { 0 };
		mtx_lock(&pool->mtx);
		while (pool->count == 0 && !pool->stop) {
			cnd_wait(&pool->work_cv, &pool->mtx);
		}
		if (pool->count == 0 && pool->stop) {
			mtx_unlock(&pool->mtx);
			break;
		}
		(void)pop_task_locked(pool, &task);
		mtx_unlock(&pool->mtx);

		task.fn(task.arg);
		finish_task(pool);
	}
	return 0;
}

QsThreadPool *qs_threadpool_create(size_t num_threads, const int *pin_cpus, size_t num_pin_cpus)
{
	ERRNOCHECK(num_threads == 0, EINVAL, err_null);

	QsThreadPool *pool = calloc(1, sizeof(*pool));
	ERRNOCHECK(pool == nullptr, ENOMEM, err_null);

	pool->num_threads = num_threads;
	pool->cap = QS_TASK_QUEUE_CAP;
	pool->workers = calloc(num_threads, sizeof(*pool->workers));
	ERRNOCHECK(pool->workers == nullptr, ENOMEM, err_pool);

	pool->queue = calloc(pool->cap, sizeof(*pool->queue));
	ERRNOCHECK(pool->queue == nullptr, ENOMEM, err_workers);

	ERRNOCHECK(mtx_init(&pool->mtx, mtx_plain) != thrd_success, EAGAIN, err_queue);
	ERRNOCHECK(cnd_init(&pool->work_cv) != thrd_success, EAGAIN, err_mtx);
	ERRNOCHECK(cnd_init(&pool->done_cv) != thrd_success, EAGAIN, err_work_cv);

	for (size_t i = 0; i < num_threads; i++) {
		pool->workers[i].pool = pool;
		pool->workers[i].cpu_id =
			(pin_cpus != nullptr && num_pin_cpus > 0) ? pin_cpus[i % num_pin_cpus] : -1;
		if (thrd_create(&pool->workers[i].thread, worker_main, &pool->workers[i]) !=
		    thrd_success) {
			errno = EAGAIN;
			goto err_threads;
		}
		pool->workers[i].started = true;
	}

	return pool;

err_threads:
	mtx_lock(&pool->mtx);
	pool->stop = true;
	cnd_broadcast(&pool->work_cv);
	mtx_unlock(&pool->mtx);
	for (size_t i = 0; i < num_threads; i++) {
		if (pool->workers[i].started) {
			thrd_join(pool->workers[i].thread, nullptr);
		}
	}
	cnd_destroy(&pool->done_cv);
err_work_cv:
	cnd_destroy(&pool->work_cv);
err_mtx:
	mtx_destroy(&pool->mtx);
err_queue:
	free(pool->queue);
err_workers:
	free(pool->workers);
err_pool:
	free(pool);
err_null:
	return nullptr;
}

void qs_threadpool_destroy(QsThreadPool *pool)
{
	if (pool == nullptr) {
		return;
	}

	qs_threadpool_wait_all(pool);

	mtx_lock(&pool->mtx);
	pool->stop = true;
	cnd_broadcast(&pool->work_cv);
	mtx_unlock(&pool->mtx);

	for (size_t i = 0; i < pool->num_threads; i++) {
		if (pool->workers[i].started) {
			thrd_join(pool->workers[i].thread, nullptr);
		}
	}

	cnd_destroy(&pool->done_cv);
	cnd_destroy(&pool->work_cv);
	mtx_destroy(&pool->mtx);
	free(pool->queue);
	free(pool->workers);
	free(pool);
}

bool qs_threadpool_submit(QsThreadPool *pool, QsTaskFn fn, void *arg)
{
	if (fn == nullptr) {
		return false;
	}
	if (pool == nullptr) {
		fn(arg);
		return true;
	}

	mtx_lock(&pool->mtx);
	if (pool->stop) {
		mtx_unlock(&pool->mtx);
		return false;
	}

	atomic_fetch_add_explicit(&pool->in_flight, 1, memory_order_release);

	if (pool->count < pool->cap) {
		pool->queue[pool->tail] = (QsTask){ .fn = fn, .arg = arg };
		pool->tail = (pool->tail + 1) % pool->cap;
		pool->count++;
		atomic_store_explicit(&pool->pending, pool->count, memory_order_relaxed);
		cnd_signal(&pool->work_cv);
		cnd_broadcast(&pool->done_cv);
		mtx_unlock(&pool->mtx);
		return true;
	}

	mtx_unlock(&pool->mtx);
	fn(arg);
	finish_task(pool);
	return true;
}

void qs_threadpool_wait_all(QsThreadPool *pool)
{
	if (pool == nullptr) {
		return;
	}

	mtx_lock(&pool->mtx);
	while (atomic_load_explicit(&pool->in_flight, memory_order_acquire) > 0) {
		QsTask task = { 0 };
		if (pop_task_locked(pool, &task)) {
			mtx_unlock(&pool->mtx);
			task.fn(task.arg);
			finish_task(pool);
			mtx_lock(&pool->mtx);
		} else {
			cnd_wait(&pool->done_cv, &pool->mtx);
		}
	}
	mtx_unlock(&pool->mtx);
}

size_t qs_threadpool_num_threads(const QsThreadPool *pool)
{
	return pool != nullptr ? pool->num_threads : 0;
}

size_t qs_threadpool_pending_tasks(const QsThreadPool *pool)
{
	return pool != nullptr ? atomic_load_explicit(&pool->pending, memory_order_relaxed) : 0;
}

int qs_threadpool_worker_cpu(const QsThreadPool *pool, size_t worker_idx)
{
	if (pool == nullptr || worker_idx >= pool->num_threads) {
		return -1;
	}
	return pool->workers[worker_idx].cpu_id;
}
