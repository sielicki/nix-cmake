#include "cmake2nix.hpp"

#include <CLI/CLI.hpp>
#include <fmt/core.h>
#include <iostream>

using namespace cmake2nix;

int main(int argc, char** argv) {
    CLI::App app{"cmake2nix - Generate Nix expressions for CMake projects"};
    app.require_subcommand(0, 1);

    Config config;

    // Global options
    app.add_option("-i,--input", config.input_file, "CMakeLists.txt location")
        ->check(CLI::ExistingFile);
    app.add_option("-l,--lock-file", config.lock_file, "Lock file location");
    app.add_option("-o,--output", config.output_dir, "Output directory");
    app.add_option("--packages-nix", config.packages_nix, "Packages file name");
    app.add_option("--env-nix", config.env_nix, "Environment file name");
    app.add_option("--composition", config.composition_nix, "Composition file name");
    app.add_option("--cmake-flags", config.cmake_flags, "CMake flags for discovery");
    app.add_flag("--recursive", config.recursive, "Enable recursive discovery");
    app.add_flag("--no-prefetch", config.no_prefetch, "Skip hash prefetching");
    app.add_flag("-v,--verbose", config.verbose, "Verbose output");

    // Subcommands
    auto* discover_cmd = app.add_subcommand("discover", "Discover dependencies by running CMake");
    discover_cmd->callback([&]() { commands::discover(config); });

    auto* prefetch_cmd =
        app.add_subcommand("prefetch", "Prefetch hashes for dependencies in lock file");
    prefetch_cmd->callback([&]() { commands::prefetch(config); });

    auto* generate_cmd = app.add_subcommand("generate", "Generate Nix expressions from lock file");
    generate_cmd->callback([&]() { commands::generate(config); });

    auto* lock_cmd = app.add_subcommand("lock", "Update lock file (discover + prefetch)");
    lock_cmd->callback([&]() { commands::lock(config); });

    auto* init_cmd = app.add_subcommand("init", "Scaffold a new nix-cmake project");
    std::string init_dir = ".";
    init_cmd->add_option("directory", init_dir, "Project directory");
    init_cmd->callback([&]() { commands::init(init_dir); });

    auto* shell_cmd = app.add_subcommand("shell", "Enter development shell");
    shell_cmd->callback([&]() { commands::shell(config); });

    auto* build_cmd = app.add_subcommand("build", "Build the project");
    build_cmd->callback([&]() { commands::build(config); });

    // Default command (no subcommand): full workflow
    app.callback([&]() {
        if (app.get_subcommands().empty()) {
            // Full workflow: discover + prefetch + generate
            fmt::print("cmake2nix: Running full workflow (discover + prefetch + generate)\n");
            commands::discover(config);
            if (!config.no_prefetch) {
                commands::prefetch(config);
            }
            commands::generate(config);
        }
    });

    try {
        app.parse(argc, argv);
    } catch (const CLI::ParseError& e) {
        return app.exit(e);
    } catch (const std::exception& e) {
        fmt::print(stderr, "Error: {}\n", e.what());
        return 1;
    }

    return 0;
}
