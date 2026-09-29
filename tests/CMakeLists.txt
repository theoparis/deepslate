add_executable(deepslate_tests test_main.cpp test_format.cpp test_game.cpp)
target_link_libraries(deepslate_tests PRIVATE deepslate_core)
add_test(NAME unit COMMAND deepslate_tests)

# End-to-end smoke tests drive the real game under a virtual X server with software GL.
find_program(XVFB_RUN xvfb-run)
if(XVFB_RUN)
  add_test(NAME smoke_gameplay_and_persistence
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/smoke.sh $<TARGET_FILE:deepslate> ${CMAKE_CURRENT_BINARY_DIR}/smoke-world)
  set_tests_properties(smoke_gameplay_and_persistence PROPERTIES TIMEOUT 600)
else()
  message(STATUS "xvfb-run not found: skipping smoke tests")
endif()
