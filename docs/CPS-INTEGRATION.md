# CPS (Common Package Specification) Integration

> **Status: phase 1 implemented** (CPS generation for packages built
> with nix-cmake, CPS consumption including transitive resolution,
> Threads compat description, parser). Later phases below are design
> direction. This document replaces an earlier speculative draft; the
> details here were verified against the in-tree CMake 4.4.3 and are
> exercised by the `cps-consumption` flake check.

## What CPS is

The [Common Package Specification](https://cps-org.github.io/cps/) is
a tool-agnostic, JSON-based description of a built package:
components (libraries/executables/interfaces), their locations,
usage requirements (includes, definitions, compile features), and
requirements on other packages. It plays the role of CMake
package-config scripts (`<name>Config.cmake` +
`<name>Targets.cmake`) as *data instead of code*, consumable by build
tools other than CMake.

## State in CMake 4.4.3 (what we build on)

- **Import is stable.** Since 4.3, `find_package` config mode searches
  `<name>.cps` alongside CMake-script configs and *prefers* CPS
  within a prefix. No experimental gate is needed to consume CPS
  (the `CMAKE_EXPERIMENTAL_FIND_CPS_PACKAGES` UUID from the 4.0 era
  is gone). Transitive requirements of a CPS package are resolved by
  CMake itself via nested `find_package` calls, against CPS *or*
  CMake-script packages.
- **Export has two routes.**
  - Projects can call `install(PACKAGE_INFO <name> EXPORT ...)`
    (since 4.3, not gated).
  - Distributors can generate CPS for *unmodified* projects that use
    `install(EXPORT)` via
    `CMAKE_INSTALL_EXPORTS_AS_PACKAGE_INFO=<export>:<package>...`,
    gated by `CMAKE_EXPERIMENTAL_MAPPED_PACKAGE_INFO`. The gate UUID
    rotates between CMake releases and is documented only in
    `Help/dev/experimental.rst` of the CMake source tree
    (4.4.3: `ababa1b5-7099-495f-a9cd-e22d38f274f2`).
- **Version selection is stricter than CMake-script configs.** With
  the `simple` schema and no `compat_version`, the package version
  must *equal* the requested version. `find_package(fmt 12)` does
  **not** accept fmt 12.2.0's CPS unless it declares
  `compat_version <= 12`. Generated CPS must set `compat_version`
  deliberately (analogous to `SameMajorVersion` in
  `write_basic_package_version_file`).
- **Hints are not yet honoured.** Generated CPS records where a
  requirement was found at build time (`requires.<pkg>.hints`), but
  CMake 4.4.3 does not pass them to the nested search
  (`// TODO set hints` in `cmFindPackageCommand.cxx`). Transitive
  dependencies must therefore be on the consumer's prefix path —
  in Nix terms: they must be propagated inputs.
- **`Threads:Threads` has no CPS description.** CMake generates
  `requires: ["Threads:Threads", ...]` for the many targets that link
  `Threads::Threads`, but Threads exists only as the `FindThreads`
  module, so such CPS packages fail to load with
  `Could not find a package configuration file provided by "Threads"`.
  nix-cmake fills this gap (below). Also note `cps_version` must
  match a version CMake accepts (`0.14` was rejected as "unknown";
  `0.14.1` — what CMake 4.4.3 generates — works).

## What nix-cmake does today

### 1. CPS generation in the builders (`cps` argument)

`lib.builders.buildCMakePackage` accepts an opt-in `cps` argument
rendered by `builders.cpsFlagsFor` into the mapped-package-info flags
above, so packages install `.cps` files alongside their CMake-script
configs without upstream changes:

```nix
builders.buildCMakePackage {
  pname = "fmt";
  # ...
  cps.exports = [{
    export = "fmt-targets";          # install(EXPORT <export>) name
    package = "fmt";                 # find_package(<package>) name
    version = "@FMT_VERSION@";       # @VAR@ expanded by CMake
    compatVersion = "@CPACK_PACKAGE_VERSION_MAJOR@";
    license = "MIT";
    # appendix, lowerCase, destination, versionSchema also supported
  }];
  # cps.gateUuid overrides the known gate for the CMake in use.
}
```

Gate UUIDs for verified CMake versions live in
`builders.cpsGateUuids`; unknown versions fail evaluation with an
explanation instead of silently producing nothing. See
[`dogfood/fmt.nix`](../dogfood/fmt.nix) and
[`dogfood/spdlog.nix`](../dogfood/spdlog.nix).

### 2. Threads compat description (`pkgs/cmake-cps-compat`)

A data-only package installing `share/cps/Threads/Threads.cps`
(interface component with `-pthread` compile/link flags). The
builders add it to `nativeBuildInputs` by default (`cpsCompat =
false` opts out), so CPS transitive resolution works out of the box.

### 3. Fixes CPS consumption exposed in our own hooks

Dogfooding CPS found two general bugs, now fixed:

- The dependency provider's `FIND_PACKAGE` handling retried with
  `PATHS <prefixes> NO_DEFAULT_PATH`. `PATHS` entries are searched
  as explicit config directories without prefix suffix patterns,
  which cannot find `<prefix>/share/cps/<name>/<name>.cps` and broke
  CPS transitive resolution. It now delegates to CMake's standard
  search (`BYPASS_PROVIDER` only); Nix prefixes are already on
  `CMAKE_PREFIX_PATH`/`CMAKE_SYSTEM_PREFIX_PATH`.
- Prefix construction in both configure hooks only considered
  *direct* inputs. Transitive CPS requirements need the propagated
  closure, so the hooks now iterate stdenv's accumulated
  `pkgsHostTarget`/`pkgsBuild*` arrays.

### 4. Parser (`lib.cps`)

`parseCPSFile` / `parseCPSDir` parse real generated CPS (root +
per-configuration appendices) into a normalized structure
(components with requirements like `fmt:fmt` / `:local`,
package-level `requires`, sorted external `dependencies`), plus
`lockRequirements` for a lock-file-shaped view. Reading CPS from a
derivation output is import-from-derivation, like the other
discovery parsers; nothing requires it by default.

### Verified end-to-end

`checks.cps-consumption` (`tests/cps/`): a consumer that only calls
`find_package(spdlog 1 REQUIRED)`, asserts `spdlog_DIR` points at
the CPS description, and links `spdlog::spdlog`. spdlog's CPS
requires `fmt:fmt` and `Threads:Threads`; both resolve transitively
(fmt itself via CPS), and the resulting binary runs in `doCheck`.

## Design notes

- **Absolute paths in generated CPS are fine in Nix.** CMake writes
  store-absolute `includes`/`location` (our hooks set absolute
  GNUInstallDirs) and `@prefix@`-relative `cps_path`. Store paths are
  immutable, so non-relocatable descriptions are not a correctness
  issue; they do mean a `.cps` file is only meaningful inside its
  store closure, exactly like CMake-script exports today.
- **Multi-output derivations** work because locations are absolute:
  headers in `dev`, libraries in `out` are recorded as-is.
- **CPS and the provider coexist.** The provider still logs/intercepts
  `find_package` (discovery, REQUIRED enforcement); with the search
  fix above it no longer distorts *which* description CMake picks,
  so CMake's CPS preference applies.
- **Nothing here is required.** CPS generation is opt-in per package,
  consumption needs no gates with CMake ≥ 4.3, and projects without
  `install(EXPORT)` simply have nothing to map.

## Next steps (not yet implemented)

1. **More compat descriptions** for module-only packages that appear
   in generated `requires` (candidates as encountered: e.g.
   `OpenSSL`, `ZLIB` are config/module hybrids — add only with a
   failing consumer in hand).
2. **CPS as a discovery input.** When a fetched source ships `.cps`
   files (or after `cmake2nix`-style generation), `parseCPSDir` can
   feed `generateLock` the same dependency graph the File API does,
   without configuring the project.
3. **Dynamic-derivation awareness.** The dynamic producer's generator
   could prefer CPS-providing inputs and pass `cps.exports` through
   to the generated build (the serialisable shape already fits).
4. **Upstreaming.** The mapped-info flags and Threads description are
   generic; both are candidates for nixpkgs' cmake hook / a
   `cmake-cps-compat` package there.
5. **Gate UUID maintenance.** The cps gate will rotate; keep
   `cpsGateUuids` in sync when bumping the in-tree CMake (the build
   fails loudly at configure time if it drifts, and the
   `cps-consumption` check covers it).

## References

- [CPS specification](https://cps-org.github.io/cps/) and
  [schema](https://cps-org.github.io/cps/schema.html)
- CMake docs: `find_package` (CPS search + version selection),
  `install(PACKAGE_INFO)`, `CMAKE_INSTALL_EXPORTS_AS_PACKAGE_INFO`,
  `Help/dev/experimental.rst` (gate UUIDs) — in the CMake source tree
- [Kitware: Navigating CMake Dependencies with CPS](https://www.kitware.com/navigating-cmake-dependencies-with-cps/)
