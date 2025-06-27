# Simple Project Example

This example demonstrates the clean ergonomics of nix-cmake, similar to uv2nix.

## Project Structure

```
.
├── flake.nix           # Nix flake (no manual dependencies!)
├── cmake-lock.json     # Lock file with pinned dependency versions
├── CMakeLists.txt      # Standard CMake project
└── main.cpp            # Source code
```

## Workflow

### 1. Initial Setup

Add dependencies to your `CMakeLists.txt` as usual:

```cmake
FetchContent_Declare(
  fmt
  GIT_REPOSITORY https://github.com/fmtlib/fmt.git
  GIT_TAG 10.2.1
)
FetchContent_MakeAvailable(fmt)
```

### 2. Generate Lock File

Run discovery to generate `cmake-lock.json`:

```bash
nix run .#discovery
cmake2nix lock
```

This discovers all FetchContent dependencies and their exact versions.

### 3. Build

Just build! All dependencies are automatically fetched from the lock file:

```bash
nix build
```

### 4. Develop

Enter a dev shell with all dependencies available:

```bash
nix develop
```

## Key Features

- **No manual dependency specification** - Just use FetchContent as normal
- **Automatic lock file** - Exact versions pinned automatically
- **Clean flake.nix** - No fetchFromGitHub, no manual hashes
- **Standard CMake** - Works with any CMake project using FetchContent

## Comparison with Manual Approach

**Before (manual):**
```nix
let
  fmt = pkgs.fetchFromGitHub {
    owner = "fmtlib";
    repo = "fmt";
    rev = "10.2.1";
    hash = "sha256-...";  # Manual hash lookup!
  };
in buildPackage {
  fetchContentDeps = { inherit fmt; };  # Manual wiring!
}
```

**After (nix-cmake):**
```nix
let
  workspace = nix-cmake.lib.workspace pkgs {
    workspaceRoot = ./.;  # Reads cmake-lock.json automatically
  };
in {
  packages.default = workspace.buildPackage {
    pname = "my-project";
    version = "0.1.0";
  };
}
```

Clean, simple, automatic!
