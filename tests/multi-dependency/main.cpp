#include <catch2/catch_test_macros.hpp>
#include <fmt/core.h>
#include <nlohmann/json.hpp>

TEST_CASE("fmt works", "[fmt]") {
    std::string result = fmt::format("Hello {}", "world");
    REQUIRE(result == "Hello world");
}

TEST_CASE("nlohmann_json works", "[json]") {
    nlohmann::json j = {{"test", true}, {"value", 42}};
    REQUIRE(j["test"] == true);
    REQUIRE(j["value"] == 42);
}

TEST_CASE("All dependencies loaded", "[integration]") {
    nlohmann::json j = {{"status", "success"}};
    std::string msg = fmt::format("Multi-dependency test: {}", j["status"].get<std::string>());
    REQUIRE(msg == "Multi-dependency test: success");
}
