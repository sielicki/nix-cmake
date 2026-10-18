# Dogfood

Upstream projects repackaged with nix-cmake's own builders, using the
exact sources nixpkgs uses (`src = pkgs.<upstream>.src`). These exist
to kick the tires on real-world CMake projects, not as replacements
for the nixpkgs packages.

Build any of them with:

```bash
nix build .#dogfood-fmt
nix build .#dogfood-tl-expected
```

They are flake *packages*, deliberately not checks, so
`nix flake check` stays fast.

## Results (2026-10-18, x86_64-linux)

| Package | Version | Exercises | Result |
|---|---|---|---|
| fmt | 12.2.0 | compiled lib, install config, pkg-config file, CPS export | ✅ file list matches nixpkgs fmt (with `BUILD_SHARED_LIBS=ON`); installs `lib/cps/fmt/fmt.cps` |
| spdlog | 1.17.0 | external fmt via `find_package`, CPS export with transitive `fmt`/`Threads` requires | ✅ consumed transitively via CPS in `checks.cps-consumption` |
| nlohmann_json | 3.12.0 | header-only, multi-header install | ✅ |
| catch2 | 3.16.0 | test framework library (v3) | ✅ |
| pugixml | 1.16 | simple compiled library | ✅ |
| brotli | 1.2.0 | libraries + executable (install RPATH) | ✅ after hook fix below |
| zstd | 1.5.7 | CMake project in `build/cmake` subdir (`cmakeDir`) | ✅ binary round-trips |
| simdjson | 4.6.8 | compiled lib + pkg-config file | ✅ |
| tl-expected | 1.1.0 | upstream tests `FetchContent` Catch2 v2, provided via `fetchContentDeps`, `ctest` in `doCheck` | ✅ 100% tests passed |
| cli11 | 2.6.2 | header-only library | ✅ |
| yaml-cpp | 0.9.0 | compiled library | ✅ |
| googletest | 1.18.0 | gtest + gmock install | ✅ |
| fast-float | 8.3.0 | tests with system doctest (`SYSTEM_DOCTEST=ON`) | ✅ (variant with FetchContent-provided doctest also builds) |
| abseil-cpp | 20260817.0 | large multi-library project | ✅ |

Additionally verified outside this folder during the same session:

- a downstream consumer executable linking dogfood fmt + spdlog +
  nlohmann_json + Catch2 + GTest via `find_package` builds and runs;
- `dogfood-fmt` also builds through `lib.dynamic` (dynamic
  derivations, empty lock file);
- multi-output (`outputs = [ "out" "dev" ]`) fmt splits headers,
  CMake config, and pkg-config files into `dev` correctly.

## Gaps found (and fixed)

1. **Broken executables (brotli).** Our hooks never set the absolute
   `CMAKE_INSTALL_*DIR` paths that nixpkgs' cmake hook sets.
   Libraries landed in `lib64/` and `bin/brotli` had no RPATH to its
   own libraries (`libbrotlienc.so.1: cannot open shared object`).
   Both configure phases (`cmake-dependency-hook` and the bootstrap
   hook in `pkgs/cmake/setup-hook.sh`) now pass absolute
   GNUInstallDirs paths per output, with user `-D` values winning.
2. **Static-by-default libraries.** `dogfood-fmt` initially produced
   `libfmt.a` where nixpkgs ships shared libraries. This is upstream's
   default (`BUILD_SHARED_LIBS` unset), not a hook bug; the dogfood
   package now sets it explicitly to match nixpkgs.

## Remaining observations (not fixed)

- Tests are off for most packages above (matching a packaging-first
  pass). Enabling upstream test suites is the natural next stress
  test; tl-expected and fast-float already run theirs.
- `pkgs.pkg-config` is not added automatically by the builders;
  projects locating dependencies via `pkg_check_modules` must add it
  to `nativeBuildInputs` themselves (same as nixpkgs).
- Most dogfood packages use a single output; nixpkgs splits
  `out`/`dev` (and sometimes `lib`). Multi-output works (see above)
  but is opt-in per package.
