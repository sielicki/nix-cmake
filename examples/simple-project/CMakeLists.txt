cmake_minimum_required(VERSION 3.24)
project(SimpleProject)

include(FetchContent)

# This will be intercepted and redirected to the pre-fetched version
FetchContent_Declare(
  fmt
  GIT_REPOSITORY https://github.com/fmtlib/fmt.git
  GIT_TAG 10.2.1
)

FetchContent_MakeAvailable(fmt)

add_executable(hello main.cpp)
target_link_libraries(hello PRIVATE fmt::fmt)
