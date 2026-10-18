# CMake Packaging Review: nix-cmake vs nixpkgs

> **Status: review (2026-10-18).** Compares `pkgs/cmake/bootstrap.nix`
> (`cmakeMinimal`) and `pkgs/cmake/default.nix` (`cmake`) against
> nixpkgs' `pkgs/by-name/cm/cmake/package.nix` at the same version
> (4.4.3), with emphasis on the reason `cmakeMinimal` exists at all:
> **Nix toolchain bootstrapping**.

## Why `cmakeMinimal` exists in nixpkgs

Full CMake links curl, OpenSSL, libarchive, libuv, rhash, etc. That
dependency set cannot enter early bootstrap stages:

- nixpkgs defines both from **one** `package.nix`:
  `cmake = …#full`, `cmakeMinimal = callPackage ./package.nix { isMinimalBuild = true; }`
  ("can't use override - it triggers infinite recursion").
  `isMinimalBuild` flips the defaults that matter:
  `useOpenSSL = false`, `useSharedLibraries = false` (→
  `--no-system-libs`, everything vendored), no UI toolkits
  (asserted), no docs. Its only `buildInput` is `bashNonInteractive`
  (+ iconv on Darwin), so it can be built with a bare bootstrap
  stdenv: `./bootstrap` needs nothing but a C/C++ compiler.
- In the **Darwin stdenv bootstrap** (`pkgs/stdenv/darwin/default.nix`),
  `curl` is explicitly banned (`curl = throw "nothing in the Darwin
  bootstrap can depend on curl"`), and stage 1 sets
  `cmake = self.cmakeMinimal` to build stage-1 packages (which in
  turn build LLVM/clang/libSystem for later stages). A full CMake
  would drag curl + OpenSSL into a stage that must not have them,
  and any change to curl would trigger a full stdenv rebuild.
- Elsewhere the same logic applies wherever CMake is needed *below*
  its own library dependencies in the graph: LLVM with
  `libc == "llvm"` uses `cmakeMinimal`, and top-level `zstd` is
  built with `buildPackages.cmakeMinimal`.
- Equally important, **nixpkgs' full CMake does not depend on
  cmakeMinimal to build**: the same recipe always self-bootstraps
  via `./bootstrap` (`dontUseCmakeConfigure`, `CC_FOR_BUILD`/
  `CXX_FOR_BUILD`). There is no point in the graph where building
  CMake requires a working CMake.

Consequences used as review criteria below: a bootstrap-viable
minimal CMake must have (a) a build recipe needing only a compiler,
(b) a tiny runtime closure free of curl/OpenSSL-tier packages.

## Head-to-head

| Aspect | nixpkgs (4.4.3) | nix-cmake (4.4.3) |
|---|---|---|
| Recipe structure | one parameterized `package.nix` (`isMinimalBuild`, `uiToolkits`, `buildDocs`, `useOpenSSL`, `useSharedLibraries`) | two derivations: `bootstrap.nix` (minimal) + `default.nix` (full); both self-bootstrap via `./bootstrap` since the bootstrap-parity change (see F2) |
| Source | release tarball from cmake.org (`fetchurl`) | GitHub git archive (`fetchFromGitHub`, tag `v4.4.3`) |
| Patches | 5 (below) | none ("zero-patch") |
| Minimal build inputs | `bashNonInteractive` (+ iconv on Darwin) | compiler only since bootstrap-parity change (iconv on Darwin only, from libc on Linux) |
| Minimal runtime closure | 11 store paths | 7 after the fixes in Findings (glibc/gcc-lib only; libidn2 arrives via glibc) |
| Full build inputs | system libs via `--system-libs`; no jsoncpp/cppdap; openssl optional | system libs via `--system-libs`, same list as upstream (always OpenSSL; no ncurses) |
| Full outputs | `out` (+ `man`/`info` iff docs) | `out` (since bootstrap-parity change) |
| Docs/UI | optional sphinx docs, curses/Qt GUIs | none |
| Setup hooks shipped | `setup-hook.sh` (full configure logic) + `check-pc-files-hook.sh`, attached to **both** variants | minimal: own basic `setup-hook.sh`; full: toolchain + dependency hooks (not the basic hook) |
| Cross support | `CC/CXX_FOR_BUILD`, absolute AR/RANLIB/STRIP flags, install-time `cmakeMinimal` substitution, `strictDeps`, static-libarchive LDFLAGS fix | `CC/CXX_FOR_BUILD` + absolute bintools flags now passed; untested cross (Linux-first), no install-time substitution |
| Structured attrs | yes | no |

