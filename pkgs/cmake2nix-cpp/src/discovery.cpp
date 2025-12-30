#include "cmake2nix.hpp"

#include <array>
#include <cstdlib>
#include <fmt/core.h>
#include <fstream>
#include <memory>
#include <regex>

namespace cmake2nix::discovery {

namespace {
std::string exec_command(const std::string& cmd) {
    std::array<char, 128> buffer;
    std::string result;
    std::unique_ptr<FILE, decltype(&pclose)> pipe(popen(cmd.c_str(), "r"), pclose);

    if (!pipe) {
        throw std::runtime_error("popen() failed!");
    }

    while (fgets(buffer.data(), buffer.size(), pipe.get()) != nullptr) {
        result += buffer.data();
    }

    return result;
}
} // namespace

std::vector<Dependency> run(const Config& config) {
    fmt::print("cmake2nix: Discovering dependencies from {}\n", config.input_file.string());

    // Create discovery derivation path
    auto discovery_path = create_discovery_derivation(config);

    // Parse discovery log
    auto log_file = discovery_path / "discovery-log.json";
    if (!fs::exists(log_file)) {
        throw std::runtime_error("Discovery log not found: " + log_file.string());
    }

    return parse_discovery_log(log_file);
}

fs::path create_discovery_derivation(const Config& config) {
    fmt::print("cmake2nix: Creating discovery derivation...\n");

    // Build nix expression for discovery
    std::string nix_expr = R"(
let
  pkgs = import <nixpkgs> {};
  nix-cmake = pkgs.callPackage <nix-cmake> {};
  workspace = nix-cmake.workspace pkgs;
in
workspace.discoverDependencies {
  src = )" + config.input_file.parent_path().string() +
                           R"(;
  cmakeFlags = [)";

    for (const auto& flag : config.cmake_flags) {
        nix_expr += " \"" + flag + "\"";
    }

    if (config.recursive) {
        nix_expr += " \"-DNIX_CMAKE_RECURSIVE_DISCOVERY=1\"";
    }

    nix_expr += " ];\n}\n";

    // Write to temp file
    auto temp_file = fs::temp_directory_path() / "cmake2nix-discovery.nix";
    std::ofstream out(temp_file);
    out << nix_expr;
    out.close();

    // Build derivation
    std::string cmd = fmt::format("nix-build --no-out-link {} 2>&1", temp_file.string());
    std::string output = exec_command(cmd);

    // Extract output path from nix-build output
    // The last line should be the store path
    size_t last_newline = output.find_last_of('\n', output.size() - 2);
    std::string store_path = output.substr(last_newline + 1);

    // Trim whitespace
    store_path.erase(0, store_path.find_first_not_of(" \t\n\r"));
    store_path.erase(store_path.find_last_not_of(" \t\n\r") + 1);

    fs::remove(temp_file);

    fmt::print("cmake2nix: Discovery complete: {}\n", store_path);
    return fs::path(store_path);
}

std::vector<Dependency> parse_discovery_log(const fs::path& log_file) {
    std::vector<Dependency> deps;
    std::ifstream file(log_file);

    if (!file) {
        return deps;
    }

    std::string line;
    while (std::getline(file, line)) {
        if (line.empty())
            continue;

        try {
            json j = json::parse(line);

            Dependency dep;
            dep.name = j.value("name", "");
            dep.version = j.value("version", "unknown");

            // Determine fetcher method from metadata
            if (j.contains("gitRepository")) {
                std::string repo = j["gitRepository"];

                // Check if it's a GitHub URL
                std::regex github_regex(R"(https?://github\.com/([^/]+)/([^/\.]+))");
                std::smatch match;

                if (std::regex_search(repo, match, github_regex)) {
                    dep.method = "fetchFromGitHub";
                    dep.args["owner"] = match[1].str();
                    dep.args["repo"] = match[2].str();
                    dep.args["rev"] = j.value("gitTag", "HEAD");
                    dep.args["hash"] = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
                } else {
                    dep.method = "fetchgit";
                    dep.args["url"] = repo;
                    dep.args["rev"] = j.value("gitTag", "HEAD");
                    dep.args["sha256"] = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
                }

                // Store metadata
                dep.metadata = j;
            }

            if (!dep.name.empty()) {
                deps.push_back(dep);
            }
        } catch (const json::exception& e) {
            fmt::print(stderr, "Warning: Failed to parse discovery log line: {}\n", e.what());
        }
    }

    fmt::print("cmake2nix: Discovered {} dependencies\n", deps.size());
    return deps;
}

} // namespace cmake2nix::discovery
