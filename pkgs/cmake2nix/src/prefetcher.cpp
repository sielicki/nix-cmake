#include "cmake2nix.hpp"

#include <array>
#include <fmt/core.h>
#include <memory>
#include <regex>

namespace cmake2nix::prefetcher {

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

std::string extract_hash(const std::string& output) {
    // Look for sha256- prefixed hash
    std::regex hash_regex(R"(sha256-[A-Za-z0-9+/=]+)");
    std::smatch match;

    if (std::regex_search(output, match, hash_regex)) {
        return match[0].str();
    }

    return "";
}
} // namespace

void prefetch_all(LockFile& lock, bool verbose) {
    fmt::print("cmake2nix: Prefetching {} dependencies...\n", lock.dependencies.size());

    int prefetched = 0;
    for (auto& [name, dep] : lock.dependencies) {
        // Skip if already has a non-placeholder hash
        if (dep.args.contains("hash")) {
            std::string hash = dep.args["hash"];
            if (hash != "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=") {
                if (verbose) {
                    fmt::print("  {} already has hash, skipping\n", name);
                }
                continue;
            }
        }

        try {
            std::string hash;

            if (dep.method == "fetchFromGitHub") {
                std::string owner = dep.args["owner"];
                std::string repo = dep.args["repo"];
                std::string rev = dep.args["rev"];
                hash = prefetch_github(owner, repo, rev);
                dep.args["hash"] = hash;
            } else if (dep.method == "fetchgit") {
                std::string url = dep.args["url"];
                std::string rev = dep.args.value("rev", "HEAD");
                hash = prefetch_git(url, rev);
                dep.args["sha256"] = hash;
            } else if (dep.method == "fetchurl") {
                std::string url = dep.args["url"];
                hash = prefetch_url(url);
                dep.args["sha256"] = hash;
            }

            if (!hash.empty()) {
                fmt::print("  ✓ {} ({})\n", name, hash.substr(0, 16) + "...");
                prefetched++;
            }
        } catch (const std::exception& e) {
            fmt::print(stderr, "  ✗ {} failed: {}\n", name, e.what());
        }
    }

    fmt::print("cmake2nix: Prefetched {}/{} dependencies\n", prefetched, lock.dependencies.size());
}

std::string prefetch_github(const std::string& owner, const std::string& repo,
                            const std::string& rev) {
    std::string cmd = fmt::format("nix-prefetch-github {} {} --rev {} 2>&1", owner, repo, rev);
    std::string output = exec_command(cmd);

    // nix-prefetch-github outputs JSON
    try {
        json j = json::parse(output);
        if (j.contains("hash")) {
            return j["hash"];
        }
    } catch (...) {
        // Fall back to hash extraction from output
    }

    std::string hash = extract_hash(output);
    if (hash.empty()) {
        throw std::runtime_error("Failed to extract hash from nix-prefetch-github output");
    }

    return hash;
}

std::string prefetch_git(const std::string& url, const std::string& rev) {
    std::string cmd = fmt::format("nix-prefetch-git --url {} --rev {} 2>&1", url, rev);
    std::string output = exec_command(cmd);

    // nix-prefetch-git outputs JSON
    try {
        json j = json::parse(output);
        if (j.contains("sha256")) {
            return "sha256-" + std::string(j["sha256"]);
        }
    } catch (...) {
        // Fall back to hash extraction
    }

    std::string hash = extract_hash(output);
    if (hash.empty()) {
        throw std::runtime_error("Failed to extract hash from nix-prefetch-git output");
    }

    return hash;
}

std::string prefetch_url(const std::string& url) {
    std::string cmd = fmt::format("nix-prefetch-url {} 2>&1", url);
    std::string output = exec_command(cmd);

    std::string hash = extract_hash(output);
    if (hash.empty()) {
        throw std::runtime_error("Failed to extract hash from nix-prefetch-url output");
    }

    return hash;
}

} // namespace cmake2nix::prefetcher
