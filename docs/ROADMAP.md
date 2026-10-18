# nix-cmake Roadmap

`nix-cmake` brings the packaging ergonomics of modern ecosystems like Rust (crane) and Python (uv2nix) to C++/CMake projects. This roadmap records what actually ships today (covered by `nix flake check`) versus what is exploratory.

## Phase 0: Foundation (shipped)

- [x] **Zero-Patch Philosophy**: Standard Kitware CMake 4.4.3 (`cmakeMinimal` bootstrap + full `cmake`) without Nixpkgs patches.
- [x] **Dependency Provider**: Interception of `FetchContent_MakeAvailable` and `find_package` via `CMAKE_PROJECT_TOP_LEVEL_INCLUDES`, with `FETCHCONTENT_SOURCE_DIR_*` fallback for `FetchContent_Populate`/CPM.
- [x] **Toolchain Hook**: `CMAKE_TOOLCHAIN_FILE` generated from an stdenv (cc wrappers, correct system mapping).

## Phase 1: Discovery (shipped)

- [x] **Discovery mode**: Configure-time logging of intercepted dependencies to a JSON-lines log, with stubbed targets.
- [x] **File API replies**: `discoverDependencies` collects codemodel/cache replies next to the log.
- [x] **Recursive discovery**: FOD variant (`recursiveDiscover`) that lets FetchContent proceed.
- [ ] **Darwin verification**: Discovery bypasses compiler checks, but the check suite currently runs on Linux; Darwin is untested in CI.

## Phase 2: Lockfiles (shipped, with limits)

- [x] **`cmake-lock.json`**: name -> `{version, method, args, metadata}` consumed by builders, workspace, dynamic builds, and `cmake2nix`.
- [x] **CPM `package-lock.cmake` import** (note: git dependencies receive placeholder hashes, by design of the CPM format).
- [x] **Project overlay**: `mkProjectOverlay` builds each lock entry as a package on demand.
- [ ] **Transitive/direct distinction**: `workspace.deps.default` currently equals `deps.all`.

## Phase 3: Builder ergonomics (partial)

- [x] `builders.buildCMakePackage`, `workspace.buildPackage`, `workspace.mkShell`.
- [~] **`buildDepsOnly`**: experimental; preserves the full build tree, it does not isolate dependency targets.
- [ ] **Workspace dependency overrides API**: overrides today are plain attrset merges (`fetchContentDeps //`, overlay `fetchers`); a dedicated `override` API does not exist yet.

## Phase 4: Dynamic derivations (shipped, evolving)

- [x] `lib.dynamic.buildCMakePackage`: discovery + build generation at build time via a text-hashed producer derivation and `builtins.outputOf`; verified with `--option allow-import-from-derivation false`. See [DYNAMIC-DERIVATIONS.md](DYNAMIC-DERIVATIONS.md).
- [ ] Per-target/per-dependency generated derivations from File API metadata.
- [ ] Lockfile regeneration inside the producer (hashes still require a prefetch step outside the sandbox).

## Phase 5: Tooling (shipped, evolving)

- [x] **`cmake2nix` CLI** (C++): `discover`, `prefetch`, `generate`, `lock`, `init`, `shell`, `build`. Discovery expects `NIX_PATH` entries for `<nixpkgs>`/`<nix-cmake>`; generated expressions use the legacy `nix-build`/`nix-shell` interface.
- [x] **flake-parts module**: `perSystem.cmake-project`.
- [x] **RAPIDS**: `rapids-cmake` package + stdexec test fixture (pinned, old).
- [x] **CPS (phase 1)**: opt-in CPS generation in the builders
  (`cps.exports`, via `CMAKE_INSTALL_EXPORTS_AS_PACKAGE_INFO`),
  `cmake-cps-compat` Threads description, spec-shaped parser
  (`lib.cps`), and a transitive-consumption check. See
  [CPS-INTEGRATION.md](CPS-INTEGRATION.md).
- [~] **Multi-toolchain**: `lib.toolchains` selects Clang/GCC stdenvs; `extraFlags` is accepted but unimplemented.

## Future outlook

- [ ] CPS phase 2: CPS as discovery/lock interchange, more compat descriptions, dynamic-build awareness.
- [ ] Extended cross-compilation (tested Darwin + embedded toolchains).
- [ ] Auto-conversion of complex projects to standalone Nix expressions.
- [ ] Binary cache interop (vcpkg/Conan) where source builds are restricted.
- [ ] Structured-attrs aware hooks (cmakeFlags without space-splitting limits).
