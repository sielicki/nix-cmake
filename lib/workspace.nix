{ lib, pkgs }:

let
  /*
    discoverDependencies runs a guest configuration of the CMake project
    to extract File API replies and Nix-CMake discovery logs.
  */
  discoverDependencies = { 
    src, 
    cmake ? (pkgs.cmakeMinimal or pkgs.cmake), 
    cmakeFlags ? [], 
    nativeBuildInputs ? [],
    cmakeToolchainFile ? (pkgs.callPackage ../pkgs/cmake-toolchain-hook/cmake-toolchain.nix {} pkgs.stdenv),
    cmakeDependencyHookFile ? ../pkgs/cmake-dependency-hook/cmakeBuildHook.cmake,
    recursive ? false
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
    in drv;

  recursiveDiscover = { src, outputHash, outputHashAlgo ? "sha256", ... } @ args:
    (discoverDependencies (args // { recursive = true; })).overrideAttrs (old: {
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
      
      index = if indexFile == null then null 
              else readJSON "${replyDir}/${indexFile}";

      codemodelObj = if (index == null || !builtins.hasAttr "objects" index) then null 
                     else lib.findFirst (o: o.kind == "codemodel") null index.objects;

      codemodelRelPath = if codemodelObj == null then null 
                         else codemodelObj.jsonFile;

      codemodel = if codemodelRelPath == null then null
                  else readJSON "${replyDir}/${codemodelRelPath}";

      targets = if (codemodel == null || builtins.length codemodel.configurations == 0) then []
                else (builtins.elemAt codemodel.configurations 0).targets;

    in map (t: 
      let 
        info = readJSON "${replyDir}/${t.jsonFile}";
      in {
        inherit (t) name id;
        inherit (info) type;
        imported = info.imported or false;
      }
    ) targets;

  extractFromDiscoveryLog = configured:
    let
      logPath = "${configured}/discovery-log.json";
      content = if builtins.pathExists logPath then builtins.readFile logPath else "";
      lines = lib.filter (l: l != "") (lib.splitString "\n" content);
    in map (l: builtins.fromJSON (builtins.unsafeDiscardStringContext l)) lines;

  mkProjectOverlay = { lock, fetchers ? {} }: 
    self: super: 
    let
      # Use the provided fetchers, or fall back to the lock file's fetcher specs
      projectPackages = lib.mapAttrs (name: dep: 
        let 
          # 1. Try explicit fetcher override
          # 2. Try to instantiate the fetcher from the lock file
          # 3. Fall back to null if no source is available
          src = if builtins.hasAttr name fetchers then fetchers.${name} 
                else if dep ? method && dep ? args then (pkgs.${dep.method} dep.args)
                else null;
        in {
          inherit name src;
          pkg = if src == null then null else pkgs.stdenv.mkDerivation {
             name = "${name}-${dep.version or "unknown"}";
             inherit src;
             # Add target metadata for later mapping
             passthru = {
               cmakeTargets = dep.metadata.cmakeTargets or [ name ];
             };
          };
        }
      ) (lock.dependencies or {});
    in {
      cmakeProject = projectPackages;
    };

  loadWorkspace = { workspaceRoot }:
    let
      # Check for cmake-lock.json first (our native format)
      cmakeLockPath = workspaceRoot + "/cmake-lock.json";
      hasCMakeLock = builtins.pathExists cmakeLockPath;

      # Check for CPM's package-lock.cmake
      cpmLockPath = workspaceRoot + "/package-lock.cmake";
      hasCPMLock = builtins.pathExists cpmLockPath;

      # Load the appropriate lock file
      lock =
        if hasCMakeLock then
          builtins.fromJSON (builtins.readFile cmakeLockPath)
        else if hasCPMLock then
          let
            cpmParser = import ./cpm-lock-parser.nix { inherit lib; };
          in
            cpmParser.loadCPMPackageLock cpmLockPath
        else
          { version = "1.0"; dependencies = {}; };

      dependency = import ./dependency.nix { inherit lib; };

      # Auto-generate all fetchers from the lock file
      # No manual specification needed!
      fetchers = lib.mapAttrs (name: dep:
        if dep ? method && dep ? args then
          # Instantiate the fetcher from the lock file
          pkgs.${dep.method} dep.args
        else
          null
      ) (lock.dependencies or {});

      # Filter out null fetchers
      validFetchers = lib.filterAttrs (n: v: v != null) fetchers;

      workspace = rec {
        inherit workspaceRoot lock;

        # Create overlay that provides all dependencies as CMake packages
        mkCMakeOverlay = { sourcePreference ? "source" }:
          mkProjectOverlay {
            inherit lock;
            fetchers = validFetchers;
          };

        # Dependency groups (similar to uv2nix's workspace.deps.all, workspace.deps.default)
        deps = {
          # All dependencies from lock file
          all = builtins.attrNames (lock.dependencies or {});
          # Just the direct dependencies (could parse CMakeLists.txt for this)
          default = builtins.attrNames (lock.dependencies or {});
        };

        # Build the package with lock file dependencies automatically applied
        buildPackage = args:
          let
            builders = import ./builders.nix { inherit lib pkgs; };
          in
          builders.buildCMakePackage (args // {
            src = args.src or workspaceRoot;
            # Auto-inject all fetchers from lock file
            fetchContentDeps = validFetchers;
          });

        # Development shell with all dependencies available
        mkShell = { nativeBuildInputs ? [], ... } @ args:
          let
            # Create a derivation with all dependencies built
            depsEnv = pkgs.stdenv.mkDerivation {
              name = "cmake-deps-env";
              dontUnpack = true;
              dontBuild = true;
              installPhase = "mkdir -p $out";
              # Make all dependencies available
              buildInputs = builtins.attrValues validFetchers;
            };
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
              ) validFetchers)}
              echo "Nix-CMake: Development environment ready"
              echo "Nix-CMake: ${toString (builtins.length deps.all)} dependencies available"
            '';
          });
      };
    in workspace;

  generateLock = configured:
    let
      dependency = import ./dependency.nix { inherit lib; };
      logPath = "${configured}/discovery-log.json";
    in
      dependency.generateLockFromLog logPath;

in {
  inherit discoverDependencies recursiveDiscover extractFromCodemodel extractFromDiscoveryLog mkProjectOverlay loadWorkspace generateLock;
}
