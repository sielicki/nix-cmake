{ lib, pkgs }:

let
  /*
    discoverDependencies runs a guest configuration of the CMake project
    to extract File API replies and Nix-CMake discovery logs.
  */
  discoverDependencies =
    { src
    , cmake ? (pkgs.cmakeMinimal or pkgs.cmake)
    , cmakeFlags ? [ ]
    , nativeBuildInputs ? [ ]
    , cmakeToolchainFile ? (pkgs.callPackage ../pkgs/cmake-toolchain-hook/cmake-toolchain.nix { } pkgs.stdenv)
    , cmakeDependencyHookFile ? ../pkgs/cmake-dependency-hook/cmakeBuildHook.cmake
    , recursive ? false
    }:
    let
      # Setup File API query
      query = builtins.toFile "query.json" (builtins.toJSON {
        requests = [
          { kind = "codemodel"; version = 2; }
          { kind = "cache"; version = 2; }
        ];
      });

      # Use stdenv.mkDerivation for a robust environment
      # Run the configuration in a shell with CMake and Ninja
      # We use a purely local build that doesn't effectively build, just configures
      drv = pkgs.stdenv.mkDerivation {
        name = "cmake-discovery";
        inherit src;

        nativeBuildInputs = [ cmake pkgs.git pkgs.cacert pkgs.ninja ] ++ nativeBuildInputs;

        dontBuild = true;
        dontInstall = true;
        dontUseNixCMakeSetup = true;

        configurePhase = ''
          mkdir -p build/.cmake/api/v1/query/client-nix-cmake
          cp ${query} build/.cmake/api/v1/query/client-nix-cmake/query.json

          mkdir -p $out

          # Configure
          cmake -S . -B build \
            -DCMAKE_TOOLCHAIN_FILE=${cmakeToolchainFile} \
            -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${cmakeDependencyHookFile} \
            -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
            -DCMAKE_C_COMPILER_WORKS=1 \
            -DCMAKE_CXX_COMPILER_WORKS=1 \
            -DNIX_CMAKE_DISCOVERY_MODE=1 \
            -DNIX_CMAKE_DISCOVERY_LOG=$out/discovery-log.json \
            ${lib.optionalString recursive "-DNIX_CMAKE_RECURSIVE_DISCOVERY=1"} \
            ${lib.concatStringsSep " " cmakeFlags} \
            || true

          # Extract File API replies
          mkdir -p $out/reply
          if [ -d build/.cmake/api/v1/reply ]; then
            cp -r build/.cmake/api/v1/reply/* $out/reply/
          fi
        '';

        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      };
    in
    drv;

  recursiveDiscover = { outputHash, outputHashAlgo ? "sha256", ... } @ args:
    (discoverDependencies (args // { recursive = true; })).overrideAttrs (_: {
      inherit outputHash outputHashAlgo;
      outputHashMode = "recursive";
    });

  readJSON = path:
    let content = builtins.readFile path;
    in builtins.fromJSON (builtins.unsafeDiscardStringContext content);

  extractFromCodemodel = configured:
    let
      replyDir = "${configured}/reply";
      indexFiles = builtins.attrNames (builtins.readDir replyDir);
      indexFile = lib.findFirst (f: lib.hasPrefix "index-" f) null indexFiles;

      index =
        if indexFile == null then null
        else readJSON "${replyDir}/${indexFile}";

      codemodelObj =
        if (index == null || !builtins.hasAttr "objects" index) then null
        else lib.findFirst (o: o.kind == "codemodel") null index.objects;

      codemodelRelPath =
        if codemodelObj == null then null
        else codemodelObj.jsonFile;

      codemodel =
        if codemodelRelPath == null then null
        else readJSON "${replyDir}/${codemodelRelPath}";

      targets =
        if (codemodel == null || builtins.length codemodel.configurations == 0) then [ ]
        else (builtins.elemAt codemodel.configurations 0).targets;

    in
    map
      (t:
        let
          info = readJSON "${replyDir}/${t.jsonFile}";
        in
        {
          inherit (t) name id;
          inherit (info) type;
          imported = info.imported or false;
        }
      )
      targets;

  # NOTE: reads a derivation output during evaluation (import-from-
  # derivation). Prefer lib/dynamic.nix for new code; this remains for
  # interactive lock-file workflows where IFD is acceptable.
  extractFromDiscoveryLog = configured:
    let
      logPath = "${configured}/discovery-log.json";
      content = if builtins.pathExists logPath then builtins.readFile logPath else "";
      lines = lib.filter (l: l != "") (lib.splitString "\n" content);
    in
    map (l: builtins.fromJSON (builtins.unsafeDiscardStringContext l)) lines;

  # Instantiate the source fetchers described by a lock file.
  # Returns an attrset of dependency name -> source (or null when the
  # lock entry has no usable fetcher specification). Entries may be
  # overridden per-name via `fetchers`.
  lockFetchers = { lock, fetchers ? { } }:
    lib.mapAttrs
      (name: dep:
        if builtins.hasAttr name fetchers then fetchers.${name}
        else if dep ? method && dep ? args && dep.method != null then (pkgs.${dep.method} dep.args)
        else null
      )
      (lock.dependencies or { });

  mkProjectOverlay = { lock, fetchers ? { } }:
    _final: _prev:
      let
        srcs = lockFetchers { inherit lock fetchers; };
        builders = import ./builders.nix { inherit lib pkgs; };

        projectPackages = lib.mapAttrs
          (name: dep:
            let
              src = srcs.${name};
              version =
                let v = dep.version or null;
                in if v == null then "unknown" else v;
            in
            {
              inherit name src;
              # A best-effort standalone build of the dependency, for use
              # via find_package() by other projects. Evaluated lazily.
              pkg =
                if src == null then null
                else
                  (builders.buildCMakePackage {
                    pname = name;
                    inherit version src;
                  }).overrideAttrs (old: {
                    passthru = (old.passthru or { }) // {
                      cmakeTargets = dep.metadata.cmakeTargets or [ name ];
                    };
                  });
            }
          )
          (lock.dependencies or { });
      in
      {
        cmakeProject = projectPackages;
      };

  loadWorkspace = { workspaceRoot, lockFile ? null }:
    let
      # Check for cmake-lock.json first (our native format)
      cmakeLockPath = workspaceRoot + "/cmake-lock.json";
      hasCMakeLock = builtins.pathExists cmakeLockPath;

      # Check for CPM's package-lock.cmake
      cpmLockPath = workspaceRoot + "/package-lock.cmake";
      hasCPMLock = builtins.pathExists cpmLockPath;

      # Load the appropriate lock file (explicit lockFile wins)
      lock =
        if lockFile != null then
          builtins.fromJSON (builtins.readFile lockFile)
        else if hasCMakeLock then
          builtins.fromJSON (builtins.readFile cmakeLockPath)
        else if hasCPMLock then
          let
            cpmParser = import ./cpm-lock-parser.nix { inherit lib; };
          in
          cpmParser.loadCPMPackageLock cpmLockPath
        else
          { version = "1.0"; dependencies = { }; };

      # Auto-generate all fetchers from the lock file.
      validFetchers = lib.filterAttrs (_: v: v != null)
        (lockFetchers { inherit lock; });

      workspace = rec {
        inherit workspaceRoot lock;

        # Create overlay that provides all dependencies as CMake packages.
        # `sourcePreference` is accepted for backwards compatibility but
        # currently only "source" (build from fetched sources) exists.
        mkCMakeOverlay = { sourcePreference ? "source" }:
          lib.warnIf (sourcePreference != "source")
            "nix-cmake: sourcePreference '${sourcePreference}' is not implemented; using \"source\""
            (mkProjectOverlay {
              inherit lock;
              fetchers = validFetchers;
            });

        # Dependency groups (similar to uv2nix's workspace.deps).
        # `default` currently equals `all`: which lock entries are direct
        # dependencies is not recorded in the lock file yet.
        deps = {
          all = builtins.attrNames (lock.dependencies or { });
          default = deps.all;
        };

        # Build the package with lock file dependencies automatically applied.
        # Explicit `fetchContentDeps` in args extend/override the lock file.
        buildPackage = args:
          let
            builders = import ./builders.nix { inherit lib pkgs; };
          in
          builders.buildCMakePackage (args // {
            src = args.src or workspaceRoot;
            fetchContentDeps = validFetchers // (args.fetchContentDeps or { });
          });

        # Development shell with all dependency sources available via
        # FETCHCONTENT_SOURCE_DIR_* environment variables.
        mkShell = { nativeBuildInputs ? [ ], ... } @ args:
          let
            # Bash cannot export variables with '-' (or other non-identifier
            # characters) in their name, so only export deps whose
            # FetchContent name is a valid shell identifier.
            shellFetchers = lib.filterAttrs
              (name: _: builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null)
              validFetchers;
          in
          pkgs.mkShell (args // {
            nativeBuildInputs = nativeBuildInputs ++ [
              (pkgs.cmakeMinimal or pkgs.cmake)
              pkgs.ninja
            ];
            shellHook = (args.shellHook or "") + ''
              export CMAKE_EXPORT_COMPILE_COMMANDS=ON
              ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: src:
                "export FETCHCONTENT_SOURCE_DIR_${lib.toUpper name}=${src}"
              ) shellFetchers)}
              echo "Nix-CMake: Development environment ready"
              echo "Nix-CMake: ${toString (builtins.length deps.all)} dependencies available"
            '';
          });
      };
    in
    workspace;

  generateLock = configured:
    let
      dependency = import ./dependency.nix { inherit lib; };
      logPath = "${configured}/discovery-log.json";
    in
    dependency.generateLockFromLog logPath;

in
{
  inherit discoverDependencies recursiveDiscover extractFromCodemodel extractFromDiscoveryLog lockFetchers mkProjectOverlay loadWorkspace generateLock;
}
