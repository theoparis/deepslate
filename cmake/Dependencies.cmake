# Third-party dependencies.
#
# By default every dependency is fetched with FetchContent (pinned tags).
# With -DDEEPSLATE_SYSTEM_DEPS=ON, find_package()/pkg-config is used instead.
# In either mode a dependency that cannot be obtained one way falls back to the
# other (system -> fetch, fetch -> system) before failing.

include(FetchContent)
set(FETCHCONTENT_QUIET OFF)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)

find_package(Threads REQUIRED)
find_package(PkgConfig QUIET)

# ---------------------------------------------------------------- zlib-ng
# Built in zlib-compat mode so that LevelDB, libarchive and curl all link the
# same implementation (target `zlib`, header <zlib.h>).
function(ds_dep_zlib)
  if(DEEPSLATE_SYSTEM_DEPS)
    find_package(ZLIB QUIET)
    if(ZLIB_FOUND)
      add_library(ds_zlib INTERFACE)
      target_link_libraries(ds_zlib INTERFACE ZLIB::ZLIB)
      set(DS_ZLIB_SYSTEM ON PARENT_SCOPE)
      return()
    endif()
  endif()
  set(ZLIB_COMPAT ON CACHE BOOL "" FORCE)
  set(ZLIB_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
  set(ZLIBNG_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
  set(WITH_GTEST OFF CACHE BOOL "" FORCE)
  set(WITH_FUZZERS OFF CACHE BOOL "" FORCE)
  set(WITH_BENCHMARKS OFF CACHE BOOL "" FORCE)
  set(INSTALL_UTILS OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(zlib-ng
    GIT_REPOSITORY https://github.com/zlib-ng/zlib-ng.git
    GIT_TAG 2.3.3 GIT_SHALLOW ON)
  FetchContent_MakeAvailable(zlib-ng)
  # LevelDB and libarchive link a target/library called `zlib`.
  if(NOT TARGET zlib)
    add_library(zlib INTERFACE)
    target_link_libraries(zlib INTERFACE zlib-ng)
    target_include_directories(zlib INTERFACE ${zlib-ng_SOURCE_DIR} ${zlib-ng_BINARY_DIR})
  endif()
  # FindZLIB (used by curl/libarchive) skips creating ZLIB::ZLIB when it already exists.
  add_library(ZLIB::ZLIB ALIAS zlib-ng)
  add_library(ds_zlib INTERFACE)
  target_link_libraries(ds_zlib INTERFACE zlib)
  # Let find_package(ZLIB) consumers (libarchive, curl) resolve to zlib-ng.
  set(ZLIB_INCLUDE_DIR "${zlib-ng_BINARY_DIR}" CACHE PATH "" FORCE)
  set(ZLIB_LIBRARY zlib CACHE STRING "" FORCE)
  set(ZLIB_FOUND ON CACHE BOOL "" FORCE)
  set(HAVE_ZLIB ON CACHE BOOL "" FORCE)
endfunction()
ds_dep_zlib()

# ---------------------------------------------------------------- LevelDB
# Fork of Mojang's LevelDB (raw-deflate block compression, as used by Bedrock).
set(LEVELDB_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LEVELDB_BUILD_BENCHMARKS OFF CACHE BOOL "" FORCE)
set(LEVELDB_INSTALL OFF CACHE BOOL "" FORCE)
# The fork's CMake probes for system libraries; pin the answers so the build
# is reproducible and links only the zlib-ng we provide.
set(HAVE_CRC32C OFF CACHE BOOL "" FORCE)
set(HAVE_SNAPPY OFF CACHE BOOL "" FORCE)
set(HAVE_ZSTD OFF CACHE BOOL "" FORCE)
set(HAVE_TCMALLOC OFF CACHE BOOL "" FORCE)
# Avoid the fork's PUBLIC -Werror.
set(HAVE_CLANG_THREAD_SAFETY OFF CACHE BOOL "" FORCE)
set(LEVELDB_DISABLE_RTTI ON CACHE BOOL "" FORCE)
if(DS_ZLIB_SYSTEM)
  # The fork links a target literally called `zlib`.
  add_library(zlib INTERFACE)
  target_link_libraries(zlib INTERFACE ZLIB::ZLIB)
endif()
FetchContent_Declare(leveldb
  GIT_REPOSITORY https://github.com/theoparis/leveldb.git
  GIT_TAG main GIT_SHALLOW ON)
FetchContent_MakeAvailable(leveldb)

# ---------------------------------------------------------------- simdjson
if(DEEPSLATE_SYSTEM_DEPS)
  find_package(simdjson QUIET)
endif()
if(NOT TARGET simdjson::simdjson)
  set(SIMDJSON_DEVELOPER_MODE OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(simdjson
    GIT_REPOSITORY https://github.com/simdjson/simdjson.git
    GIT_TAG v5.0.1 GIT_SHALLOW ON)
  FetchContent_MakeAvailable(simdjson)
endif()

# ---------------------------------------------------------------- Eigen
if(DEEPSLATE_SYSTEM_DEPS)
  find_package(Eigen3 3.4 QUIET NO_MODULE)
endif()
if(NOT TARGET Eigen3::Eigen)
  set(EIGEN_BUILD_DOC OFF CACHE BOOL "" FORCE)
  set(EIGEN_BUILD_TESTING OFF CACHE BOOL "" FORCE)
  set(EIGEN_BUILD_PKGCONFIG OFF CACHE BOOL "" FORCE)
  set(EIGEN_BUILD_BLAS OFF CACHE BOOL "" FORCE)
  set(EIGEN_BUILD_LAPACK OFF CACHE BOOL "" FORCE)
  set(EIGEN_BUILD_CMAKE_PACKAGE OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(eigen
    GIT_REPOSITORY https://gitlab.com/libeigen/eigen.git
    GIT_TAG 5.0.1 GIT_SHALLOW ON)
  FetchContent_MakeAvailable(eigen)
endif()

# ---------------------------------------------------------------- FastNoise2
if(DEEPSLATE_SYSTEM_DEPS)
  find_package(FastNoise2 QUIET)
endif()
if(NOT TARGET FastNoise2::FastNoise AND NOT TARGET FastNoise)
  set(FASTNOISE2_NOISETOOL OFF CACHE BOOL "" FORCE)
  set(FASTNOISE2_TESTS OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(FastNoise2
    GIT_REPOSITORY https://github.com/Auburn/FastNoise2.git
    GIT_TAG v1.1.1 GIT_SHALLOW ON)
  FetchContent_MakeAvailable(FastNoise2)
endif()
if(TARGET FastNoise2::FastNoise)
  set(DS_FASTNOISE_TARGET FastNoise2::FastNoise)
else()
  set(DS_FASTNOISE_TARGET FastNoise)
endif()

# ---------------------------------------------------------------- libarchive
function(ds_dep_libarchive)
  if(DEEPSLATE_SYSTEM_DEPS)
    find_package(LibArchive QUIET)
    if(LibArchive_FOUND)
      add_library(ds_archive INTERFACE)
      target_link_libraries(ds_archive INTERFACE LibArchive::LibArchive)
      return()
    endif()
  endif()
  foreach(o TEST TAR CPIO CAT UNZIP OPENSSL LIBB2 LZ4 LZO LZMA ZSTD BZip2 LIBXML2 EXPAT
            PCREPOSIX PCRE2POSIX ICONV ACL XATTR CNG MBEDTLS NETTLE)
    set(ENABLE_${o} OFF CACHE BOOL "" FORCE)
  endforeach()
  set(ENABLE_ZLIB ON CACHE BOOL "" FORCE)
  set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
  set(ENABLE_WERROR OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(libarchive
    GIT_REPOSITORY https://github.com/libarchive/libarchive.git
    GIT_TAG v3.8.9 GIT_SHALLOW ON)
  FetchContent_MakeAvailable(libarchive)
  add_library(ds_archive INTERFACE)
  target_link_libraries(ds_archive INTERFACE archive_static)
  target_include_directories(ds_archive INTERFACE ${libarchive_SOURCE_DIR}/libarchive)
endfunction()
ds_dep_libarchive()

# ---------------------------------------------------------------- curl
function(ds_dep_curl)
  if(DEEPSLATE_SYSTEM_DEPS)
    find_package(CURL QUIET)
    if(CURL_FOUND)
      add_library(ds_curl INTERFACE)
      target_link_libraries(ds_curl INTERFACE CURL::libcurl)
      return()
    endif()
  endif()
  set(BUILD_CURL_EXE OFF CACHE BOOL "" FORCE)
  set(CURL_ENABLE_EXPORT_TARGET OFF CACHE BOOL "" FORCE)
  set(BUILD_LIBCURL_DOCS OFF CACHE BOOL "" FORCE)
  set(BUILD_MISC_DOCS OFF CACHE BOOL "" FORCE)
  set(ENABLE_CURL_MANUAL OFF CACHE BOOL "" FORCE)
  set(CURL_USE_LIBPSL OFF CACHE BOOL "" FORCE)
  set(CURL_USE_LIBSSH2 OFF CACHE BOOL "" FORCE)
  set(CURL_USE_LIBSSH OFF CACHE BOOL "" FORCE)
  set(USE_LIBIDN2 OFF CACHE BOOL "" FORCE)
  set(USE_NGHTTP2 OFF CACHE BOOL "" FORCE)
  set(CURL_DISABLE_LDAP ON CACHE BOOL "" FORCE)
  set(CURL_DISABLE_TESTS ON CACHE BOOL "" FORCE)
  set(CURL_ZSTD OFF CACHE BOOL "" FORCE)
  set(CURL_BROTLI OFF CACHE BOOL "" FORCE)
  set(CURL_USE_OPENSSL ON CACHE BOOL "" FORCE)
  set(HTTP_ONLY ON CACHE BOOL "" FORCE)
  FetchContent_Declare(curl
    GIT_REPOSITORY https://github.com/curl/curl.git
    GIT_TAG curl-8_22_0 GIT_SHALLOW ON)
  FetchContent_MakeAvailable(curl)
  add_library(ds_curl INTERFACE)
  target_link_libraries(ds_curl INTERFACE libcurl_static)
endfunction()
ds_dep_curl()

# ---------------------------------------------------------------- SDL3
if(DEEPSLATE_SYSTEM_DEPS)
  find_package(SDL3 QUIET)
endif()
if(NOT TARGET SDL3::SDL3)
  set(SDL_SHARED OFF CACHE BOOL "" FORCE)
  set(SDL_STATIC ON CACHE BOOL "" FORCE)
  set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
  set(SDL_TESTS OFF CACHE BOOL "" FORCE)
  set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
  set(SDL_DISABLE_INSTALL_DOCS ON CACHE BOOL "" FORCE)
  set(SDL_X11_XTEST OFF CACHE BOOL "" FORCE)  # only used for screensaver inhibition
  FetchContent_Declare(SDL3
    GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
    GIT_TAG release-3.4.16 GIT_SHALLOW ON)
  FetchContent_MakeAvailable(SDL3)
endif()

# ---------------------------------------------------------------- stb
FetchContent_Declare(stb
  GIT_REPOSITORY https://github.com/nothings/stb.git
  GIT_TAG 2c980bb59875b0d32144a71867fbdebb2f77cd20)
FetchContent_GetProperties(stb)
if(NOT stb_POPULATED)
  FetchContent_Populate(stb)
endif()
add_library(ds_stb INTERFACE)
target_include_directories(ds_stb SYSTEM INTERFACE ${stb_SOURCE_DIR})
