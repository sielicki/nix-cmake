{ buildPackages
, darwin
, fetchFromGitHub
, gitUpdater
, lib
, libiconv
, makeBinaryWrapper
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


    # Bootstrap parity with nixpkgs' cmakeMinimal: this derivation
    # must be buildable with only a compiler, so that it can enter
    # toolchain bootstrap stages where e.g. curl is banned outright.
    # The ./bootstrap script needs nothing else (stdenv provides
    # make/coreutils); do not add ninja or libraries here.
    depsBuildBuild = [ buildPackages.stdenv.cc ];

    strictDeps = true;

    # Only needed for the Darwin postInstall wrapper below.
    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isDarwin [
      makeBinaryWrapper
      darwin.DarwinTools # sw_vers
      darwin.system_cmds # vm_stat
    ];

    outputs = [ "out" ];
    separateDebugInfo = true;
    setOutputFlags = false;

    # Provide basic CMake setup hook for packages that use cmakeMinimal as a build dependency
    setupHooks = [ ./setup-hook.sh ];

    # No buildInputs on Linux: CMake >= 4.4's vendored cmlibarchive
    # needs iconv at configure time, and glibc provides it (see
    # ICONV_INCLUDE_DIR below). Previously libidn2/libiconv were
    # linked opportunistically and leaked into the runtime closure.
    # Darwin has no iconv in libc, hence libiconv there (as upstream).
    buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [
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
      # No --generator=Ninja: ninja must not be a bootstrap dependency;
      # bootstrap's default (Unix Makefiles, make from stdenv) is used.
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
      # Absolute tool paths, as upstream passes them: cmake would
      # otherwise resolve ar/ranlib/strip relative to source roots.
      (lib.cmakeFeature "CMAKE_CXX_COMPILER" "${stdenv.cc.targetPrefix}c++")
      (lib.cmakeFeature "CMAKE_C_COMPILER" "${stdenv.cc.targetPrefix}cc")
      (lib.cmakeFeature "CMAKE_AR" "${lib.getBin stdenv.cc.bintools.bintools}/bin/${stdenv.cc.targetPrefix}ar")
      (lib.cmakeFeature "CMAKE_RANLIB" "${lib.getBin stdenv.cc.bintools.bintools}/bin/${stdenv.cc.targetPrefix}ranlib")
      (lib.cmakeFeature "CMAKE_STRIP" "${lib.getBin stdenv.cc.bintools.bintools}/bin/${stdenv.cc.targetPrefix}strip")
    ];

    # bootstrap is autoconf-like, not autoconf: no --build/--host.
    configurePlatforms = [ ];

    # The compiler used to compile the bootstrap cmake itself.
    # (Only differs from the host compiler when cross; CC_FOR_BUILD
    # is set by stdenv from depsBuildBuild. Same shape as upstream.)
    preConfigure = ''
      configureFlags=("CC=$CC_FOR_BUILD" "CXX=$CXX_FOR_BUILD" ''${configureFlags[@]})
    '';


    dontUseNixCMakeSetup = true;
    configureScript = "./bootstrap";
    enableParallelBuilding = true;

    # Wrap cmake binaries only where runtime helper tools are not
    # found via PATH in a Nix build environment (Darwin: sw_vers,
    # vm_stat, sysctl). Deliberately do NOT wrap in `git` (or, on
    # Linux, ps/sysctl): a minimal/bootstrap CMake must have a tiny
    # runtime closure, and git would drag in curl, openssl, perl and
    # more (~95 store paths) -- defeating the point of cmakeMinimal,
    # and violating e.g. the Darwin bootstrap's ban on curl. Projects
    # that need git at build time add it to nativeBuildInputs
    # themselves (as nix-cmake's discovery derivations do). Compare
    # upstream nixpkgs, whose cmake-minimal closure is 11 paths and
    # which instead *patches* the helper paths into the source on
    # Darwin (we keep the zero-patch approach via the wrapper).
    postInstall = lib.optionalString stdenv.hostPlatform.isDarwin ''
      for prog in cmake ctest cpack; do
        if [ -f "$out/bin/$prog" ]; then
          wrapProgram "$out/bin/$prog" \
            --prefix PATH : ${lib.makeBinPath [
              darwin.DarwinTools    # sw_vers for macOS version detection
              darwin.system_cmds    # vm_stat/sysctl for system info
            ]}
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
