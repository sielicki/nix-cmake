#include <fmt/core.h>

int main() {
    fmt::print("Hello from nix-cmake!\n");
    fmt::print("fmt version: {}.{}.{}\n", FMT_VERSION / 10000, (FMT_VERSION % 10000) / 100,
               FMT_VERSION % 100);
    return 0;
}
