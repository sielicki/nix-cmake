{ lib, pkgs }:

let
  defaultDependencyHook =
    (pkgs.callPackage ../pkgs/cmake-dependency-hook { }).setupHook;

  dependencyHookFile = ../pkgs/cmake-dependency-hook/cmakeBuildHook.cmake;

  # Dynamic derivations are strictly opt-in. `builtins.outputOf` only
  # exists when the evaluating Nix has the dynamic-derivations
  # experimental feature enabled, which makes it a reliable
  # feature-detection probe. Nothing in the rest of nix-cmake (builders,
  # workspace, hooks) requires either dynamic derivations or
  # import-from-derivation; this module just stays dormant without them.
  # Note the daemon additionally needs ca-derivations and recursive-nix
  # at build time, which cannot be probed at evaluation time.
  available = builtins ? outputOf;

  /*
    buildCMakePackage builds a CMake project with dynamic derivations
    (RFC 92) instead of import-from-derivation.

    Evaluation only creates two ordinary derivations:

    1. A text-hashed *producer* derivation (name ends in `.drv`) that runs
       a CMake discovery configure, validates the discovered dependencies
       against `cmake-lock.json`, generates a self-contained `build.nix`,
       and instantiates it with recursive Nix. Its output is the `.drv`
       file for the real build.
    2. A wrapper derivation whose input is
       `builtins.outputOf producer "out"`. Nix builds the producer,
       resolves the generated derivation, builds it, and only then builds
       the wrapper — all inside a single `nix build` invocation.

    Unlike `workspace.extractFromDiscoveryLog`/`generateLock`, no
    derivation output is read during evaluation, so evaluation stays
    instant and does not need `--allow-import-from-derivation`.

    Opt-in only: using this function requires the experimental features
      ca-derivations, dynamic-derivations, recursive-nix
    (see `available` below). The rest of nix-cmake requires neither.

    Dependency hashes still come from the checked-in lock file: sandbox
    builders have no network access, so fetching cannot be discovered
    dynamically. Discovery decides *which* dependencies the generated
    build needs and fails early when the lock file is incomplete.

    Arguments mirror `builders.buildCMakePackage` where practical.
    `lockFile` defaults to `<src>/cmake-lock.json`. Because the real
    build is generated at build time, only serialisable attributes can
    be passed through: `nativeBuildInputs`/`buildInputs` (derivations,
    embedded by store path), `env` (string -> string), `doCheck`,
    and string phases (`checkPhase`, `installPhase`).
  */
  buildCMakePackageImpl =
    { pname
    , version
    , src
    , lockFile ? null
    , cmake ? (pkgs.cmakeMinimal or pkgs.cmake)
    , cmakeDependencyHook ? defaultDependencyHook
    , cmakeToolchainFile ? (pkgs.callPackage ../pkgs/cmake-toolchain-hook/cmake-toolchain.nix { } pkgs.stdenv)
    , cmakeFlags ? [ ]
    , nativeBuildInputs ? [ ]
    , buildInputs ? [ ]
    , env ? { }
    , doCheck ? false
    , checkPhase ? null
    , installPhase ? null
    , meta ? { }
    }:
    let
      # Nix requires the generated derivation's name to match the producer's
      # output file name (minus `.drv`). stdenv names a derivation
      # `pname-version`, so the producer must use that full name.
      generatedName = if version == "" then pname else "${pname}-${version}";

      producer = pkgs.runCommand "${generatedName}.drv"
        {
          nativeBuildInputs = [
            cmake
            pkgs.ninja
            pkgs.git
            pkgs.cacert
            pkgs.python3
            pkgs.nix
          ];

          outputHashMode = "text";
          outputHashAlgo = "sha256";
          requiredSystemFeatures = [ "recursive-nix" ];

          # Configuration consumed by ./dynamic-generate.py
          DYNAMIC_PNAME = pname;
          DYNAMIC_VERSION = version;
          DYNAMIC_SRC = "${src}";
          DYNAMIC_NIXPKGS = "${pkgs.path}";
          DYNAMIC_CMAKE = "${cmake}";
          DYNAMIC_DEPENDENCY_HOOK =
            lib.optionalString (cmakeDependencyHook != null) "${cmakeDependencyHook}";
          DYNAMIC_LOCK_FILE =
            if lockFile == null then "${src}/cmake-lock.json" else "${lockFile}";
          DYNAMIC_CMAKE_FLAGS = lib.concatStringsSep "\n" cmakeFlags;
          DYNAMIC_NATIVE_INPUTS =
            lib.concatMapStringsSep " " (input: "${input}") nativeBuildInputs;
          DYNAMIC_BUILD_INPUTS =
            lib.concatMapStringsSep " " (input: "${input}") buildInputs;
          # Plain string->string map; values must not reference derivations
          # (use nativeBuildInputs/buildInputs for those).
          DYNAMIC_EXTRA_ENV = builtins.toJSON env;
          DYNAMIC_DO_CHECK = if doCheck then "1" else "";
          DYNAMIC_CHECK_PHASE = lib.optionalString (checkPhase != null) checkPhase;
          DYNAMIC_INSTALL_PHASE = lib.optionalString (installPhase != null) installPhase;

          CMAKE_TOOLCHAIN_FILE_PATH = "${cmakeToolchainFile}";
          CMAKE_DEPENDENCY_HOOK_FILE = "${dependencyHookFile}";
          GENERATOR = ./dynamic-generate.py;
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        } ''
        cp -r "$DYNAMIC_SRC" src
        chmod -R u+w src
        cd src

        export DYNAMIC_DISCOVERY_LOG="$PWD/discovery-log.json"

        # Discovery configure: same flags as workspace.discoverDependencies.
        # Configure is allowed to fail (stubbed dependencies), the log is
        # what matters. cmakeFlags are newline-separated, one flag per
        # line, so flags containing spaces survive intact.
        _flags_array=()
        if [[ -n "$DYNAMIC_CMAKE_FLAGS" ]]; then
          mapfile -t _flags_array <<< "$DYNAMIC_CMAKE_FLAGS"
        fi
        cmake -S . -B build \
          -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE_PATH" \
          -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES="$CMAKE_DEPENDENCY_HOOK_FILE" \
          -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
          -DCMAKE_C_COMPILER_WORKS=1 \
          -DCMAKE_CXX_COMPILER_WORKS=1 \
          -DNIX_CMAKE_DISCOVERY_MODE=1 \
          -DNIX_CMAKE_DISCOVERY_LOG="$DYNAMIC_DISCOVERY_LOG" \
          "''${_flags_array[@]}" || true

        export DYNAMIC_OUTPUT="$PWD/build.nix"
        python3 "$GENERATOR"

        drv=$(nix-instantiate build.nix)
        echo "nix-cmake dynamic: instantiated $drv"
        cp "$drv" "$out"
      '';

      wrapper = pkgs.runCommand pname
        {
          inherit version meta;
        } ''
        mkdir -p "$out"
        cp -r ${builtins.outputOf producer.outPath "out"}/. "$out"/
        chmod -R u+w "$out"
      '';
    in
    wrapper.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        # The text-hashed derivation that produces the real build's .drv.
        # Useful for debugging: `nix build .#<pkg>.producer` style access
        # via passthru in `nix eval`, or `nix log` on its drvPath.
        inherit producer;
      };
    });

  buildCMakePackage = args:
    if available then buildCMakePackageImpl args
    else
      throw ''
        nix-cmake: lib.dynamic.buildCMakePackage requires the Nix
        experimental features ca-derivations, dynamic-derivations and
        recursive-nix, which are not enabled for this evaluation
        (builtins.outputOf is unavailable).

        Enable them (e.g. in nix.conf:
          experimental-features = ca-derivations dynamic-derivations recursive-nix
        ) to use dynamic derivations, or use
        lib.builders.buildCMakePackage / workspace.buildPackage instead,
        which require neither dynamic derivations nor
        import-from-derivation.
      '';

in
{
  inherit available buildCMakePackage;
}
