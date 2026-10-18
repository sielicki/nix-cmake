{ installShellFiles
, buildPackages
, darwin
, fetchFromGitHub
, git
, gitUpdater
, lib
, libiconv
, libidn2
, makeBinaryWrapper
, ninja
, ps
, sysctl
, stdenv
}:
let
  pkg = stdenv.mkDerivation rec {
    pname = "cmakeMinimal";
    version = "4.4.3";

    src = fetchFromGitHub {
      owner = "Kitware";
      repo = "CMake";
      rev = "v${version}";
      hash = "sha256-oVJpBWhLPWkFhQYu4Ueh5Q0+mCapncS2MjoSK/12SDg=";
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

    # libiconv: CMake >= 4.4's vendored cmlibarchive requires iconv at
    # configure time even for the bootstrap build.
    buildInputs = [
      (lib.getDev libidn2)
      (lib.getLib libidn2)
      (lib.getDev libiconv)
      (lib.getLib libiconv)
    ];

    # Explicit bootstrap flags: use only CMake's vendored libraries.
    # NOTE: Don't use --init during bootstrap! The bootstrap process
    # doesn't use project() in the normal way, so
    # CMAKE_PROJECT_TOP_LEVEL_INCLUDES would try to set the dependency
    # provider outside of project() context, which is an error. The
    # bootstrap build doesn't need FetchContent interception anyway.
    configureFlags = [
      "--no-system-libs"
      "--no-system-curl"
      "--no-system-zlib"
      "--no-system-expat"
      "--no-system-jsoncpp"
      "--no-system-bzip2"
      "--no-system-liblzma"
      "--no-system-nghttp2"
      "--no-system-zstd"
      "--no-system-libarchive"
      "--no-system-librhash"
      "--no-system-libuv"
      "--no-system-cppdap"
      "--generator=Ninja"
      "--parallel=$NIX_BUILD_CORES"
      "--prefix=${builtins.placeholder "out"}"
      "--bindir=bin"
      "--datadir=share"
      "--xdgdatadir=share"
      "--docdir=share/doc"
      "--mandir=share/man"
      "--verbose"
    ] ++ lib.optional (stdenv.cc.isCcache or false) "--enable-ccache" ++ [
      "--"
      "-DCMAKE_USE_OPENSSL=OFF"
      # CMake >= 4.4's cmlibarchive requires iconv; the bootstrap CMake's
      # find_path cannot search Nix include dirs, so point it at the header.
      "-DICONV_INCLUDE_DIR=${lib.getDev (if stdenv.hostPlatform.isDarwin then libiconv else stdenv.cc.libc)}/include"
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
