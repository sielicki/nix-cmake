# nix-cmake Design Document

## Vision

Create a **crane/uv2nix-style declarative CMake dependency manager for Nix** that makes packaging CMake projects as ergonomic as packaging Rust (crane) or Python (uv2nix) projects.

## Core Philosophy

Inspired by [crane](https://crane.dev/) and [uv2nix](https://pyproject-nix.github.io/uv2nix/):

1. **Lock file driven** - Like `Cargo.lock` or `uv.lock`, we consume existing CMake ecosystem lock files
2. **Composable API** - Small, reusable functions that build on each other
3. **Minimal configuration** - Automatic discovery and sensible defaults
4. **Incremental builds** - Separate dependency building from project code
5. **Pure Nix** - All logic in Nix; no external tools required for evaluation
6. **Upstream compatibility** - Work with unmodified CMake projects
7. **Zero-Patch Philosophy** - Use unpatched Kitware CMake with declarative toolchains
8. **File API Driven** - Use the CMake File API for robust target discovery

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     User-Facing API Layer                    │
│  lib.workspace.loadWorkspace, buildCMakeApplication, etc.   │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                   Lock File Processing                       │
│   Parse CMakeLists.txt, CPM lock files, generate deps       │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                  Overlay/Scope Generation                    │
│    mkCMakeOverlay - translate deps to Nix derivations       │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                  Low-Level Build Hooks                       │
│   cmakeDependencyHook, cmakeToolchainHook (IMPLEMENTED)     │
└─────────────────────────────────────────────────────────────┘
```

## Design Patterns from crane

### 1. Composable Functions

**crane pattern:**
```nix
# Build dependencies separately for caching
cargoArtifacts = crane.buildDepsOnly { ... };

# Build the actual package reusing artifacts
crane.buildPackage {
  inherit cargoArtifacts;
  ...
};
```

**nix-cmake equivalent:**
```nix
# Build CMake dependencies separately
cmakeDeps = workspace.buildDepsOnly;

# Build the actual package
workspace.buildPackage {
  inherit cmakeDeps;
};
```

### 2. Metadata Extraction

**crane pattern:**
```nix
crane.crateNameFromCargoToml { cargoToml = ./Cargo.toml; }
```

**nix-cmake equivalent:**
```nix
cmake2nix.projectNameFromCMakeLists { cmakeLists = ./CMakeLists.txt; }
```

### 3. Flexible Input Handling

**crane pattern:**
```nix
# Accept paths, derivations, or parsed structures
crane.vendorCargoDeps {
  cargoLock = ./Cargo.lock;  # or
  cargoLockContents = "..."; # or
  cargoLockParsed = { ... };
}
```

**nix-cmake equivalent:**
```nix
cmake2nix.workspace.loadWorkspace {
  workspaceRoot = ./.;
  lockFile = ./cmake.lock;           # or
  lockFileContents = "...";           # or
  cpmLockFile = ./cmake/CPMLock.cmake; # or
}
```

## Design Patterns from uv2nix

### 1. Workspace Loading

**uv2nix pattern:**
```nix
workspace = uv2nix.lib.workspace.loadWorkspace {
  workspaceRoot = ./.;
};
```

**nix-cmake equivalent:**
```nix
workspace = cmake2nix.lib.workspace.loadWorkspace {
  workspaceRoot = ./.;  # Auto-discovers CMakeLists.txt, cmake.lock, etc.
};
```

**Returns:**
```nix
{
  # Generate overlay for dependency resolution
  mkCMakeOverlay = final: prev: { ... };

  # Parsed configuration
  config = {
    projectName = "myproject";
    version = "1.0.0";
    dependencies = { ... };
  };

  # Pre-defined dependency sets
  deps = {
    default = { ... };      # Runtime deps only
    all = { ... };          # Runtime + build deps
    dev = { ... };          # Development dependencies
  };
}
```

### 2. Overlay-Based Dependency Resolution

**uv2nix pattern:**
```nix
pythonSet = (pkgs.python3.override {
  packageOverrides = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };
}).pkgs;

pythonSet.mkVirtualEnv "my-env" workspace.deps.default
```

**nix-cmake equivalent:**
```nix
cmakeSet = pkgs.cmakePackages.overrideScope (
  workspace.mkCMakeOverlay {
    preferSystemPackages = true;  # Use find_package when possible
  }
);

