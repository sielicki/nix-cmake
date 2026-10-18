{ buildPackages
, bzip2
, cmakeDependencyHook
, cmakeToolchainHook
, curl
, expat
, fetchFromGitHub
, gitUpdater
, lib
, libarchive
, libuv
, openssl
, pkg-config
, rhash
, stdenv
, xz
, zlib
}:

# Full CMake, built the way nixpkgs builds it: by self-bootstrapping
# through ./bootstrap with --system-libs. Building CMake must not
# require a working CMake -- that is the point of the bootstrap
# flow, and it decouples this derivation from cmakeMinimal and from
# the nix-cmake setup hooks. The hooks below are shipped payload
# (consumers' builds use them); they are deliberately not in
# nativeBuildInputs, so they are never activated during this build.
let
  # System libraries for --system-libs (see buildInputs).
  systemLibs = [
    bzip2
    curl
    expat
    libarchive
    libuv
    openssl
    rhash
    xz
    zlib
  ];
in
stdenv.mkDerivation rec {
  pname = "cmake";
  version = "4.4.3";

  src = fetchFromGitHub {
    owner = "Kitware";
    repo = "CMake";
    rev = "v${version}";
    hash = "sha256-oVJpBWhLPWkFhQYu4Ueh5Q0+mCapncS2MjoSK/12SDg=";
  };

  # Single "out" output, as upstream. (The previous dev/out/doc
  # split relied on building through our cmake hooks.)
  outputs = [ "out" ];
  separateDebugInfo = true;
  setOutputFlags = false;

  setupHooks = [
    cmakeToolchainHook
    cmakeDependencyHook
  ];

  # Only the build compiler: used by ./bootstrap to compile the
  # bootstrap cmake (CC_FOR_BUILD/CXX_FOR_BUILD). No cmake, no ninja.
  depsBuildBuild = [ buildPackages.stdenv.cc ];

  nativeBuildInputs = [ pkg-config ];

  # Mirroring upstream's full --system-libs list. ncurses is
  # intentionally absent (no curses UI is built); nghttp2/zstd
  # come in via curl/libarchive, as upstream relies on.
  buildInputs = systemLibs;

  strictDeps = true;

  # bootstrap is autoconf-like, not autoconf: no --build/--host.
  configurePlatforms = [ ];

  # Same shape as upstream: the build compiler goes first, so the
  # bootstrap cmake is built with it (only matters when cross).
  preConfigure = ''
    configureFlags=("CC=$CC_FOR_BUILD" "CXX=$CXX_FOR_BUILD" ''${configureFlags[@]})
  '';

  configureScript = "./bootstrap";
  configureFlags = [
    "--no-system-cppdap"
    "--no-system-jsoncpp"
    "--system-libs"
    "--parallel=$NIX_BUILD_CORES"
    "--prefix=${builtins.placeholder "out"}"
    "--bindir=bin"
    "--datadir=share"
    "--xdgdatadir=share"
    "--docdir=share/doc"
    "--mandir=share/man"
    "--"
    # The bootstrap cmake's find_* cannot discover Nix prefixes on
    # its own (upstream relies on its patched
    # NIXPKGS_CMAKE_PREFIX_PATH + its hook for this). Zero-patch
    # equivalent: name the system-lib prefixes explicitly.
    "-DCMAKE_PREFIX_PATH=${lib.concatStringsSep ";" (map lib.getDev systemLibs ++ map lib.getLib systemLibs)}"
    # Absolute tool paths, as upstream passes them.
    (lib.cmakeFeature "CMAKE_CXX_COMPILER" "${stdenv.cc.targetPrefix}c++")
    (lib.cmakeFeature "CMAKE_C_COMPILER" "${stdenv.cc.targetPrefix}cc")
    (lib.cmakeFeature "CMAKE_AR" "${lib.getBin stdenv.cc.bintools.bintools}/bin/${stdenv.cc.targetPrefix}ar")
    (lib.cmakeFeature "CMAKE_RANLIB" "${lib.getBin stdenv.cc.bintools.bintools}/bin/${stdenv.cc.targetPrefix}ranlib")
    (lib.cmakeFeature "CMAKE_STRIP" "${lib.getBin stdenv.cc.bintools.bintools}/bin/${stdenv.cc.targetPrefix}strip")
    (lib.cmakeBool "CMAKE_USE_OPENSSL" true)
    (lib.cmakeBool "BUILD_CursesDialog" false)
    # CMake >= 4.4's vendored/system libarchive path requires iconv;
    # the bootstrap cmake's find_path cannot search Nix include dirs.
    "-DICONV_INCLUDE_DIR=${lib.getDev stdenv.cc.libc}/include"
  ];

  # Belt and braces: even if some cmake hook were in the environment,
  # it must not take over this build's configure phase.
  dontUseCmakeConfigure = true;
  dontUseNixCMakeSetup = true;
  enableParallelBuilding = true;

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
}
