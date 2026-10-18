{ lib, writeTextFile }:

stdenv:
let
  inherit (stdenv) hostPlatform buildPlatform cc;
  inherit (stdenv.cc) bintools;

  isCross = hostPlatform != buildPlatform;

  # Use the Nix cc *wrapper*, not the unwrapped compiler. The wrapper
  # supplies libc include/library paths, hardening flags and the
  # dynamic linker; bypassing it (as an earlier version of this file
  # did) breaks ordinary builds outside of discovery mode.
  ccPath = "${cc}/bin/${cc.targetPrefix}${if cc.isClang then "clang" else "gcc"}";
  cxxPath = "${cc}/bin/${cc.targetPrefix}${if cc.isClang then "clang++" else "g++"}";
  arPath = "${bintools.bintools}/bin/${cc.targetPrefix}ar";
  ranlibPath = "${bintools.bintools}/bin/${cc.targetPrefix}ranlib";
  stripPath = "${bintools.bintools}/bin/${cc.targetPrefix}strip";

  cmakeSystemNameFor = platform: {
    "linux" = "Linux";
    "darwin" = "Darwin";
    "windows" = "Windows";
    "freebsd" = "FreeBSD";
    "openbsd" = "OpenBSD";
    "netbsd" = "NetBSD";
  }.${platform.parsed.kernel.name} or "Generic";

  cmakeSystemProcessorFor = platform:
    if platform.parsed.cpu.name == "aarch64" && platform.parsed.kernel.name == "darwin" then "arm64"
    else platform.parsed.cpu.name;

  libcLib = lib.getLib stdenv.cc.libc;
  libcDev = lib.getDev stdenv.cc.libc;

in
writeTextFile {
  name = "cmake-toolchain-${stdenv.targetPlatform.config}.cmake";
  text = ''
    # Nix-generated CMake toolchain file for ${stdenv.targetPlatform.config}
    # - hostPlatform (artifacts): ${hostPlatform.config}
    # - buildPlatform (builder):  ${buildPlatform.config}
    # - Cross-compiling: ${lib.boolToString isCross}
    cmake_policy(PUSH)
    cmake_minimum_required(VERSION 3.24)
    set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)

    # System configuration. CMAKE_SYSTEM_* describes the platform the
    # built artifacts run on (Nix hostPlatform); CMAKE_HOST_SYSTEM_*
    # describes the builder (Nix buildPlatform). These were swapped in
    # an earlier version of this file.
    set(CMAKE_SYSTEM_NAME "${cmakeSystemNameFor hostPlatform}")
    set(CMAKE_SYSTEM_PROCESSOR "${cmakeSystemProcessorFor hostPlatform}")
    set(CMAKE_HOST_SYSTEM_NAME "${cmakeSystemNameFor buildPlatform}")
    set(CMAKE_HOST_SYSTEM_PROCESSOR "${cmakeSystemProcessorFor buildPlatform}")
    set(CMAKE_CROSSCOMPILING ${if isCross then "TRUE" else "FALSE"})

    # Compilers (Nix cc wrappers, see above)
    set(CMAKE_C_COMPILER "${ccPath}")
    if(NOT EXISTS "${ccPath}")
        message(FATAL_ERROR "C compiler not found: ${ccPath}")
    endif()
    set(CMAKE_CXX_COMPILER "${cxxPath}")
    if(NOT EXISTS "${cxxPath}")
        message(FATAL_ERROR "C++ compiler not found: ${cxxPath}")
    endif()
    ${lib.optionalString cc.isClang ''
    set(CMAKE_C_COMPILER_TARGET "${hostPlatform.config}")
    set(CMAKE_CXX_COMPILER_TARGET "${hostPlatform.config}")
    ''}

    # Bintools
    set(CMAKE_AR "${arPath}")
    set(CMAKE_RANLIB "${ranlibPath}")
    set(CMAKE_STRIP "${stripPath}")

    # Ignore impure system prefixes; dependencies come from Nix inputs
    # (populated into CMAKE_SYSTEM_*_PATH by cmakeBuildHook.cmake).
    set(CMAKE_SYSTEM_IGNORE_PREFIX_PATH
        "/usr"
        "/usr/local"
        "/opt"
        "/opt/local"     # MacPorts
        "/opt/homebrew"  # Homebrew on Apple Silicon
        "/sw"            # Fink
    )

    list(APPEND CMAKE_SYSTEM_PREFIX_PATH "${libcLib}")
    list(APPEND CMAKE_SYSTEM_INCLUDE_PATH "${libcDev}/include")
    list(APPEND CMAKE_SYSTEM_LIBRARY_PATH "${libcLib}/lib")

    ${lib.optionalString isCross ''
    # Cross-compilation search configuration
    set(CMAKE_FIND_ROOT_PATH "${libcLib}")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
    ''}

    # Disable package registries; Nix controls dependency resolution.
    set(CMAKE_FIND_USE_PACKAGE_REGISTRY FALSE)
    set(CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY FALSE)
    set(CMAKE_EXPORT_NO_PACKAGE_REGISTRY TRUE)

    set(BUILD_SHARED_LIBS ${if stdenv.hostPlatform.isStatic then "OFF" else "ON"} CACHE BOOL "Build shared libraries by default")

    if(DEFINED ENV{SOURCE_DATE_EPOCH})
      set(SOURCE_DATE_EPOCH $ENV{SOURCE_DATE_EPOCH} CACHE STRING "Timestamp for reproducible builds")
    endif()

    ${lib.optionalString hostPlatform.isDarwin ''
    # Prefer Unix-style libraries to frameworks/app bundles
    set(CMAKE_FIND_FRAMEWORK LAST)
    set(CMAKE_FIND_APPBUNDLE LAST)
    ''}

    ${lib.optionalString hostPlatform.isStatic ''
    set(CMAKE_FIND_LIBRARY_SUFFIXES .a)
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "Force static libraries" FORCE)
    ''}

    include(${./NixGNUInstallDirs.cmake})

    set(NIX_CMAKE_TOOLCHAIN_CONFIGURED TRUE)
    cmake_policy(POP)
  '';
}