## The five nixpkgs patches, and our zero-patch equivalents

1. **`nixpkgs-cmake-prefix-path.patch`** (28 lines) — teaches CMake
   a new env var `NIXPKGS_CMAKE_PREFIX_PATH`, like `CMAKE_PREFIX_PATH`
   but never searched for *programs*. The setup hook accumulates
   every input prefix there (per host/target offset), so package
   discovery sees all Nix inputs without letting `find_program` pick
   up target-architecture binaries from `buildInputs`.
   *Ours:* hooks pass `-DCMAKE_PREFIX_PATH=<all inputs>` instead.
   Simpler and patch-free, but conflates program search: in a cross
   build, target prefixes' `bin/` dirs are program-searchable. Our
   generated toolchain mitigates for cross (`FIND_ROOT_PATH_MODE_PROGRAM
   NEVER`), but only when the toolchain hook is in use. **Gap: cross
   program-search hygiene.**

2. **`add-nixpkgs-libc-paths.patch`** (50 lines, plus a
   `substituteInPlace` of `@libc_*@` at build time) — makes
   `Platform/UnixPaths.cmake` resolve the *consumer's* libc at
   CMake run time from the cc-wrapper's `nix-support/orig-libc[-dev]`
   files, so one CMake binary serves every stdenv/libc combination.
   This is also what lets nixpkgs' bootstrap configure find
   `iconv.h`. *Ours:* per-stdenv generated toolchain files carry libc
   paths (equivalent when the toolchain hook is used), but plain
   `cmakeMinimal` has no equivalent — which is exactly why our 4.4
   bootstrap needed the explicit `-DICONV_INCLUDE_DIR` workaround.
   **Gap: cmakeMinimal alone doesn't know libc paths.**

3. **`remove-impure-search-paths.patch`** (2009 lines, 62 files) —
   deletes hardcoded `/usr`, `/usr/local`, `/opt`, Homebrew, Windows
   registry, etc. search paths from Find modules and platform files
   (including the default `CMAKE_SYSTEM_PREFIX_PATH` of
   `/usr/local /usr /`). *Ours:* hooks/toolchain set
   `CMAKE_SYSTEM_IGNORE_PREFIX_PATH` for the main offenders. Inside
   the Nix sandbox the hardcoded paths don't exist, so builds are
   unaffected; outside it (`nix develop`, `nix run .#cmake` on a
   workstation) our CMake *can* find `/usr` libraries and programs
   through Find-module hardcoded paths (CUDA, Java, …) that a prefix
   ignore list cannot cover. **Gap: impurity leaks in unsandboxed
   use; none inside Nix builds.**

4. **`darwin-binary-paths.patch` / `darwin-bsd-binary-paths.patch`**
   — bake absolute store paths for `sw_vers`, `vm_stat`, `sysctl`,
   `ps` into kwsys/platform modules (Darwin/FreeBSD only, via
   `replaceVars`). *Ours:* `cmakeMinimal` wraps the binaries with
   DarwinTools/system_cmds on Darwin only (functionally equivalent,
   wrapper instead of patch); the full `cmake` does neither, so on
   Darwin it falls back to bare `sw_vers` etc. via PATH (works on a
   real Mac, impure and fragile in pure environments). **Gap: full
   cmake on Darwin.**

## Findings from this review

### Fixed during the review

