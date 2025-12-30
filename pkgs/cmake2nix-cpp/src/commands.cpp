#include "cmake2nix.hpp"
#include <fmt/core.h>
#include <fstream>

namespace cmake2nix::commands {

void discover(const Config& config) {
    auto deps = discovery::run(config);

    // Load existing lock file if it exists
    LockFile lock;
    if (fs::exists(config.lock_file)) {
        lock = lockfile::load(config.lock_file);
        lock = lockfile::merge(lock, deps);
    } else {
        lock.dependencies.clear();
        for (const auto& dep : deps) {
            lock.dependencies[dep.name] = dep;
        }
    }

    lockfile::save(lock, config.lock_file);

    if (!config.no_prefetch) {
        fmt::print("cmake2nix: ⚠️  Lock file contains placeholder hashes\n");
        fmt::print("cmake2nix: Run 'cmake2nix prefetch' to fetch real hashes\n");
    }
}

void prefetch(const Config& config) {
    auto lock = lockfile::load(config.lock_file);
    prefetcher::prefetch_all(lock, config.verbose);
    lockfile::save(lock, config.lock_file);
}

void generate(const Config& config) {
    auto lock = lockfile::load(config.lock_file);
    auto info = parser::parse_cmake_lists(config.input_file);

    fmt::print("cmake2nix: Generating Nix expressions for {} v{}\n",
              info.pname, info.version);

    generator::write_all(config, lock, info);
}

void lock(const Config& config) {
    discover(config);
    if (!config.no_prefetch) {
        prefetch(config);
    }
}

void init(const fs::path& dir) {
    fs::create_directories(dir);

    fmt::print("cmake2nix: Scaffolding project in {}\n", dir.string());

    // Create CMakeLists.txt
    {
        auto path = dir / "CMakeLists.txt";
        std::ofstream file(path);
        file << R"(cmake_minimum_required(VERSION 3.24)
project(my-nix-project VERSION 0.1.0)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(app main.cpp)
)";
    }

    // Create main.cpp
    {
        auto path = dir / "main.cpp";
        std::ofstream file(path);
        file << R"(#include <iostream>

int main() {
    std::cout << "Hello from nix-cmake!" << std::endl;
    return 0;
}
)";
    }

    fmt::print("cmake2nix: ✓ Project initialized\n");
    fmt::print("cmake2nix: Run 'cmake2nix' to generate Nix expressions\n");
}

void shell(const Config& config) {
    auto composition = config.output_dir / config.composition_nix;

    if (!fs::exists(composition)) {
        throw std::runtime_error(
            "Composition file not found: " + composition.string() +
            "\nRun 'cmake2nix generate' first"
        );
    }

    std::string cmd = fmt::format("nix-shell {} -A shell", composition.string());
    std::system(cmd.c_str());
}

void build(const Config& config) {
    auto composition = config.output_dir / config.composition_nix;

    if (!fs::exists(composition)) {
        throw std::runtime_error(
            "Composition file not found: " + composition.string() +
            "\nRun 'cmake2nix generate' first"
        );
    }

    std::string cmd = fmt::format("nix-build {} -A package", composition.string());
    std::system(cmd.c_str());
}

} // namespace cmake2nix::commands
