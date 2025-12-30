#include "cmake2nix.hpp"

#include <fmt/core.h>
#include <fstream>

namespace cmake2nix {

json LockFile::to_json() const {
    json j;
    j["version"] = version;

    json deps_json = json::object();
    for (const auto& [name, dep] : dependencies) {
        json dep_json;
        dep_json["name"] = dep.name;
        dep_json["version"] = dep.version;
        dep_json["method"] = dep.method;
        dep_json["args"] = dep.args;
        dep_json["metadata"] = dep.metadata;
        deps_json[name] = dep_json;
    }
    j["dependencies"] = deps_json;

    return j;
}

LockFile LockFile::from_json(const json& j) {
    LockFile lock;
    lock.version = j.value("version", "1.0");

    if (j.contains("dependencies")) {
        for (const auto& [name, dep_json] : j["dependencies"].items()) {
            Dependency dep;
            dep.name = dep_json.value("name", name);
            dep.version = dep_json.value("version", "unknown");
            dep.method = dep_json.value("method", "");
            dep.args = dep_json.value("args", json::object());
            dep.metadata = dep_json.value("metadata", json::object());
            lock.dependencies[name] = dep;
        }
    }

    return lock;
}

} // namespace cmake2nix

namespace cmake2nix::lockfile {

LockFile load(const fs::path& path) {
    if (!fs::exists(path)) {
        throw std::runtime_error("Lock file not found: " + path.string());
    }

    std::ifstream file(path);
    if (!file) {
        throw std::runtime_error("Failed to open lock file: " + path.string());
    }

    json j;
    file >> j;

    return LockFile::from_json(j);
}

void save(const LockFile& lock, const fs::path& path) {
    std::ofstream file(path);
    if (!file) {
        throw std::runtime_error("Failed to write lock file: " + path.string());
    }

    json j = lock.to_json();
    file << j.dump(2) << "\n";

    fmt::print("cmake2nix: Lock file saved: {}\n", path.string());
}

LockFile merge(const LockFile& old_lock, const std::vector<Dependency>& new_deps) {
    LockFile merged = old_lock;

    // Add or update dependencies
    for (const auto& dep : new_deps) {
        auto it = merged.dependencies.find(dep.name);
        if (it != merged.dependencies.end()) {
            // Preserve existing hash if version matches
            if (it->second.version == dep.version) {
                // Keep old args (which may have real hash)
                // Only update if new dep has a hash
                if (dep.args.contains("hash") || dep.args.contains("sha256")) {
                    it->second = dep;
                }
                continue;
            }
        }
        // New dependency or version changed
        merged.dependencies[dep.name] = dep;
    }

    return merged;
}

} // namespace cmake2nix::lockfile