- **F1 — `cmakeMinimal` closure bloat (bootstrap-hostile).** Our
  minimal wrapped its binaries with `git`, `ps`, and `sysctl` in
  PATH on *all* platforms. `git` alone pulls curl, OpenSSL, Perl
  and friends: **95 store paths vs upstream's 11**, including the
  exact packages (curl!) a bootstrap CMake must not depend on.
  Upstream needs no wrapper: on Linux nothing is wrapped, on Darwin
  paths are patched in. Fix: wrap only on Darwin (DarwinTools +
  system_cmds), drop `git` entirely (sandboxed FetchContent can't
  clone anyway; discovery derivations add git themselves), and drop
  the unused `ps` buildInput from the full build. **8 store paths** at review time; **7** after the later bootstrap-parity slimming (bash wrapper gone; remaining libidn2/libunistring arrive via glibc itself, cmake does not link them).

### Open (ranked)

- **F2 — Full CMake cannot bootstrap itself.** ~~Ours is built *by*
  cmakeMinimal through our own hooks.~~ **Fixed after this review
  (bootstrap parity, Linux-first):** full `cmake` now
  self-bootstraps via `./bootstrap --system-libs`, like upstream.
  It takes no CMake, ninja, or hook input to build; hooks are
  shipped payload only. `cmakeMinimal` was slimmed at the same
  time to compiler-only inputs (no ninja, no libraries;
  Make-generator bootstrap). Guarded by flake checks
  `bootstrap-properties` (.drv input lists + minimal closure
  free of curl/OpenSSL-tier packages) and `bootstrap-consumer`
  (full cmake still works as a consumer build tool). Side effect:
  full cmake is a single `out` output now, as upstream (the old
  dev/out/doc split relied on hook-driven builds).
- **F3 — No cross-compilation handling** in either derivation
  (upstream: `*_FOR_BUILD` compilers, absolute bintools paths,
  install-time cmake substitution, static fixes). Our flake checks
  evaluate aarch64 but never build it; a `pkgsCross` build of
  `cmakeMinimal` is the natural test to add.
- **F4 — Program-search hygiene** (patch 1 above): using
  `CMAKE_PREFIX_PATH` for everything lets `find_program` see
  `buildInputs` binaries. Mostly a cross-building concern.
- **F5 — `.pc` file validation.** Upstream ships
  `check-pc-files-hook.sh` which rejects `.pc` files containing
  `}//nix/store` (badly joined absolute GNUInstallDirs). Our hooks
  pass absolute install dirs (since the dogfood RPATH fix), making
  this check relevant; we have no equivalent validation.
- **F6 — Full-build dependency hygiene.** ncurses is linked but no
  `BUILD_CursesDialog` is requested (dead weight); `nghttp2`/`zstd`
  are linked only via curl/libarchive transitivity rather than
  CMake options; `openssl` is non-optional. Upstream parameterizes
  all of these. Cosmetic for a library whose full CMake is mostly a
  carrier for our hooks.
- **F7 — Source provenance.** Release tarball (upstream) vs GitHub
  git archive (ours). The tarball is Kitware's canonical,
  signature-published artifact and what bootstrap seeds pin;
  switching `src` to `fetchurl` cmake.org would also make our hash
  directly comparable to nixpkgs'.
- **F8 — Darwin full build** (patch 4 above): no helper-path
  handling at all in `pkgs/cmake/default.nix`.

## Verification

- Versions compared at 4.4.3 on both sides; patch files read in full
  from the pinned nixpkgs.
- Closure sizes measured with `nix path-info -r`:
  cmakeMinimal 95 → 7 (binary is a plain ELF again, not a wrapper
  script, on Linux; links only libc/libstdc++/libm/libdl/librt).
- After the bootstrap-parity change: `.#cmakeMinimal`, `.#cmake`,
  checks `bootstrap-properties` + `bootstrap-consumer`, and
  `nix flake check` rebuilt/re-run. Full cmake reports
  `Using system-installed: ... OPENSSL` and links system
  curl/libarchive/librhash/libuv.
