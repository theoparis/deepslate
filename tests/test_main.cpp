#include <cstring>

#include "test_framework.hpp"

int main(int argc, char** argv) {
  const char* filter = argc > 1 ? argv[1] : nullptr;
  int ran = 0, failed_cases = 0;
  for (auto& c : tf::cases()) {
    if (filter && !std::strstr(c.name, filter)) continue;
    int before = tf::failures();
    std::fprintf(stderr, "[ RUN  ] %s\n", c.name);
    c.fn();
    ran++;
    if (tf::failures() != before) { failed_cases++; std::fprintf(stderr, "[ FAIL ] %s\n", c.name); }
    else std::fprintf(stderr, "[  OK  ] %s\n", c.name);
  }
  std::fprintf(stderr, "%d tests run, %d failed\n", ran, failed_cases);
  return failed_cases ? 1 : 0;
}
