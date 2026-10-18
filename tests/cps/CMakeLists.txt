cmake_minimum_required(VERSION 4.0)
project(CpsConsumptionTest CXX)

# Only spdlog is requested explicitly. Its CPS description requires
# fmt, which CMake must resolve transitively (also via CPS).
find_package(spdlog 1 REQUIRED)

if(NOT spdlog_DIR MATCHES "/cps/")
  message(FATAL_ERROR "spdlog was not loaded via CPS (spdlog_DIR=${spdlog_DIR})")
endif()
message(STATUS "spdlog via CPS: ${spdlog_DIR}")
message(STATUS "fmt_DIR=${fmt_DIR}")

add_executable(cps_app main.cpp)
target_link_libraries(cps_app PRIVATE spdlog::spdlog)
install(TARGETS cps_app RUNTIME DESTINATION bin)
