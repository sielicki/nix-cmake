# Recursive Dependency Discovery

One of the most powerful features of `nix-cmake` is its ability to perform recursive dependency discovery. 

## The Problem
Many modern C++ projects use a "tree" of dependencies, where the top-level `CMakeLists.txt` uses `FetchContent` to download a library (e.g., Project B), and Project B in turn uses `FetchContent` to download its own dependencies (e.g., Project C). 

In a standard Nix sandbox, these downloads fail because network access is restricted.

## The Solution: Fixed-Output Derivation (FOD)
`nix-cmake` uses a two-pass approach to solve this:

1. **Discovery Pass (FOD)**: `nix-cmake` runs a "guest" CMake configuration in a derivation with `outputHash` (FOD). This pass is allowed to access the network. Our dependency provider hook intercepts every `FetchContent` call and logs the details (URLs, Git repositories, tags) to a structured JSON file.
2. **Nix Library Processing**: Nix reads this log and generates fetchers for each dependency. These sources are then injected into the final build environment.

## Usage

### 1. Perform a Recursive Discovery
In your flake or Nix file, use `recursiveDiscover`:

```nix
discovery = nix-cmake.lib.workspace.recursiveDiscover {
  src = ./.;
  outputHash = "sha256-..."; # Initial hash or dummy
};
```

### 2. Inspect the Discovery Log
The resulting derivation contains a `discovery-log.json`. You can inspect it to see what was found:
```bash
nix build .#discovery
cat result/discovery-log.json
```

### 3. Generate a Package Set
Use `mkProjectOverlay` to create a standard Nixpkgs overlay from the discovery results:

```nix
workspace = nix-cmake.lib.workspace.loadWorkspace {
  src = ./.;
  lockFile = ./cmake-lock.json; # Result of discovery
};

# Extend pkgs with project dependencies
pkgsWithDeps = pkgs.extend workspace.overlay;
```

## Platform-Specific Handling
Recursive discovery often triggers CMake's compiler and linker checks. On platforms like macOS (Darwin), these checks can fail if dependencies like `-lSystem` aren't immediately available in the discovery environment.

`nix-cmake` automatically handles this by:
- Using `CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY` to bypass linker checks.
- Forcing `CMAKE_C_COMPILER_WORKS=1` to allow configuration to proceed to the dependency discovery phase.
