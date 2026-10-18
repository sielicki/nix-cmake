# Dynamic Derivations

`lib/dynamic.nix` builds CMake projects using Nix **dynamic derivations**
([RFC 92](https://github.com/NixOS/rfcs/blob/master/rfcs/0092-plan-dynamism.md))
instead of import-from-derivation (IFD).

## Why

The classic nix-cmake flow is two-phase:

1. Run a discovery configure (`workspace.discoverDependencies`) that logs
   every intercepted `FetchContent`/`find_package` call.
2. Read that log **during evaluation** (`extractFromDiscoveryLog`,
   `generateLock`) to decide what to build next.

Step 2 is IFD: evaluation blocks on a build, `nix flake check` needs
`--allow-import-from-derivation`, and nixpkgs-style code review rejects it.

Dynamic derivations move step 2 into the build graph. Evaluation stays
pure and instant; a single `nix build` performs discovery, generates the
real build derivation, and builds it.

## How it works

`dynamic.buildCMakePackage` creates two derivations at evaluation time:

1. **Producer** — a text-hashed (`outputHashMode = "text"`) derivation
   whose name ends in `.drv`. Its builder:
   - copies `src` to a writable directory and runs the same discovery
     configure as `discoverDependencies` (dependency provider in
     discovery mode, compiler checks bypassed);
   - runs `lib/dynamic-generate.py`, which validates every discovered
     dependency against `cmake-lock.json` and renders a self-contained
     `build.nix` (stdenv build, lock-file fetchers injected as
     `FETCHCONTENT_SOURCE_DIR_*`);
   - instantiates `build.nix` with recursive Nix (`nix-instantiate`)
     and copies the resulting `.drv` file to `$out`.
2. **Wrapper** — an ordinary derivation that copies
   `builtins.outputOf producer.outPath "out"` into its own `$out`.
   Nix builds the producer first, *resolves* the generated derivation,
   builds it, substitutes the resulting path, and only then builds the
   wrapper.

One naming invariant is imposed by Nix: the generated derivation's name
must equal the producer's output file name minus `.drv`. Since stdenv
names derivations `pname-version`, the producer is named
`"<pname>-<version>.drv"`.

## Optional, feature-detected

Dynamic derivations are **strictly opt-in**: nothing in nix-cmake —
the flake outputs, builders, workspace, or hooks — requires them (or
import-from-derivation). This module is only *used* when the
evaluating Nix has the feature enabled, detected at evaluation time
via `builtins ? outputOf` and exposed as `lib.dynamic.available`.
Calling `buildCMakePackage` without it fails with an explanation
rather than breaking evaluation, and this repo's dynamic flake check
is simply absent (not failing) in that configuration.

To use it, enable these experimental features for your Nix (the
daemon additionally needs `recursive-nix` in `system-features` for
recursive-Nix builders, which the producer requests via
`requiredSystemFeatures`):

```ini
experimental-features = ca-derivations dynamic-derivations recursive-nix
```

## Usage

```nix
let
  dynamic = nix-cmake.lib.dynamic pkgs;
in
dynamic.buildCMakePackage {
  pname = "my-app";
  version = "0.1.0";
  src = ./.;
  lockFile = ./cmake-lock.json;   # default: <src>/cmake-lock.json
  cmakeFlags = [ "-DMY_OPTION=ON" ];
  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.openssl ];
  doCheck = true;
  checkPhase = "./test_app";
}
```

Because the real build is generated at build time, only serialisable
arguments can be passed through: derivations for `nativeBuildInputs` /
`buildInputs` (embedded by store path), plain strings for `env`, and
string `checkPhase`/`installPhase`. Arbitrary `stdenv.mkDerivation`
arguments are available in the classic `builders.buildCMakePackage`.

The producer is exposed as `passthru.producer` for debugging
(`nix log` on its derivation shows the discovery and generation output).

## Lock files still provide the hashes

Discovery decides *which* dependencies a project needs, but it cannot
fetch them: sandbox builders have no network, and fixed-output fetchers
need hashes up front. Hashes therefore still come from the checked-in
`cmake-lock.json` (maintained with the discovery package or
`cmake2nix lock`).

What the producer adds on top of the classic flow:

- The lock file is **validated against an actual CMake configure** on
  every build. A dependency that CMake requests but the lock file does
  not provide fails the producer with an actionable error, instead of
  failing (or silently downloading) halfway through the real build.
- Lock entries that discovery did not observe are still included, with
  a note in the log. This matters for CPM: dependencies fetched via
  `FetchContent_Populate` bypass the dependency provider and may not
  appear in the discovery log.

## Verification

`tests/dynamic` is wired up as the flake check `dynamic-fetchcontent`.
It also builds with IFD explicitly disabled, which is the point of the
exercise:

```bash
nix build .#checks.x86_64-linux.dynamic-fetchcontent \
  --option allow-import-from-derivation false
```

Evaluation of a dynamic package prints a placeholder path
(`/0…`-style) and completes immediately — no derivation is built while
evaluating.

## Limitations

- Generated builds always use the in-tree hooks and `-GNinja`.
- One generated derivation per project. Splitting per-target or
  per-dependency derivations from File API metadata is possible with
  the same mechanism and is future work (see ROADMAP).
- `cmakeFlags` are transported one flag per line; a single flag cannot
  contain a newline.
