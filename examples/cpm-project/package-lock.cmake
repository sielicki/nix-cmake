# CPM Package Lock
# This file should be committed to version control

# Generated from CPM.cmake
# https://github.com/cpm-cmake/CPM.cmake

CPMDeclarePackage(fmt
  VERSION 10.2.1
  GITHUB_REPOSITORY fmtlib/fmt
  EXCLUDE_FROM_ALL YES
)

CPMDeclarePackage(nlohmann_json
  VERSION 3.11.3
  GITHUB_REPOSITORY nlohmann/json
  EXCLUDE_FROM_ALL YES
)

CPMDeclarePackage(Catch2
  VERSION 3.5.2
  GITHUB_REPOSITORY catchorg/Catch2
  EXCLUDE_FROM_ALL YES
)
