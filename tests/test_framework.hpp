#pragma once
// Tiny test framework: TEST(name) { CHECK(cond); CHECK_EQ(a, b); }
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <sstream>
#include <string>
#include <vector>

namespace tf {

struct Case {
  const char* name;
  std::function<void()> fn;
};
inline std::vector<Case>& cases() {
  static std::vector<Case> c;
  return c;
}
inline int& failures() {
  static int f = 0;
  return f;
}
struct Reg {
  Reg(const char* n, std::function<void()> f) { cases().push_back({n, std::move(f)}); }
};
template <class A, class B>
void check_eq(const A& a, const B& b, const char* ea, const char* eb, const char* file, int line) {
  if (!(a == b)) {
    std::ostringstream os;
    os << a << " != " << b;
    std::fprintf(stderr, "  FAIL %s:%d: %s == %s (%s)\n", file, line, ea, eb, os.str().c_str());
    failures()++;
  }
}

}  // namespace tf

#define TEST(name)                                        \
  static void test_##name();                              \
  static tf::Reg reg_##name(#name, test_##name);          \
  static void test_##name()

#define CHECK(cond)                                                                      \
  do {                                                                                   \
    if (!(cond)) {                                                                       \
      std::fprintf(stderr, "  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);            \
      tf::failures()++;                                                                  \
    }                                                                                    \
  } while (0)
#define CHECK_EQ(a, b) tf::check_eq((a), (b), #a, #b, __FILE__, __LINE__)
