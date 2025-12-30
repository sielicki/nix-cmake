#include "cmake2nix.hpp"

#include <fstream>
#include <regex>
#include <sstream>

namespace cmake2nix::parser {

ProjectInfo parse_cmake_lists(const fs::path& path) {
    std::ifstream file(path);
    if (!file) {
        throw std::runtime_error("Failed to open " + path.string());
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string content = buffer.str();

    ProjectInfo info;
    info.pname = extract_project_name(content).value_or("cmake-project");
    info.version = extract_version(content).value_or("0.1.0");

    return info;
}

std::optional<std::string> extract_project_name(const std::string& content) {
    // Match: project(name ...)
    std::regex project_regex(R"(project\s*\(\s*(\w+))");
    std::smatch match;

    if (std::regex_search(content, match, project_regex)) {
        return match[1].str();
    }

    return std::nullopt;
}

std::optional<std::string> extract_version(const std::string& content) {
    // Match: VERSION x.y.z in project() call
    std::regex version_regex(R"(VERSION\s+([0-9]+\.[0-9]+(?:\.[0-9]+)?))");
    std::smatch match;

    if (std::regex_search(content, match, version_regex)) {
        return match[1].str();
    }

    return std::nullopt;
}

} // namespace cmake2nix::parser
