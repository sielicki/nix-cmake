#include <fmt/core.h>
#include <iostream>

int main() {
    fmt::print("Hello from CPM-managed fmt library!\n");
    fmt::print("CPM interception test: {}\n", "PASSED");
    return 0;
}
