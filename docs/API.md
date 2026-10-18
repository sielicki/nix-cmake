# nix-cmake API Reference

This document describes the current Nix API for `nix-cmake`, exported
as `nix-cmake.lib` from the flake (see `lib/default.nix`).

## Workspace API (`lib.workspace pkgs`)

Project discovery, File API interrogation, and lockfile handling.

### `discoverDependencies`

Performs a guest configuration of a CMake project to extract File API
replies (`$out/reply`) and the discovery log (`$out/discovery-log.json`).

**Arguments:**

- `src`: Path to source directory.
- `cmake` (optional): CMake package to use (default `pkgs.cmakeMinimal or pkgs.cmake`).
- `cmakeFlags` (optional): Extra CMake configuration flags.
- `nativeBuildInputs` (optional): Extra inputs for the configure.
- `cmakeToolchainFile` (optional): Toolchain file (default: generated from `pkgs.stdenv`).
- `cmakeDependencyHookFile` (optional): Provider script (default `pkgs/cmake-dependency-hook/cmakeBuildHook.cmake`).
- `recursive` (optional): Allow `FetchContent` to proceed during discovery instead of stubbing it.

### `recursiveDiscover`

Wrapper around `discoverDependencies` with `recursive = true`, turned
into a fixed-output derivation. Extra arguments: `outputHash`,
`outputHashAlgo` (default `"sha256"`).

### `loadWorkspace`

The primary entry point for a lockfile-driven project.

**Arguments:**

- `workspaceRoot`: Project directory. `cmake-lock.json` there is used
  when present, falling back to CPM's `package-lock.cmake`.
- `lockFile` (optional): Explicit JSON lock file, overriding autodetection.

**Returns** an attrset with:

- `workspaceRoot`, `lock`: as given/parsed.
- `deps.all`, `deps.default`: dependency names (`default` currently equals `all`).
- `buildPackage`: like `builders.buildCMakePackage`, with `src`
  defaulting to `workspaceRoot` and `fetchContentDeps` taken from the
  lock file (explicit entries override).
- `mkCMakeOverlay`: `{ sourcePreference ? "source" } -> overlay`.
- `mkShell`: dev shell exporting `FETCHCONTENT_SOURCE_DIR_*` for all
  lock dependency sources (names must be valid shell identifiers).

### `lockFetchers`

`{ lock, fetchers ? {} } -> { name -> source-or-null }`. Instantiates
the fetchers described by a lock file; `fetchers` override per name.

### `mkProjectOverlay`

`{ lock, fetchers ? {} } -> overlay` adding `cmakeProject.<name> =
{ name, src, pkg }`, where `pkg` is a best-effort standalone build of
the dependency (lazily evaluated).

### `extractFromCodemodel`, `extractFromDiscoveryLog`, `generateLock`

Parse File API replies / discovery logs from a `discoverDependencies`
result. **These use import-from-derivation** (they read derivation
outputs during evaluation); prefer `lib.dynamic` for new code.

## Builders API (`lib.builders pkgs`)

### `buildCMakePackage`

Wrapper around `stdenv.mkDerivation` integrating the nix-cmake hooks.
Extra arguments are forwarded to `stdenv.mkDerivation`.

**Key arguments:**

- `pname`, `version`, `src`: as usual.
- `cmake` (optional, default in-tree `cmakeMinimal`).
- `fetchContentDeps` (optional): `{ name -> source | { src, ... } }`,
  injected as `FETCHCONTENT_SOURCE_DIR_*`.
- `lockFile` (optional): JSON lock file whose fetchers are merged in
  (explicit `fetchContentDeps` win).
- `cmakeFlags` (optional): `-GNinja` and `CPM_USE_LOCAL_PACKAGES=ON`
  are added automatically.
- `cmakeToolchainHook` (optional, default none), `cmakeDependencyHook`
  (optional, default the in-tree hook).
