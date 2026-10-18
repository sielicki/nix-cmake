# Documentation Index

Documents are grouped by how much you should rely on them. The
[roadmap](ROADMAP.md) is the source of truth for what ships today.

## Reference (current)

| Document | Contents |
|---|---|
| [API.md](API.md) | Nix library reference: workspace, builders, dynamic, hooks |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System overview, dependency provider, build flow |
| [DYNAMIC-DERIVATIONS.md](DYNAMIC-DERIVATIONS.md) | IFD-free discovery/build via dynamic derivations (RFC 92) |
| [FLAKE-PARTS.md](FLAKE-PARTS.md) | `flakeModules.default` (`perSystem.cmake-project`) usage |
| [CPS-INTEGRATION.md](CPS-INTEGRATION.md) | CPS generation/consumption, Threads compat, design notes |
| [CMAKE-PACKAGING-REVIEW.md](CMAKE-PACKAGING-REVIEW.md) | In-tree CMake vs nixpkgs: patches, bootstrap role of cmakeMinimal, gaps |
| [RECURSIVE-DISCOVERY.md](RECURSIVE-DISCOVERY.md) | Nested dependency discovery (FOD flow) |
| [ZERO-PATCH.md](ZERO-PATCH.md) | Why CMake is unpatched and how hermeticity is achieved |
| [ROADMAP.md](ROADMAP.md) | Shipped vs. exploratory status, by phase |

## Background

| Document | Contents |
|---|---|
| [CMAKE-4-FEATURES.md](CMAKE-4-FEATURES.md) | Survey of CMake 4.x features nix-cmake relies on (written against 4.2; current CMake is 4.4.3) |
| [COMPARISONS.md](COMPARISONS.md) | Positioning vs. other `*2nix` ecosystems |

## Design explorations (not implemented as written)

These documents record design directions. Code snippets in them are
illustrative and may not exist; check [ROADMAP.md](ROADMAP.md) before
relying on anything here.

| Document | Contents |
|---|---|
| [DESIGN.md](DESIGN.md) | crane/uv2nix-style vision and API sketches |
| [CMAKE-AS-BUILDER.md](CMAKE-AS-BUILDER.md) | Using CMake itself as the derivation builder |
| [CMAKE2NIX-DESIGN.md](CMAKE2NIX-DESIGN.md) | Non-flake `cmake2nix` workflow (partially implemented by `pkgs/cmake2nix`) |
| [FILE-API-STRATEGY.md](FILE-API-STRATEGY.md) | File-API-driven dependency extraction strategy |
| [PKG-CONFIG-INTEGRATION.md](PKG-CONFIG-INTEGRATION.md) | `cmake_pkg_config` based pkg-config support |
| [CPACK-INTEGRATION.md](CPACK-INTEGRATION.md) | CPack External generator integration (deferred) |
