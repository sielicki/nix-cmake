{ lib, pkgs }:

let
  /*
    applyLockFile takes a lock file structure and returns environment variables
    for the dependency provider.
  */
  applyLockFile = { lock, fetchers ? {} }:
    let
      # fetchers is a map of { depName = derivation; }
      # If not provided in fetchers, we might try to derive it (future)
      
      envVars = lib.mapAttrs' (name: src: 
        lib.nameValuePair "NIX_FETCHCONTENT_${name}_SOURCE_DIR" "${src}"
      ) fetchers;
    in envVars;

  /*
    buildCMakePackage is a high-level builder that automatically 
    applies the nix-cmake hooks and manage dependencies.
  */
  buildCMakePackage = {
    pname,
    version,
    src,
    cmake ? (pkgs.cmakeMinimal or pkgs.cmake),
    cmakeToolchainHook ? null,  # Optional - most projects don't need custom toolchain
    cmakeDependencyHook ? (pkgs.callPackage ../pkgs/cmake-dependency-hook/default.nix { inherit cmake; }).setupHook,
    cmakeFlags ? [],
    fetchContentDeps ? {},
    lockFile ? null,
    cmakeArtifacts ? null,
    ...
  } @ args:
    let
      # Use provided fetchers or derive from lockFile
      workspace = import ./workspace.nix { inherit lib pkgs; };
      lock = if lockFile == null then {} else builtins.fromJSON (builtins.readFile lockFile);
      
      # Merge explicit deps with lock-derived ones
      allDeps = (workspace.mkProjectOverlay { inherit lock; } pkgs pkgs).cmakeProject // 
                lib.mapAttrs (n: v: { name = n; src = v; pkg = null; }) fetchContentDeps;

      # Filter out our custom arguments
      drvArgs = builtins.removeAttrs args [ 
        "cmake" "cmakeToolchainHook" "cmakeDependencyHook" "fetchContentDeps" "lockFile" "cmakeArtifacts"
      ];

      # Inject FetchContent dependencies via environment variables
      fetchContentEnv = lib.mapAttrs' (name: dep:
        lib.nameValuePair "FETCHCONTENT_SOURCE_DIR_${lib.toUpper name}" "${dep.src}"
      ) (lib.filterAttrs (n: d: d.src != null) allDeps);

      finalAttrs = drvArgs // fetchContentEnv // {
        inherit pname version src;

        # CPM.cmake configuration: prefer local packages (find_package) before downloading
        CPM_USE_LOCAL_PACKAGES = "ON";

        nativeBuildInputs = (args.nativeBuildInputs or []) ++ [
          cmake pkgs.ninja
        ] ++ lib.optional (cmakeToolchainHook != null) cmakeToolchainHook
          ++ lib.optional (cmakeDependencyHook != null) cmakeDependencyHook;

        cmakeFlags = (args.cmakeFlags or [])
          ++ cmakeFlags
          ++ [ "-GNinja" ]
          ++ [ "-DCPM_USE_LOCAL_PACKAGES=ON" ]  # Try find_package before downloading
          ++ (lib.optional (cmakeArtifacts != null) "-DCMAKE_PREFIX_PATH=${cmakeArtifacts}");

        # If we have artifacts, we might want to copy them in or use a specific build dir
        preConfigure = (args.preConfigure or "") + lib.optionalString (cmakeArtifacts != null) ''
          # If we have incremental artifacts, we might want to seed the build directory
          # This is a simplified version; a full implementation would use --preset or similar.
        '';
      };

    in pkgs.stdenv.mkDerivation finalAttrs;

  /*
    buildDepsOnly creates a derivation that builds only the dependencies of a project.
  */
  buildDepsOnly = { src, ... } @ args:
    buildCMakePackage (args // {
      pname = "${args.pname or "project"}-deps";
      # We use a dummy configure/build that triggers dependency fetching but doesn't build the main app
      # This is project-specific but we can try a generic approach by setting a flag
      cmakeFlags = (args.cmakeFlags or []) ++ [ "-DNIX_CMAKE_BUILD_DEPS_ONLY=1" ];
      
      # We override the build phase to only build the dependencies
      # In many projects, this means just configuring or building specific targets
      buildPhase = args.buildPhase or ''
        cmake --build . --target all # Or a more discovery-based approach
      '';
      
      installPhase = ''
        mkdir -p $out
        cp -r . $out/
      '';
    });

in {
  inherit buildCMakePackage applyLockFile buildDepsOnly;
}
