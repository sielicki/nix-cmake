cmake_minimum_required(VERSION 3.24)
project(cmake2nix VERSION 0.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Use FetchContent for dependency management (works with nix-cmake!)
# In a normal build, CPM would download these, but with nix-cmake,
# the dependency provider intercepts FetchContent and provides pre-fetched sources
include(FetchContent)

# Dependencies - these will be provided by Nix via FETCHCONTENT_SOURCE_DIR_*
FetchContent_Declare(
  CLI11
  GIT_REPOSITORY https://github.com/CLIUtils/CLI11.git
  GIT_TAG v2.6.1
)

FetchContent_Declare(
  nlohmann_json
  GIT_REPOSITORY https://github.com/nlohmann/json.git
  GIT_TAG v3.12.0
)

FetchContent_Declare(
  fmt
  GIT_REPOSITORY https://github.com/fmtlib/fmt.git
  GIT_TAG 12.1.0
)

# Make dependencies available
set(CLI11_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(CLI11_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
set(FMT_INSTALL OFF CACHE BOOL "" FORCE)  # Don't install fmt, we only need to link it

FetchContent_MakeAvailable(CLI11 nlohmann_json fmt)

# Main executable
add_executable(cmake2nix
  src/main.cpp
  src/discovery.cpp
  src/lockfile.cpp
  src/generator.cpp
  src/prefetcher.cpp
  src/parser.cpp
  src/commands.cpp
)

target_link_libraries(cmake2nix PRIVATE
  CLI11::CLI11
  nlohmann_json::nlohmann_json
  fmt::fmt
)

target_include_directories(cmake2nix PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Enable warnings
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  target_compile_options(cmake2nix PRIVATE
    -Wall -Wextra -Wpedantic
  )
elseif(CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
  target_compile_options(cmake2nix PRIVATE /W4)
endif()

# Installation - use bin directory, GNUInstallDirs is included via NixGNUInstallDirs.cmake in toolchain
install(TARGETS cmake2nix
  RUNTIME DESTINATION bin
)

# Generate our own lock file during build (meta!)
add_custom_target(generate-lockfile
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/cmake2nix discover
    --input ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt
    --output ${CMAKE_CURRENT_SOURCE_DIR}/cmake-lock.json
  DEPENDS cmake2nix
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  COMMENT "Generating cmake2nix's own lock file (meta-circular!)"
)