cmakeSet.mkDependencyEnv "my-project-deps" workspace.deps.all
```

### 3. Dependency Presets

**uv2nix provides:**
- `deps.default` - baseline dependencies
- `deps.optionals` - includes optional-dependencies
- `deps.groups` - includes dependency-groups
- `deps.all` - everything

**nix-cmake equivalent:**
```nix
deps = {
  default = {
    # FetchContent dependencies marked required
    fmt = { };
    spdlog = { };
  };

  dev = {
    # Development/test dependencies
    Catch2 = { };
    benchmark = { };
  };

  all = {
    # All dependencies combined
    fmt = { };
    spdlog = { };
    Catch2 = { };
    benchmark = { };
  };
}
```

## API Design

### Core Namespace: `cmake2nix.lib.workspace`

Following uv2nix's namespace structure:

```nix
cmake2nix.lib.workspace = {
  # Main entry point - discovers and parses workspace
  loadWorkspace = {
    workspaceRoot,      # Required: path to project root
    lockFile ? null,    # Optional: cmake.lock location
    config ? { }        # Optional: configuration overrides
  }: workspace;

  # Lower-level functions for advanced use
  loadConfig = { workspaceRoot }: config;
  parseLockFile = { lockFile }: dependencies;
  parseCPMLock = { cpmLockFile }: dependencies;
};
```

### Workspace Object Structure

```nix
workspace = {
  # Create overlay for CMake package set
  mkCMakeOverlay = {
    preferSystemPackages ? true,  # Prefer find_package() over FetchContent
    sourcePreference ? "source",  # or "binary" for pre-built packages
  }: overlay;

  # Editable/development mode overlay
  mkEditableCMakeOverlay = { }: overlay;

  # Parsed workspace configuration
  config = {
    projectName = "myproject";
    version = "1.0.0";
    cmakeMinimumRequired = "3.24";
    dependencies = { ... };
    cpmDependencies = { ... };
    rapidsDependencies = { ... };
  };

  # Pre-defined dependency sets
  deps = {
    default = { };  # Runtime dependencies
    dev = { };      # Development dependencies
    all = { };      # All dependencies
  };

  # Convenience builders
  buildDepsOnly = derivation;  # Just the dependencies
  buildPackage = attrs: derivation;  # Full package build
};
```

### High-Level Builders

```nix
cmake2nix.lib = {
  # Build a CMake application (has executables)
  buildCMakeApplication = {
    workspaceRoot,
    lockFile ? null,
    cmakeFlags ? [ ],
    ...
  }: derivation;

  # Build a CMake library (header-only or compiled)
  buildCMakeLibrary = {
    workspaceRoot,
    lockFile ? null,
    ...
  }: derivation;

  # Generate a lock file from a CMake project
  generateLockFile = {
    workspaceRoot,
    outputPath ? "cmake.lock",
  }: derivation;
};
```

## Lock File Format

Inspired by CPM's lock file format but extended for Nix:

```nix
# cmake.lock
{
  version = "1.0";

  # FetchContent dependencies
  fetchContent = {
    fmt = {
      method = "git";
      url = "https://github.com/fmtlib/fmt.git";
      rev = "10.2.1";
      hash = "sha256-...";
      cmakeTarget = "fmt::fmt";  # For find_package() fallback
    };

    Catch2 = {
      method = "git";
      url = "https://github.com/catchorg/Catch2.git";
      rev = "v3.5.2";
      hash = "sha256-...";
      condition = "BUILD_TESTING";  # Only when tests enabled
    };
  };

  # CPM dependencies (superset of FetchContent)
  cpm = {
    spdlog = {
      version = "1.13.0";
      method = "git";
      url = "https://github.com/gabime/spdlog.git";
      rev = "v1.13.0";
      hash = "sha256-...";
      options = {
        SPDLOG_BUILD_SHARED = false;
      };
    };
  };

  # RAPIDS dependencies
  rapids = {
    version = "24.02";
    packages = {
      rmm = {
        version = "24.02";
        hash = "sha256-...";
      };
    };
  };
}
```

## CPM Integration Strategy

### CPM_SOURCE_CACHE Pattern

CPM uses a source cache to avoid re-downloading:

```bash
CPM_SOURCE_CACHE/
  <package>/
    <content-hash>/
      <source files>
```

**Our approach:**
1. Parse `CPMAddPackage()` calls to discover dependencies
2. Build each dependency as a Nix derivation
3. Pre-populate `CPM_SOURCE_CACHE` with symlinks to Nix store paths
4. Set `CPM_USE_LOCAL_PACKAGES=ON` to prefer our provided packages

### CPM Lock File Import

CPM generates `cmake/CPMLock.cmake`:

```cmake
CPMDeclarePackage(fmt
  VERSION 10.2.1
  GITHUB_REPOSITORY fmtlib/fmt
  GIT_TAG 10.2.1
)
```

We can parse this and convert to our lock file format automatically.

### Environment Variables

```bash
# Set by our hooks
export CPM_SOURCE_CACHE="$TMPDIR/nix-cpm-cache"
export CPM_USE_LOCAL_PACKAGES=ON
export CPM_DOWNLOAD_ALL=OFF

