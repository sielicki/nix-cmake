{
  installShellFiles,
  buildPackages,
  callPackage,
  cmakeDependencyHook,
  fetchFromGitHub,
  gitUpdater,
  cmakeToolchainHook,
  lib,
  libidn2,
  ninja,
  ps,
  stdenv,
#  zlib,
#curlMinimal ? null,
}:
let
pkg = stdenv.mkDerivation rec {
  pname = "cmakeMinimal";
  version = "4.0.3";

  src = fetchFromGitHub {
    owner = "Kitware";
    repo = "CMake";
    rev = "v${version}";
    hash = "sha256-VSn+f/sIbUkXAS3NgxO+aoFTG/OOGxxvp96VXFRlTLI=";
  };

  
  depsBuildBuild = with buildPackages; [ stdenv.cc ninja which ];
  nativeBuildInputs = [ cmakeDependencyHook installShellFiles ];

  outputs = [ "out" ];
  separateDebugInfo = true;
  setOutputFlags = false;
  buildInputs = [ ps (lib.getDev libidn2) (lib.getLib libidn2) ] ++ 
    #  (lib.optionals (curlMinimal == null) [
    #  (lib.getDev curlMinimal) (lib.getLib curlMinimal) 
    #  (lib.getDev zlib) (lib.getLib zlib) 
    #])#  
    [];

  configureFlags = (lib.cli.toGNUCommandLine {
    optionValueSeparator = "=";
    mkBool = k: v: 
        if       (lib.strings.hasPrefix "system" k) then ["--${if v then "" else "no-"}${k}"]
        else lib.optionals v ["--${k}"]
        ;
  } {
      #system-curl = (curlMinimal != null);
      #system-zlib = (curlMinimal != null);
    system-curl = false;
    system-zlib = false;
    generator = "Ninja";
    system-libs = false;
    system-expat = false;
    system-jsoncpp = false;
    system-bzip2 = false;
    system-liblzma    = false;
    system-nghttp2    = false;
    system-zstd       = false;
    system-libarchive = false;   
    system-librhash   = false;
    system-libuv      = false;

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
    init = "${../cmake-dependency-hook/cmakeBuildHook.cmake}";
  }) ++ [
        "--"
        "-DCMAKE_USE_OPENSSL=OFF"
      ];


  dontUseNixCMakeSetup = true;
  configureScript = "./bootstrap";
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
};
in pkg.overrideAttrs(prev: prev // {
  setupHooks = [
    cmakeToolchainHook
    cmakeDependencyHook
  ];
})
