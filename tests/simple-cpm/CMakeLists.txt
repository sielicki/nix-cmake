cmake_minimum_required(VERSION 3.24)
project(SimpleCPMTest)

# Check if CPM_SOURCE_DIR is provided by Nix, otherwise fetch it
if(DEFINED ENV{CPM_SOURCE_DIR})
  set(CPM_SOURCE_DIR "$ENV{CPM_SOURCE_DIR}")
  message(STATUS "Using Nix-provided CPM.cmake from: ${CPM_SOURCE_DIR}")
else()
  include(FetchContent)
  # Download CPM.cmake
  FetchContent_Declare(
    CPM
    URL https://github.com/cpm-cmake/CPM.cmake/releases/download/v0.40.2/CPM.cmake
  )
  FetchContent_MakeAvailable(CPM)
endif()

include(${CPM_SOURCE_DIR}/CPM.cmake)

# This should be intercepted by cmakeDependencyHook
CPMAddPackage(
  NAME fmt
  GITHUB_REPOSITORY fmtlib/fmt
  GIT_TAG 10.2.1
)

add_executable(test_cpm main.cpp)
target_link_libraries(test_cpm PRIVATE fmt::fmt)
