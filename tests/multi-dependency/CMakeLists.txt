cmake_minimum_required(VERSION 3.24)
project(MultiDependencyTest)

include(FetchContent)

# Multiple dependencies that should all be intercepted
FetchContent_Declare(
  fmt
  GIT_REPOSITORY https://github.com/fmtlib/fmt.git
  GIT_TAG 10.2.1
)

FetchContent_Declare(
  nlohmann_json
  GIT_REPOSITORY https://github.com/nlohmann/json.git
  GIT_TAG v3.11.3
)

FetchContent_Declare(
  Catch2
  GIT_REPOSITORY https://github.com/catchorg/Catch2.git
  GIT_TAG v3.5.2
)

FetchContent_MakeAvailable(fmt nlohmann_json Catch2)

add_executable(test_multi main.cpp)
target_link_libraries(test_multi PRIVATE
  fmt::fmt
  nlohmann_json::nlohmann_json
  Catch2::Catch2WithMain
)
