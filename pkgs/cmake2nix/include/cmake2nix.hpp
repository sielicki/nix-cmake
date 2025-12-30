#pragma once

#include <filesystem>
#include <nlohmann/json.hpp>
#include <optional>
#include <string>
#include <vector>

namespace cmake2nix {

namespace fs = std::filesystem;
using json = nlohmann::json;

// Configuration for cmake2nix operations
struct Config {
    fs::path input_file = "CMakeLists.txt";
    fs::path lock_file = "cmake-lock.json";
    fs::path output_dir = ".";
    std::string packages_nix = "cmake-packages.nix";
    std::string env_nix = "cmake-env.nix";
    std::string composition_nix = "default.nix";
    std::vector<std::string> cmake_flags;
    bool recursive = false;
    bool no_prefetch = false;
    bool verbose = false;
};

// Represents a dependency from discovery
struct Dependency {
    std::string name;
    std::string version;
    std::string method; // fetchFromGitHub, fetchgit, fetchurl
    json args;          // Method-specific arguments
    json metadata;      // Additional metadata
};

// Lock file structure
struct LockFile {
    std::string version = "1.0";
    std::map<std::string, Dependency> dependencies;

    json to_json() const;
    static LockFile from_json(const json& j);
};

// Project information extracted from CMakeLists.txt
struct ProjectInfo {
    std::string pname;
    std::string version;
};

// Discovery - Run CMake to discover dependencies
namespace discovery {
std::vector<Dependency> run(const Config& config);
fs::path create_discovery_derivation(const Config& config);
std::vector<Dependency> parse_discovery_log(const fs::path& log_file);
} // namespace discovery

// Lock file operations
namespace lockfile {
LockFile load(const fs::path& path);
void save(const LockFile& lock, const fs::path& path);
LockFile merge(const LockFile& old_lock, const std::vector<Dependency>& new_deps);
} // namespace lockfile

// Prefetching - Fetch actual hashes for dependencies
namespace prefetcher {
void prefetch_all(LockFile& lock, bool verbose = false);
std::string prefetch_github(const std::string& owner, const std::string& repo,
                            const std::string& rev);
std::string prefetch_git(const std::string& url, const std::string& rev);
std::string prefetch_url(const std::string& url);
} // namespace prefetcher

// Generator - Generate Nix expressions
namespace generator {
std::string generate_packages_nix(const LockFile& lock);
std::string generate_env_nix(const std::string& nix_cmake_path);
std::string generate_default_nix(const ProjectInfo& info);
void write_all(const Config& config, const LockFile& lock, const ProjectInfo& info);
} // namespace generator

// Parser - Parse CMakeLists.txt
namespace parser {
ProjectInfo parse_cmake_lists(const fs::path& path);
std::optional<std::string> extract_project_name(const std::string& content);
std::optional<std::string> extract_version(const std::string& content);
} // namespace parser

// Commands
namespace commands {
void discover(const Config& config);
void prefetch(const Config& config);
void generate(const Config& config);
void lock(const Config& config);
void init(const fs::path& dir);
void shell(const Config& config);
void build(const Config& config);
} // namespace commands

} // namespace cmake2nix
