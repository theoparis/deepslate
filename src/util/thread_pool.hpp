#pragma once
// Priority thread pool. Lower priority value runs first; ties are FIFO.
#include <condition_variable>
#include <functional>
#include <queue>
#include <thread>

#include "util/common.hpp"

namespace ds {

class ThreadPool {
 public:
  explicit ThreadPool(unsigned n) {
    if (n == 0) n = 1;
    for (unsigned i = 0; i < n; i++) workers_.emplace_back([this, i](std::stop_token st) { run(st, i); });
  }
  ~ThreadPool() {
    {
      std::lock_guard lk(m_);
      stopping_ = true;
    }
    cv_.notify_all();
    for (auto& w : workers_) w.request_stop();
    workers_.clear();  // joins
  }
  ThreadPool(const ThreadPool&) = delete;
  ThreadPool& operator=(const ThreadPool&) = delete;

  void submit(int priority, std::function<void()> fn) {
    {
      std::lock_guard lk(m_);
      q_.push(Job{priority, seq_++, std::move(fn)});
    }
    cv_.notify_one();
  }
  size_t pending() const {
    std::lock_guard lk(m_);
    return q_.size();
  }
  size_t size() const { return workers_.size(); }

 private:
  struct Job {
    int prio;
    u64 seq;
    std::function<void()> fn;
    bool operator<(const Job& o) const { return prio != o.prio ? prio > o.prio : seq > o.seq; }
  };
  void run(std::stop_token, unsigned) {
    for (;;) {
      Job j;
      {
        std::unique_lock lk(m_);
        cv_.wait(lk, [&] { return stopping_ || !q_.empty(); });
        if (stopping_ && q_.empty()) return;
        if (stopping_) return;
        j = std::move(const_cast<Job&>(q_.top()));
        q_.pop();
      }
      j.fn();
    }
  }
  mutable std::mutex m_;
  std::condition_variable cv_;
  std::priority_queue<Job> q_;
  u64 seq_ = 0;
  bool stopping_ = false;
  std::vector<std::jthread> workers_;
};

}  // namespace ds