# Populated per-dependency
export NIX_FETCHCONTENT_fmt_SOURCE_DIR=/nix/store/...-fmt-src
export NIX_FETCHCONTENT_Catch2_SOURCE_DIR=/nix/store/...-catch2-src
```

## Implementation Phases

### Phase 1: Core Infrastructure (Foundation)
- [x] CMake dependency provider hook
- [x] CMake toolchain hook
- [x] FetchContent interception
- [ ] Comprehensive test suite
- [ ] CPM_SOURCE_CACHE integration

### Phase 2: Lock File & Parsing (Discovery)
- [ ] Lock file format specification
- [ ] CMakeLists.txt parser (extract FetchContent/CPM calls)
- [ ] CPM lock file parser
- [ ] Dependency graph resolution
- [ ] Hash calculation utilities

### Phase 3: High-Level API (Ergonomics)
- [ ] `lib.workspace.loadWorkspace`
- [ ] `mkCMakeOverlay`
- [ ] `buildCMakeApplication`
- [ ] `buildCMakeLibrary`
- [ ] Dependency preset generation (default/dev/all)

### Phase 4: Tooling (Developer Experience)
- [ ] `cmake2nix lock` command
- [ ] `cmake2nix init` for new projects
- [ ] Flake templates
- [ ] Migration tool from manual packaging

### Phase 5: Ecosystem Integration (Polish)
- [ ] RAPIDS CMake support
- [ ] Vcpkg manifest import
- [ ] Conan integration
- [ ] NixOS module for CMake projects
- [ ] Documentation and examples

## Comparison: Manual vs nix-cmake

### Current Manual Approach (stdexec example)

```nix
# 56 lines of boilerplate
stdenv.mkDerivation {
  pname = "stdexec";

  nativeBuildInputs = [ cmake ];

  # Manual dependency fetching
  rapids-cmake = fetchFromGitHub { ... };
  icm-src = fetchFromGitHub { ... };
  cpm-cmake = fetchurl { ... };

  preConfigure = ''
    # Manual cache population
    export CPM_SOURCE_CACHE=$TMPDIR/cpm-cache
    mkdir -p $CPM_SOURCE_CACHE/cpm
    mkdir -p $CPM_SOURCE_CACHE/icm
    cp ${cpm-cmake} $CPM_SOURCE_CACHE/cpm/CPM_0.38.5.cmake
    ln -s ${icm-src} $CPM_SOURCE_CACHE/icm/<hash>
  '';

  postPatch = ''
    # Manual CMakeLists.txt patching
    sed -i '/download RAPIDS/d' CMakeLists.txt
    substituteInPlace CMakeLists.txt ...
  '';
}
```

### nix-cmake Approach

```nix
# 8 lines, declarative
cmake2nix.lib.buildCMakeApplication {
  workspaceRoot = ./.;
  lockFile = ./cmake.lock;  # Generated by: cmake2nix lock
}
```

Or with explicit dependencies:

```nix
# 15 lines with full control
workspace = cmake2nix.lib.workspace.loadWorkspace {
  workspaceRoot = ./.;
};

workspace.buildPackage {
  # Automatic dependency injection
  # Automatic CPM_SOURCE_CACHE population
  # Automatic toolchain configuration
  cmakeFlags = [
    (lib.cmakeBool "BUILD_TESTING" false)
  ];
}
```

## Benefits Summary

### For Package Maintainers
- **90% less boilerplate** compared to manual packaging
- **Automatic dependency discovery** from lock files
- **Incremental builds** - rebuild only what changed
- **Reproducible** - lock files ensure consistency

### For Developers
- **Nix-native workflow** - no impedance mismatch
- **Offline builds** - all deps in Nix store
- **Cross-compilation** - handled automatically
- **Development shells** - `mkEditableCMakeOverlay` for live editing

### For the Ecosystem
- **Lower barrier** to entry for packaging CMake projects
- **Consistency** - same patterns as crane/uv2nix/poetry2nix
- **Upstream friendly** - no CMake modifications required
- **Composable** - integrates with existing Nix infrastructure

## Open Questions

1. **How to handle ExternalProject_Add?** (downloads at build time, not configure time)
2. **Should we support mixed FetchContent + system packages?** (some from Nix, some from nixpkgs)
3. **How to handle platforms where CMake features differ?** (macOS frameworks, Windows DLLs)
4. **Version resolution strategy?** (when multiple versions of same dep requested)
5. **Binary cache integration?** (pre-built CMake packages)

## References

- [crane documentation](https://crane.dev/)
- [uv2nix documentation](https://pyproject-nix.github.io/uv2nix/)
- [CPM.cmake](https://github.com/cpm-cmake/CPM.cmake)
- [CMake dependency provider API](https://cmake.org/cmake/help/latest/command/cmake_language.html#dependency-providers)
- [RAPIDS CMake](https://github.com/rapidsai/rapids-cmake)
