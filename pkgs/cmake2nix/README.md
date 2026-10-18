# cmake2nix (C++23 Implementation)

A meta-circular implementation of cmake2nix written in C++23 using CMake and CPM.

## Meta-Circular Dogfooding

This is cmake2nix eating its own dog food! The tool itself:
- ✅ Is written in C++23
- ✅ Uses CMake as its build system
- ✅ Manages dependencies via CPM.cmake (FetchContent)
- ✅ Can generate its own cmake-lock.json
- ✅ Can generate its own Nix expressions

This demonstrates the complete workflow that cmake2nix enables for C++ projects.

## Dependencies (via CPM)

- **CLI11** (2.6.1) - Command-line argument parsing
- **nlohmann/json** (3.12.0) - JSON parsing and generation
- **fmt** (12.1.0) - Modern C++ formatting

All dependencies are managed declaratively and can be pre-fetched by Nix!

## Building

### With Nix (recommended)
```bash
nix build .#cmake2nix
./result/bin/cmake2nix --help
```

### Traditional CMake
```bash
mkdir build && cd build
cmake -G Ninja ..
ninja
./cmake2nix --help
```

## Generating cmake2nix's Own Lock File

Discovery shells out to Nix and needs `NIX_PATH` entries for
`<nixpkgs>` and `<nix-cmake>` (pointing at a nix-cmake checkout):

```bash
export NIX_PATH="nixpkgs=$(nix eval --raw nixpkgs#path 2>/dev/null || echo /path/to/nixpkgs):nix-cmake=$PWD"
```

To generate cmake2nix's own dependency lock file:

```bash
# Build cmake2nix first
nix build .#cmake2nix

# Use it to discover its own dependencies
./result/bin/cmake2nix discover \
  --input pkgs/cmake2nix/CMakeLists.txt \
  --output pkgs/cmake2nix/cmake-lock.json

# Prefetch hashes
./result/bin/cmake2nix prefetch \
  --lock-file pkgs/cmake2nix/cmake-lock.json

# Generate Nix expressions
./result/bin/cmake2nix generate \
  --lock-file pkgs/cmake2nix/cmake-lock.json \
  --output pkgs/cmake2nix/nix/
```

## Usage

Run `cmake2nix --help`. With no subcommand it performs the full
`discover` + `prefetch` + `generate` workflow. Generated expressions
(`default.nix`, `cmake-env.nix`, `cmake-packages.nix`) use the legacy
`nix-build`/`nix-shell` interface and import `<nix-cmake/lib>` via
`NIX_PATH`.

## Architecture

- `include/cmake2nix.hpp` - Main header with all interfaces
- `src/main.cpp` - CLI entry point using CLI11
- `src/parser.cpp` - CMakeLists.txt parsing
- `src/discovery.cpp` - Dependency discovery via CMake
- `src/lockfile.cpp` - Lock file operations
- `src/prefetcher.cpp` - Hash prefetching via nix-prefetch-*
- `src/generator.cpp` - Nix expression generation
- `src/commands.cpp` - Command implementations

## Why C++23?

1. **Modern C++ features** - Ranges, concepts, modules (future)
2. **Performance** - Faster than shell scripts for complex operations
3. **Type safety** - Catch errors at compile time
4. **Dogfooding** - Demonstrates cmake2nix's capabilities
5. **Self-hosting** - Can bootstrap itself

## Differences from Shell Version

- ✅ Faster execution
- ✅ Better error messages
- ✅ Type-safe JSON handling
- ✅ Structured command parsing
- ✅ Cross-platform (Unix-like systems)
- ❌ Requires C++ compiler (vs. just bash)

## Future Enhancements

- [ ] Parallel hash prefetching
- [ ] Incremental lock file updates
- [ ] Lock file diffing and merging
- [ ] Cache for discovered dependencies
- [ ] Support for private Git repositories
- [ ] Integration with CMake presets
