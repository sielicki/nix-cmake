# nix-cmake Roadmap

`nix-cmake` is a state-of-the-art Nix integration for CMake, bringing the packaging ergonomics of modern ecosystems like Rust (crane) and Python (uv2nix) to the C++ world.

## Phase 0: Foundation (Complete)
- [x] **Zero-Patch Philosophy**: Verified support for standard Kitware CMake 4.2.1 without Nixpkgs patches.
- [x] **Dependency Provider**: Interception of `FetchContent` and `CPM` calls.
- [x] **Toolchain Hook**: Robust cross-compilation support via declarative `CMAKE_TOOLCHAIN_FILE`.

## Phase 1: File API & Discovery (Complete)
- [x] **File API Integration**: Accurate extraction of project targets and metadata via CMake File API v2.
- [x] **Recursive Discovery**: FOD-based exploration of nested dependency trees for modular projects.
- [x] **JSON Discovery Logs**: Structured, parseable logging of intercepted dependencies.
- [x] **Darwin Stability**: Automated bypassing of platform compiler/linker checks during discovery.

## Phase 2: Lock Files & Nix Modeling (Complete)
- [x] **Unified Lock File Standard**: Standardized `cmake-lock.json` format for transitive dependency pinning.
- [x] **Automated Fetcher Generation**: A Nix-based generator that converts discovery logs into `fetchgit`, `fetchurl`, or local `path` specifications.
- [x] **Project Overlay Generation**: Refined `mkProjectOverlay` to handle transitive target-to-derivation mapping and lock file consumption.
- [x] **Verified Implementation**: Full "2nix" flow verified with recursive project tests.

## Phase 3: Developer Ergonomics & Incremental Builds (Complete)
- [x] **`buildDepsOnly` Implementation**: A `crane`-style builder that pre-configures and builds all dependencies into a single derivation to maximize cache hits.
- [x] **DevShell & IDE Integration**: 
    - [x] Automatic `compile_commands.json` generation enabled in dev shells.
    - [x] Ergonomic `mkShell` API for standardized development environments.
- [x] **Targeted Overrides**: A high-level `Workspace.override` API for flexible dependency swapping.

## Phase 4: CLI & Ecosystem Tooling (Complete)
- [x] **`cmake2nix` CLI**:
    - [x] `lock`: Automated updating of `cmake-lock.json`.
    - [x] `init`: One-command scaffolding for new projects.
- [x] **`flake-parts` Module**: Declarative `cmake-project` configuration for the `flake-parts` ecosystem.
- [x] **Flake Integration**: First-class support for `cmake2nix` and `flakeModules.default`.

## Phase 5: Advanced Ecosystems & Future Tech (Complete)
- [x] **RAPIDS CMake Support**: Integration patterns for the NVIDIA RAPIDS ecosystem.
- [x] **CPS (Common Package Specification) Integration**: Prototype support for CPS metadata parsing.
- [x] **Multi-Toolchain Support**: High-level library for switching between Clang, GCC, and custom toolchains.

## Future Outlook
- [ ] **Full CPS Implementation**: Moving from prototype to industrial-strength package mapping.
- [ ] **Extended Cross-Compilation**: Pre-configured toolchain bundles for Embedded and Mobile platforms.
- [ ] **Auto-Conversion**: Deep project analysis to automatically generate full Nix expressions from complex CMake bases.
- [ ] **Binary Cache Interop**: Integration with pre-built binary packages from other package managers (vcpkg/Conan) when source builds are restricted.
