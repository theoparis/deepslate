cmake_minimum_required(VERSION 3.25)
project(deepslate_edition VERSION 0.1.0 LANGUAGES C CXX)

if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  message(FATAL_ERROR "Deepslate Edition is built with LLVM/Clang (use the CMake presets or -DCMAKE_CXX_COMPILER=clang++).")
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Always link with LLD.
add_link_options(-fuse-ld=lld)

option(DEEPSLATE_SYSTEM_DEPS "Use system packages instead of FetchContent" OFF)
option(DEEPSLATE_BUILD_TESTS "Build the test suite" ON)
option(DEEPSLATE_NATIVE "Tune for the host CPU (-march=native)" OFF)
set(DEEPSLATE_SANITIZE "" CACHE STRING "Sanitizers for the game code only, e.g. address,undefined or thread")

# Project-wide options (interface target so third-party code is unaffected).
add_library(ds_options INTERFACE)
if("cxx_std_26" IN_LIST CMAKE_CXX_COMPILE_FEATURES)
  target_compile_features(ds_options INTERFACE cxx_std_26)
else()
  # Older CMake/Clang only know the C++26 working-draft spelling.
  target_compile_options(ds_options INTERFACE $<$<COMPILE_LANGUAGE:CXX>:-std=c++2c>)
endif()
target_compile_options(ds_options INTERFACE -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers)
if(DEEPSLATE_NATIVE)
  target_compile_options(ds_options INTERFACE -march=native)
endif()
if(DEEPSLATE_SANITIZE)
  target_compile_options(ds_options INTERFACE -fsanitize=${DEEPSLATE_SANITIZE} -fno-omit-frame-pointer -g)
  target_link_options(ds_options INTERFACE -fsanitize=${DEEPSLATE_SANITIZE})
  if(DEEPSLATE_SANITIZE MATCHES "undefined")
    # LevelDB is built without RTTI, so the vptr check cannot see its type info.
    target_compile_options(ds_options INTERFACE -fno-sanitize=vptr)
    target_link_options(ds_options INTERFACE -fno-sanitize=vptr)
  endif()
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
include(Dependencies)

add_subdirectory(src)
if(DEEPSLATE_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()
