# Recursive Dependency Discovery

Many C++ projects form a *tree* of dependencies: the top-level
`CMakeLists.txt` fetches project B with `FetchContent`, and B in turn
fetches its own dependencies. A one-level discovery pass (which stubs
every dependency) never sees B's dependencies.

## Approaches

### 1. Dynamic derivations (preferred for builds)

[`lib.dynamic`](DYNAMIC-DERIVATIONS.md) runs discovery at *build
time* and generates the build graph from its results, with lockfile
hashes providing the sources. This removes import-from-derivation
from the loop entirely.

### 2. Fixed-output discovery (lockfile maintenance)

`workspace.recursiveDiscover` wraps `discoverDependencies` with
`recursive = true` as a fixed-output derivation (FOD). FODs may access
the network, so `FetchContent` is allowed to proceed and nested
dependencies are logged as they are declared. The output hash must be
updated whenever the discovered set changes (the usual FOD workflow:
start from a placeholder hash, copy the correct hash from the error).

```nix
let
  workspace = (nix-cmake.lib.workspace pkgs);
in
workspace.recursiveDiscover {
  src = ./.;
  outputHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
}
```

The result contains `discovery-log.json` (one JSON object per line)
and File API replies under `reply/`:

```bash
nix build .#discovery
cat result/discovery-log.json
```

From a discovery result, a lock file structure can be produced with
`workspace.generateLock`, and sources consumed through
`workspace.loadWorkspace` / `mkProjectOverlay` (see [API.md](API.md)).
Note that reading the discovery result during evaluation is
import-from-derivation; that is fine for interactive lockfile
maintenance, which is what this flow is for.

## Compiler-check handling

Discovery configures with
`CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY` and
`CMAKE_C/CXX_COMPILER_WORKS=1`, so configuration reaches the
dependency declarations even on platforms (e.g. Darwin) whose linker
checks would otherwise fail before any `FetchContent` call runs. A
failed configure still yields whatever log lines were written before
the failure.