- `cmakeArtifacts` (optional): prefix added to `CMAKE_PREFIX_PATH`.
- `cps` (optional): generate CPS package info from `install(EXPORT)`
  sets; see [CPS-INTEGRATION.md](CPS-INTEGRATION.md). Shape:
  `{ gateUuid?, exports = [{ export, package, version?, compatVersion?, versionSchema?, license?, appendix?, lowerCase?, destination? }] }`.
  Rendered by the also-exported `cpsFlagsFor { cmake, cps }`.
- `cpsCompat` (optional, default `true`): add the `cmake-cps-compat`
  data package (CPS description for `Threads`) to native inputs so
  CPS transitive requirements resolve.

### `applyLockFile`

`{ lock, fetchers ? {} } -> { FETCHCONTENT_SOURCE_DIR_* = ...; }`
environment variables for a parsed lock file.

### `buildDepsOnly`

Experimental. Builds the project and installs the **build tree** to
`$out/build` for cache warming / reuse as `cmakeArtifacts`. It does not
isolate dependency targets (CMake has no generic way to do so).

## Dynamic API (`lib.dynamic pkgs`)

Opt-in IFD-free builds via dynamic derivations; see
[DYNAMIC-DERIVATIONS.md](DYNAMIC-DERIVATIONS.md) for the design and
limitations. Exports `available` (whether the evaluating Nix has
dynamic derivations) alongside `buildCMakePackage`, which throws an
explanatory error when called while unavailable. Importing or
evaluating anything else in nix-cmake requires neither dynamic
derivations nor import-from-derivation.

### `buildCMakePackage`

**Arguments:** `pname`, `version`, `src`, `lockFile` (default
`<src>/cmake-lock.json`), `cmake`, `cmakeDependencyHook`,
`cmakeToolchainFile` (discovery only), `cmakeFlags`,
`nativeBuildInputs`, `buildInputs` (derivations, embedded by store
path into the generated build), `env` (string -> string), `doCheck`,
`checkPhase`, `installPhase` (strings), `meta`.

Returns a wrapper derivation with `passthru.producer` (the
text-hashed derivation that generates the real build).

## Support libraries

- `lib.toolchains pkgs`: `default`, `clang { version }`, `gcc { version }`,
  `custom { stdenv }` toolchain setup hooks. `extraFlags` is accepted
  but not yet implemented (warns).
- `lib.dependency`: discovery-log -> lock/fetcher conversion.
- `lib.cpm-lock-parser` (internal, used by `loadWorkspace`):
  `package-lock.cmake` parsing.
- `lib.parseCMakeLists`: best-effort regex extraction of literal
  `FetchContent_Declare` calls. Prefer discovery.
- `lib.generators`: text generators for `cmake-packages.nix` /
  `cmake-env.nix` / `default.nix` (used by `cmake2nix` workflows).
- `lib.cps`: CPS parser (`parseCPSFile`, `parseCPSDir`, `lockRequirements`) for generated `.cps` files.

## Hooks (`pkgs/`)

### `cmakeToolchainHook`

Setup hook installing a declarative `CMAKE_TOOLCHAIN_FILE` generated
from an stdenv (correct `CMAKE_SYSTEM_*` mapping, cc-wrapper compilers,
impure-prefix ignoring, `NixGNUInstallDirs`).

### `cmakeDependencyHook`

Setup hook injecting the dependency provider
(`cmakeBuildHook.cmake`) via `CMAKE_PROJECT_TOP_LEVEL_INCLUDES`. It
intercepts `FetchContent_MakeAvailable` and `find_package`
(`REQUIRED` is honoured with a hard error), provides
`FETCHCONTENT_SOURCE_DIR_*` fallbacks for `FetchContent_Populate`/CPM,
and implements discovery mode. Its `nixCmakeConfigurePhase` replaces
the configure phase unless `dontUseNixCMakeSetup` is set.

### `cmake` / `cmakeMinimal`

Unpatched Kitware CMake 4.4.3. `cmakeMinimal` is the bootstrap build
(vendored libraries, in-tree minimal setup hook in
`pkgs/cmake/setup-hook.sh`); `cmake` is the full build against system
libraries with both hooks attached.
