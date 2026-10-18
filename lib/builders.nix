{ lib, pkgs }:

let
  # Experimental gate UUIDs for CMAKE_EXPERIMENTAL_MAPPED_PACKAGE_INFO,
  # keyed by CMake version. CMake deliberately rotates these; values
  # come from Help/dev/experimental.rst in the respective CMake source
  # tree. Only versions verified by this repository are listed; pass
  # `cps.gateUuid` explicitly for other CMake versions.
  cpsGateUuids = {
    "4.4.3" = "ababa1b5-7099-495f-a9cd-e22d38f274f2";
  };

  cpsGateFor = cmake:
    let
      version = cmake.version or null;
    in
    if version != null && cpsGateUuids ? ${version} then cpsGateUuids.${version}
    else if version != null && lib.versions.majorMinor version == "4.4" then
      lib.warn "nix-cmake: assuming the CMake 4.4.3 CPS gate UUID also applies to CMake ${version}; pass cps.gateUuid if CPS generation is rejected"
        cpsGateUuids."4.4.3"
    else
      throw "nix-cmake: no known CMAKE_EXPERIMENTAL_MAPPED_PACKAGE_INFO gate UUID for CMake version ${toString version}; pass cps.gateUuid explicitly (see Help/dev/experimental.rst in your CMake's source tree)";

  /*
    cpsFlagsFor renders CMake flags that make install(EXPORT) also
    install CPS package information (CMake >= 4.3, experimental gate),
    without modifying the upstream project. See docs/CPS-INTEGRATION.md.

    cps = {
      gateUuid ? null;           # default: known gate for `cmake`
      exports = [{
        export;                  # install(EXPORT <export>) name
        package;                 # find_package(<package>) name
        version ? "@PROJECT_VERSION@";  # @VAR@ expanded by CMake
        compatVersion ? null;    # oldest compatible version
        versionSchema ? null;
        license ? null;          # SPDX expression
        appendix ? null;
        lowerCase ? false;
        destination ? null;
      }];
    }
  */
  cpsFlagsFor = { cmake, cps }:
    let
      directiveFor = e:
        let
          appendix = e.appendix or null;
          destination = e.destination or null;
          suffix =
            lib.optionalString ((e.lowerCase or false) || appendix != null || destination != null)
              ("/" + lib.optionalString (e.lowerCase or false) "l"
                + lib.optionalString (appendix != null) "a${appendix}"
                + lib.optionalString (destination != null) "/${destination}");
        in
        "${e.export}:${e.package}${suffix}";

      metadataFor = e:
        let
          prefix = "${e.export}_EXPORT_PACKAGE_INFO_";
          isAppendix = (e.appendix or null) != null;
          version = e.version or (if isAppendix then null else "@PROJECT_VERSION@");
          fields = lib.filterAttrs (_: v: v != null) {
            VERSION = version;
            COMPAT_VERSION = e.compatVersion or null;
            VERSION_SCHEMA = e.versionSchema or null;
            LICENSE = e.license or null;
          };
        in
        lib.mapAttrsToList (k: v: "-D${prefix}${k}=${v}") fields;
    in
    [
      "-DCMAKE_EXPERIMENTAL_MAPPED_PACKAGE_INFO=${cps.gateUuid or (cpsGateFor cmake)}"
      "-DCMAKE_INSTALL_EXPORTS_AS_PACKAGE_INFO=${lib.concatStringsSep ";" (map directiveFor cps.exports)}"
    ] ++ lib.concatMap metadataFor cps.exports;

  # A fetchContentDeps entry may be a source derivation/path directly,
  # or an attrset with a `src` attribute (the shape produced by
  # cmake2nix's cmake-packages.nix and by mkProjectOverlay).
  depSrc = dep:
    if lib.isDerivation dep || builtins.isPath dep || builtins.isString dep then dep
    else dep.src or null;

  normalizedSrcs = deps:
    lib.filterAttrs (_: src: src != null)
      (lib.mapAttrs (_: depSrc) deps);

  fetchContentEnvFor = deps:
    lib.mapAttrs'
      (name: src:
        lib.nameValuePair "FETCHCONTENT_SOURCE_DIR_${lib.toUpper name}" "${src}"
      )
      (normalizedSrcs deps);

  # FETCHCONTENT_SOURCE_DIR_* as cache variables. Unlike environment
  # variables (which only take effect through cmakeBuildHook.cmake),
  # -D cache entries are honoured by FetchContent directly, so
  # fetchContentDeps also work with cmakeDependencyHook = null.
  fetchContentFlagsFor = deps:
    lib.mapAttrsToList
      (name: src: "-DFETCHCONTENT_SOURCE_DIR_${lib.toUpper name}=${src}")
      (normalizedSrcs deps);

  /*
    applyLockFile returns the FETCHCONTENT_SOURCE_DIR_* environment
    variables for a parsed lock file, instantiating its fetchers
    (entries may be overridden via `fetchers`).
  */
  applyLockFile = { lock, fetchers ? { } }:
    let
      workspace = import ./workspace.nix { inherit lib pkgs; };
    in
    fetchContentEnvFor (workspace.lockFetchers { inherit lock fetchers; });

  /*
    buildCMakePackage is a high-level builder that automatically
    applies the nix-cmake hooks and manages dependencies.

    Extra arguments are forwarded to stdenv.mkDerivation.
  */
  buildCMakePackage =
    { pname
    , version
    , src
    , cmake ? (pkgs.cmakeMinimal or pkgs.cmake)
    , cmakeToolchainHook ? null
    , cmakeDependencyHook ? (pkgs.callPackage ../pkgs/cmake-dependency-hook { }).setupHook
    , cmakeFlags ? [ ]
    , fetchContentDeps ? { }
    , lockFile ? null
    , cmakeArtifacts ? null
    , cps ? null
    , cpsCompat ? true
    , ...
    } @ args:
    let
      workspace = import ./workspace.nix { inherit lib pkgs; };
      lock =
        if lockFile == null then { dependencies = { }; }
        else builtins.fromJSON (builtins.readFile lockFile);

      lockSrcs = workspace.lockFetchers { inherit lock; };
      allDeps = lockSrcs // fetchContentDeps;

      drvArgs = builtins.removeAttrs args [
        "cmake"
        "cmakeToolchainHook"
        "cmakeDependencyHook"
        "fetchContentDeps"
        "lockFile"
        "cmakeArtifacts"
        "cmakeFlags"
        "cps"
        "cpsCompat"
      ];

      finalAttrs = drvArgs // fetchContentEnvFor allDeps // {
        inherit pname version src;

        # CPM.cmake: prefer local packages (find_package) before downloading
        CPM_USE_LOCAL_PACKAGES = "ON";

        nativeBuildInputs = (args.nativeBuildInputs or [ ]) ++ [
          cmake
          pkgs.ninja
        ]
          # CPS descriptions for module-only packages (Threads), so CPS
          # transitive requirements can resolve. Data-only; set
          # cpsCompat = false to opt out.
          ++ lib.optional cpsCompat (pkgs.callPackage ../pkgs/cmake-cps-compat { })
          ++ lib.optional (cmakeToolchainHook != null) cmakeToolchainHook
          ++ lib.optional (cmakeDependencyHook != null) cmakeDependencyHook;

        cmakeFlags = cmakeFlags
          ++ [ "-GNinja" "-DCPM_USE_LOCAL_PACKAGES=ON" ]
          ++ lib.optional (cmakeArtifacts != null) "-DCMAKE_PREFIX_PATH=${cmakeArtifacts}"
          ++ fetchContentFlagsFor allDeps
          ++ lib.optionals (cps != null) (cpsFlagsFor { inherit cmake cps; });
      };

    in
    pkgs.stdenv.mkDerivation finalAttrs;

  /*
    buildDepsOnly builds the project and installs its build tree to
    $out for reuse as `cmakeArtifacts` seed input.

    NOTE: This is not a true dependencies-only build (CMake offers no
    generic way to build only FetchContent-provided targets); it builds
    the default target and preserves the build directory. It mainly
    serves as a cache-warming step. Prefer splitting real dependency
    packages with mkProjectOverlay where possible.
  */
  buildDepsOnly = args:
    lib.warn "nix-cmake: buildDepsOnly is experimental; it preserves the full build tree, it does not isolate dependency targets"
      (buildCMakePackage (args // {
        pname = "${args.pname or "project"}-deps";
        cmakeFlags = (args.cmakeFlags or [ ]) ++ [ "-DNIX_CMAKE_BUILD_DEPS_ONLY=1" ];
        installPhase = args.installPhase or ''
          runHook preInstall
          mkdir -p $out
          cp -r ''${cmakeBuildDir:-build} $out/build
          runHook postInstall
        '';
      }));

in
{
  inherit buildCMakePackage applyLockFile buildDepsOnly cpsFlagsFor cpsGateUuids fetchContentFlagsFor;
}
