cmake_minimum_required(VERSION 3.24)
project(SimpleFetchContentTest)

include(FetchContent)

# This should be intercepted by cmakeDependencyHook
FetchContent_Declare(
  fmt
  GIT_REPOSITORY https://github.com/fmtlib/fmt.git
  GIT_TAG 10.2.1
)

FetchContent_MakeAvailable(fmt)

add_executable(test_fmt main.cpp)
target_link_libraries(test_fmt PRIVATE fmt::fmt)
