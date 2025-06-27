# nix-cmake

## IMPORTANT NOTE

This repo is primarily LLM-written, but sort-of works as a proof of concept. I don't recommend actually using this in its current state. It needs to be polished up.

## What is it?

A Nix library for seamless, modular, and unpatched CMake integration. See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for real details.

`nix-cmake` bridges the gap between CMake's dynamic ecosystem (CPM, FetchContent, RAPIDS) and Nix's reproducible, sandboxed build system. It aims to provide a declarative, `uv2nix`/`crane`-style experience for C++ projects.


## Key Features

- **Zero-Patch Philosophy**: Uses standard Kitware CMake (4.2.1) without the extensive patching typically required by Nixpkgs.
- **Dependency Provider Interception**: Automatically intercepts `FetchContent` and `CPM` calls to provide Nix-managed sources.
- **Recursive Discovery**: Supports FOD-based exploration of nested dependency trees to build complete dependency graphs.
- **File API Integration**: Leverages the CMake File API for accurate extraction of project targets and metadata.
- **Modular Overlays**: Provides a fixed-point API for managing and overriding project dependencies.

## Quick Start

### Basic Project Build

```nix
{
  inputs.nix-cmake.url = "github:sielicki/nix-cmake";

  outputs = { nix-cmake, nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      workspace = nix-cmake.lib.workspace pkgs;
    in {
      packages.x86_64-linux.default = workspace.buildCMakePackage {
        pname = "my-app";
        version = "0.1.0";
        src = ./.;
        
        # Inject dependencies
        fetchContentDeps = {
          fmt = pkgs.fetchFromGitHub { ... };
        };
      };
    };
}
```

### Dependency Discovery

```bash
# Perform a recursive discovery pass
nix build .#discovery --extra-experimental-features "nix-command flakes"
```

## Documentation

Detailed technical documentation and guides are available in the [docs/](docs/) directory:

- **[Architecture](docs/ARCHITECTURE.md)** - How the dependency provider and unpatched CMake work.
- **[Recursive Discovery](docs/RECURSIVE-DISCOVERY.md)** - Exploring multi-level dependency trees.
- **[API Reference](docs/API.md)** - Detailed signatures for workspace and builder functions.
- **[Design Vision](docs/DESIGN.md)** - Inspiration from `crane` and `uv2nix`.
- **[Roadmap](docs/ROADMAP.md)** - Current status and future plans.
- **[Comparisons](docs/COMPARISONS.md)** - Comparison to other `*2nix` tools and real-world examples.

## License

Apache 2.0
