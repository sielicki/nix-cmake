{ installShellFiles
, buildPackages
, bzip2
, callPackage
, cmakeDependencyHook
, cmakeToolchainHook
, curl
, cmakeMinimal
, ninja
, expat
, fetchFromGitHub
, fetchurl
, gitUpdater
, jsoncpp
, lib
, libarchive
, libuv
, ncurses
, nghttp2
, openssl
, ps
, #swift,
  sysctl
, replaceVars
, rhash
, sphinx
, stdenv
, texinfo
, writeText
, writeTextFile
, xz
, zlib
, zstd
, libsForQt5
, buildDocs ? true
  #cppdap,
}:
let
  inherit (libsForQt5) qtbase wrapQtAppsHook;
in
stdenv.mkDerivation rec {
  pname = "cmake";
  version = "4.2.1";

  src = fetchFromGitHub {
    owner = "Kitware";
    repo = "CMake";
    rev = "v${version}";
    hash = "sha256-lZ46Zq2HUDFw8J2kj4C6aclEWXy1MNOIKD9PVQ9WP8s=";
  };

  # CMake 4.2 brings features important for nix-cmake:
  # - Enhanced file-based API (codemodel v2.9) with imported targets
  # - Improved link dependency tracking (linkLibraries, interfaceLinkLibraries)
  # - Better transitive dependency support
  # - Foundation for CPS (Common Package Specification) integration
  depsBuildBuild = with buildPackages; [ stdenv.cc ninja which cmakeMinimal sysctl ];
  nativeBuildInputs = setupHooks ++ [ installShellFiles ];

  outputs =
    [ "dev" "out" "doc" "man" ];
  #    [ "out" ];
  #++ lib.optionals buildDocs [
  #  "info"
  #  "man"
  #];
  separateDebugInfo = true;
  setOutputFlags = false;

  buildInputs = [
    ps
    openssl
    # unpackaged:
    #   cppdap


    # recursive dependency:
    #jsoncpp

    # good:
    (lib.getDev ncurses)
    (lib.getLib ncurses)
    (lib.getDev curl)
    (lib.getLib curl)
    (lib.getDev expat)
    (lib.getLib expat)
    (lib.getDev zlib)
    (lib.getLib zlib)
    (lib.getDev bzip2)
    (lib.getDev xz)
    (lib.getDev nghttp2)
    (lib.getDev zstd)
    (lib.getDev libarchive)
    (lib.getDev rhash)
    (lib.getDev libuv)
    (lib.getLib bzip2)
    (lib.getLib xz)
    (lib.getLib nghttp2)
    (lib.getLib zstd)
    (lib.getLib libarchive)
    (lib.getLib rhash)
    (lib.getLib libuv)
  ];

  configureFlags = [
    "-DCMAKE_USE_OPENSSL=ON"
  ];

  setupHooks = [
    cmakeToolchainHook
    cmakeDependencyHook
  ];

  #dontUseNixCMakeSetup = true;
  enableParallelBuilding = true;

  #postInstall = ''
  #'';

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
