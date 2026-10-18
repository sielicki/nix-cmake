# nix-cmake

## Status

Experimental. The core flows — dependency-provider interception,
discovery, lockfile-driven builds, and [dynamic derivations](docs/DYNAMIC-DERIVATIONS.md) —
are covered by flake checks, but the APIs are not yet stable.
Originally LLM-written as a proof of concept; being polished in the open.

## What is it?

A Nix library for seamless, modular, and unpatched CMake integration. See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.

`nix-cmake` bridges the gap between CMake's dynamic ecosystem (CPM, FetchContent, RAPIDS) and Nix's reproducible, sandboxed build system. It aims to provide a declarative, `uv2nix`/`crane`-style experience for C++ projects.

## Key Features

- **Zero-Patch Philosophy**: Uses standard Kitware CMake (4.4.3) without the extensive patching typically required by Nixpkgs.
- **Dependency Provider Interception**: Automatically intercepts `FetchContent` and `find_package` calls (and thereby most `CPM` usage) to provide Nix-managed sources.
- **Discovery + Lockfiles**: Configures projects in discovery mode to enumerate dependencies into a checked-in `cmake-lock.json`.
- **Dynamic Derivations**: `lib.dynamic` performs discovery and generates the real build *at build time* (RFC 92), so evaluation never blocks on import-from-derivation.
- **File API Integration**: Leverages the CMake File API for extraction of project targets and metadata.
- **Overlays**: Projects can be exposed as a fixed-point overlay of built dependencies.

## Quick Start

### Lockfile-driven build

With a `cmake-lock.json` next to your `CMakeLists.txt` (generate one
with the discovery derivation or `cmake2nix lock`):

```nix
{
  inputs.nix-cmake.url = "github:sielicki/nix-cmake";

  outputs = { nix-cmake, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      workspace = (nix-cmake.lib.workspace pkgs).loadWorkspace {
        workspaceRoot = ./.;
      };
    in {
      packages.${system}.default = workspace.buildPackage {
        pname = "my-app";
        version = "0.1.0";
      };
      devShells.${system}.default = workspace.mkShell { };
    };
}
```

Explicit one-off dependencies can be injected instead via
`builders.buildCMakePackage { fetchContentDeps = { fmt = ...; }; }`
(see [API.md](docs/API.md)).

### Dynamic-derivation build

Opt-in only: used when your Nix has the `ca-derivations`,
`dynamic-derivations` and `recursive-nix` experimental features
enabled, ignored otherwise — nothing else in nix-cmake requires
dynamic derivations or import-from-derivation. See
[DYNAMIC-DERIVATIONS.md](docs/DYNAMIC-DERIVATIONS.md).

```nix
packages.${system}.default = (nix-cmake.lib.dynamic pkgs).buildCMakePackage {
  pname = "my-app";
  version = "0.1.0";
  src = ./.;
};
```

### Dependency discovery

```bash
# Configure-only derivation emitting File API replies + discovery log
nix build .#checks.x86_64-linux.discovery-test
```

## Flake outputs

- `packages`: `cmake` (unpatched 4.4.3, default), `cmakeMinimal` (bootstrap), `cmake2nix`, `cmakeToolchainHook`, `cmakeDependencyHook`, `rapids-cmake`, plus `dogfood-*` (upstream projects repackaged with nix-cmake, see [dogfood/](dogfood/README.md)).
- `lib`: `workspace`, `builders`, `dynamic`, `toolchains`, plus lockfile helpers.
- `overlays.default`: adds `cmakeUnpatched` / `cmakeUnpatchedMinimal` (deliberately non-conflicting names).
- `flakeModules.default`: flake-parts module (`perSystem.cmake-project`).
- `checks`: FetchContent/CPM/multi-dependency/discovery/stdexec/dynamic tests.
- `devShells.default`: in-tree CMake + `cmake2nix` for working on this repo.

## Documentation

Detailed technical documentation is available in the [docs index](docs/README.md), including:

- **[Architecture](docs/ARCHITECTURE.md)** - How the dependency provider and unpatched CMake work.
- **[Dynamic Derivations](docs/DYNAMIC-DERIVATIONS.md)** - IFD-free discovery and build generation.
- **[Recursive Discovery](docs/RECURSIVE-DISCOVERY.md)** - Exploring multi-level dependency trees.
- **[API Reference](docs/API.md)** - Signatures for workspace, builder, and dynamic functions.
- **[Design Vision](docs/DESIGN.md)** - Inspiration from `crane` and `uv2nix`.
- **[Roadmap](docs/ROADMAP.md)** - Current status and future plans.
- **[Comparisons](docs/COMPARISONS.md)** - Comparison to other `*2nix` tools.

Some documents in `docs/` are design explorations for features that are
only partially implemented; the roadmap marks what actually ships.

## Development

```bash
nix develop          # in-tree CMake + cmake2nix; installs pre-commit hooks
nix fmt              # treefmt: nixpkgs-fmt + clang-format
nix flake check      # tests, treefmt, and pre-commit hooks
                     # (statix, deadnix, shellcheck, ruff)
```

Dynamic-derivation paths are exercised only when your Nix has the
`ca-derivations`, `dynamic-derivations`, and `recursive-nix`
experimental features enabled (the dynamic check is then present;
otherwise it is absent rather than failing). The rest of the check
suite needs neither those features nor import-from-derivation.
To prove no import-from-derivation is involved:

```bash
nix build .#checks.x86_64-linux.dynamic-fetchcontent \
  --option allow-import-from-derivation false
```

## License

Apache 2.0
