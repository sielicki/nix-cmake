{ installShellFiles
, buildPackages
, callPackage
, darwin
, fetchFromGitHub
, git
, gitUpdater
, lib
, libidn2
, makeBinaryWrapper
, ninja
, ps
, sysctl
, stdenv
, #  zlib,
  #curlMinimal ? null,
}:
let
  pkg = stdenv.mkDerivation rec {
    pname = "cmakeMinimal";
    version = "4.2.1";

    src = fetchFromGitHub {
      owner = "Kitware";
      repo = "CMake";
      rev = "v${version}";
      hash = "sha256-lZ46Zq2HUDFw8J2kj4C6aclEWXy1MNOIKD9PVQ9WP8s=";
    };


    depsBuildBuild = with buildPackages; [ stdenv.cc ninja which ];

    # Don't use cmakeDependencyHook during bootstrap - it would interfere
    # Include tools needed for the bootstrap build itself
    nativeBuildInputs = [
      installShellFiles
      makeBinaryWrapper
      ps
      sysctl
    ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
      darwin.DarwinTools # sw_vers
      darwin.system_cmds # vm_stat
    ];

    outputs = [ "out" ];
    separateDebugInfo = true;
    setOutputFlags = false;

    # Provide basic CMake setup hook for packages that use cmakeMinimal as a build dependency
    setupHooks = [ ./setup-hook.sh ];

    buildInputs = [ (lib.getDev libidn2) (lib.getLib libidn2) ] ++
      #  (lib.optionals (curlMinimal == null) [
      #  (lib.getDev curlMinimal) (lib.getLib curlMinimal) 
      #  (lib.getDev zlib) (lib.getLib zlib) 
      #])#  
      [ ];

    configureFlags = (lib.cli.toGNUCommandLine
      {
        optionValueSeparator = "=";
        mkBool = k: v:
          if (lib.strings.hasPrefix "system" k) then [ "--${if v then "" else "no-"}${k}" ]
          else lib.optionals v [ "--${k}" ]
        ;
      }
      {
        #system-curl = (curlMinimal != null);
        #system-zlib = (curlMinimal != null);
        system-curl = false;
        system-zlib = false;
        generator = "Ninja";
        system-libs = false;
        system-expat = false;
        system-jsoncpp = false;
        system-bzip2 = false;
        system-liblzma = false;
        system-nghttp2 = false;
        system-zstd = false;
        system-libarchive = false;
        system-librhash = false;
        system-libuv = false;

        enable-ccache = stdenv.cc.isCcache or false;
        parallel = "$NIX_BUILD_CORES";

        prefix = builtins.placeholder "out";
        bindir = "bin";
        datadir = "share";
        xdgdatadir = "share";
        docdir = "share/doc";
        mandir = "share/man";
        sphinx-info = false;
        sphinx-man = false;
        bootstrap-system-libuv = false;
        bootstrap-system-jsoncpp = false;
        bootstrap-system-librhash = false;
        system-cppdap = false;
        verbose = true;
        # NOTE: Don't use --init during bootstrap!
        # The bootstrap process doesn't use project() in the normal way,
        # so CMAKE_PROJECT_TOP_LEVEL_INCLUDES would try to set the dependency
        # provider outside of project() context, which is an error.
        # The bootstrap build doesn't need FetchContent interception anyway.
        # init = "${../cmake-dependency-hook/cmakeBuildHook.cmake}";
      }) ++ [
      "--"
      "-DCMAKE_USE_OPENSSL=OFF"
    ];


    dontUseNixCMakeSetup = true;
    configureScript = "./bootstrap";
    enableParallelBuilding = true;

    # Wrap cmake binaries to ensure runtime dependencies are available
    # This maintains our zero-patch philosophy by using wrappers instead of patching source
    postInstall = ''
      # Wrap cmake and related tools with runtime dependencies in PATH
      for prog in cmake ctest cpack; do
        if [ -f "$out/bin/$prog" ]; then
          wrapProgram "$out/bin/$prog" \
            --prefix PATH : ${lib.makeBinPath ([
              git
              ps
              sysctl
            ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
              darwin.DarwinTools    # sw_vers for macOS version detection
              darwin.system_cmds    # vm_stat for memory info
            ])}
        fi
      done
    '';

    passthru.updateScript = gitUpdater {
      url = "https://gitlab.kitware.com/cmake/cmake.git";
      rev-prefix = "v";
      ignoredVersions = "-"; # -rc1 and friends
    };

    meta = {
      homepage = "https://cmake.org/";
      description = "Cross-platform, open-source build system generator";
      longDescription = ''
        CMake is an open-source, cross-platform family of tools designed to build,
        test and package software. CMake is used to control the software
        compilation process using simple platform and compiler independent
        configuration files, and generate native makefiles and workspaces that can
        be used in the compiler environment of your choice.
      '';
      changelog = "https://cmake.org/cmake/help/v${lib.versions.majorMinor version}/release/${lib.versions.majorMinor version}.html";
      license = lib.licenses.bsd3;
      maintainers = with lib.maintainers; [
        ttuegel
        lnl7
        sielicki
      ];
      platforms = lib.platforms.all;
      mainProgram = "cmake";
    };
  };
  # Bootstrap cmake is minimal - no hooks, they would create circular dependencies
in
pkg
