cmake_minimum_required(VERSION 3.24)
project(DynamicFetchContentTest)

include(FetchContent)

# Discovered at build time by the dynamic-derivation producer; the generated
# build derivation provides this from cmake-lock.json via
# FETCHCONTENT_SOURCE_DIR_FMT.
FetchContent_Declare(
  fmt
  GIT_REPOSITORY https://github.com/fmtlib/fmt.git
  GIT_TAG 10.2.1
)

FetchContent_MakeAvailable(fmt)

add_executable(test_fmt main.cpp)
target_link_libraries(test_fmt PRIVATE fmt::fmt)

install(TARGETS test_fmt RUNTIME DESTINATION bin)
