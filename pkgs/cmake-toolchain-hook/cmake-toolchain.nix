{ lib, writeTextFile, writeShellScript }:

stdenv:
let
  inherit (stdenv) hostPlatform buildPlatform targetPlatform cc;
  inherit (stdenv.cc) bintools;

  launchers = import ./../cmake-compiler-launchers { inherit lib writeShellScript stdenv; };

  isCross = hostPlatform != buildPlatform;

  #ccPath = "${lib.meta.getExe cc.cc}";
  #cxxPath = "${lib.meta.getExe cc.cc}++";
  ccPath = "${cc.cc}/bin/${if cc.isClang then "clang" else "gcc"}";
  cxxPath = "${cc.cc}/bin/${if cc.isClang then "clang++" else "g++"}";
  arPath = "${bintools.bintools}/bin/${cc.targetPrefix}ar";
  ranlibPath = "${bintools.bintools}/bin/${cc.targetPrefix}ranlib";
  stripPath = "${bintools.bintools}/bin/${cc.targetPrefix}strip";
  #arPath = "${cc.cc.libllvm}/bin/llvm-ar";
  #ranlibPath = "${cc.cc.libllvm}/bin/llvm-ranlib";
  #stripPath = "${cc.cc.libllvm}/bin/llvm-strip";

  cmakeSystemNameFor = platform: {
    "linux" = "Linux";
    "darwin" = "Darwin";
    "windows" = "Windows";
    "freebsd" = "FreeBSD";
    "openbsd" = "OpenBSD";
    "netbsd" = "NetBSD";
  }.${platform.parsed.kernel.name} or "Generic";

  cmakeSystemProcessorFor = platform: {
    "x86_64" = "x86_64";
    "i686" = "i686";
    "aarch64" = "arm64";
    "armv7l" = "arm";
    "armv6l" = "arm";
  }.${platform.parsed.cpu.name} or platform.parsed.cpu.name;

  libcLib = lib.getLib stdenv.cc.libc;
  libcDev = lib.getDev stdenv.cc.libc;

in
writeTextFile {
  name = "cmake-toolchain-${stdenv.targetPlatform.config}.cmake";
  #set(CMAKE_C_COMPILER_LAUNCHER "${launchers.cCompilerLauncher}")
  #set(CMAKE_CXX_COMPILER_LAUNCHER "${launchers.cxxCompilerLauncher}")

  #set(CMAKE_C_LINKER_LAUNCHER "${launchers.cLinkerLauncher}")
  #set(CMAKE_CXX_LINKER_LAUNCHER "${launchers.cxxLinkerLauncher}")
  text = ''
    # Nix-generated CMake toolchain file for ${stdenv.targetPlatform.config}
    # Generated from stdenv with:
    # - hostPlatform: ${hostPlatform.config}
    # - buildPlatform: ${buildPlatform.config}
    # - Cross-compiling: ${lib.boolToString isCross}
    cmake_policy(PUSH)
    cmake_minimum_required(VERSION 3.24)
    set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)
    set(CMAKE_VERBOSE_MAKEFILE ON)
    set(CMAKE_FIND_DEBUG_MODE ON)
    set(CMAKE_SIZEOF_VOID_P ${if buildPlatform.is64bit then "8" else if buildPlatform.is32bit then "4" else "BAD BAD BAD"})
    set(CMAKE_EXPERIMENTAL_EXPORT_PACKAGE_INFO "b80be207-778e-46ba-8080-b23bba22639e")

    
    # ============================================================================
    # System Configuration
    # ============================================================================
    set(CMAKE_HOST_SYSTEM_NAME "${cmakeSystemNameFor hostPlatform}")
    set(CMAKE_HOST_SYSTEM_PROCESSOR "${cmakeSystemProcessorFor hostPlatform}")
    set(CMAKE_SYSTEM_NAME "${cmakeSystemNameFor buildPlatform}")
    set(CMAKE_SYSTEM_PROCESSOR "${cmakeSystemProcessorFor buildPlatform}")
    set(CMAKE_CROSSCOMPILING ${if isCross then "TRUE" else "FALSE"})
    
    # ============================================================================
    # Compiler Configuration  
    # ============================================================================
    
    # Point to actual unwrapped compilers
    set(CMAKE_C_COMPILER "${ccPath}")
    set(CMAKE_C_COMPILER_TARGET ${hostPlatform.config})
    if(NOT EXISTS "${ccPath}")
        message(FATAL_ERROR "C compiler not found: ${ccPath}")
    endif()
    set(CMAKE_CXX_COMPILER "${cxxPath}")
    set(CMAKE_CXX_COMPILER_TARGET ${hostPlatform.config})
    if(NOT EXISTS "${cxxPath}")
        message(FATAL_ERROR "C++ compiler not found: ${cxxPath}")
    endif()
   
    # Bintools
    set(CMAKE_AR "${arPath}")
    set(CMAKE_RANLIB "${ranlibPath}")
    set(CMAKE_STRIP "${stripPath}")
    
    # ============================================================================
    # Linker Configuration
    # ============================================================================
    
    # ============================================================================
    # Search Path Configuration
    # ============================================================================
    # Ignore standard Unix paths - we control everything through Nix
    set(CMAKE_SYSTEM_IGNORE_PREFIX_PATH 
        "/usr"
        "/usr/local" 
        "/opt"
        "/opt/local"
        "/sw"  # Fink on macOS
    )
    
    list(APPEND CMAKE_SYSTEM_PREFIX_PATH "${libcLib}")
    list(APPEND CMAKE_SYSTEM_INCLUDE_PATH "${libcDev}/include")
    list(APPEND CMAKE_SYSTEM_LIBRARY_PATH "${libcLib}/lib")
    
    # ============================================================================
    # Cross-Compilation Search Configuration
    # ============================================================================
    
    ${lib.optionalString isCross ''
    set(CMAKE_FIND_ROOT_PATH "${libcLib}")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
    ''}
    
    # ============================================================================
    # Registry and Network Isolation
    # ============================================================================
    
    # Disable all package registries - we control dependencies through Nix
    set(CMAKE_FIND_USE_PACKAGE_REGISTRY FALSE)
    set(CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY FALSE)
    set(CMAKE_EXPORT_NO_PACKAGE_REGISTRY TRUE)
    
    # ============================================================================
    # Build Configuration Defaults
    # ============================================================================
    set(BUILD_SHARED_LIBS ${if stdenv.hostPlatform.isStatic then "OFF" else "ON"} CACHE BOOL "Build shared libraries by default")

    # ============================================================================
    # Reproducible Builds
    # ============================================================================
    # Respect SOURCE_DATE_EPOCH for reproducible builds
    if(DEFINED ENV{SOURCE_DATE_EPOCH})
      set(SOURCE_DATE_EPOCH $ENV{SOURCE_DATE_EPOCH} CACHE STRING "Timestamp for reproducible builds")
    endif()

    # Add compiler flags for reproducible builds
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
      # Use relative paths in debug info for reproducibility
      add_compile_options(
        $<$<CONFIG:Debug>:-fdebug-prefix-map=$''${CMAKE_SOURCE_DIR}=.>
        $<$<CONFIG:RelWithDebInfo>:-fdebug-prefix-map=$''${CMAKE_SOURCE_DIR}=.>
      )

      # Linker flags for reproducibility
      ${lib.optionalString hostPlatform.isLinux ''
      add_link_options(-Wl,--build-id=none)  # Remove build-id which varies
      ''}
      ${lib.optionalString hostPlatform.isDarwin ''
      add_link_options(-Wl,-no_uuid)  # Remove UUID on macOS
      ''}
    endif()

    #include(GNUInstallDirs)
    
    # ============================================================================
    # Platform-Specific Configuration
    # ============================================================================
    ${lib.optionalString hostPlatform.isDarwin ''
    # macOS-specific settings
    set(CMAKE_FIND_FRAMEWORK LAST)  # Prefer Unix-style to Framework packages
    set(CMAKE_FIND_APPBUNDLE LAST)
    ''}
    
    ${lib.optionalString hostPlatform.isStatic ''
    # Static linking configuration
    set(CMAKE_FIND_LIBRARY_SUFFIXES .a)
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "Force static libraries")
    ''}
    
    # ============================================================================
    # Validation
    # ============================================================================
    set(CMAKE_OPTIMIZE_DEPENDENCIES ON)
    set(CMAKE_LINK_WHAT_YOU_USE ON)
    set(CMAKE_INCLUDE_WHAT_YOU_USE ON)
    #set(CMAKE_EXPORT_BUILD_DATABASE ON)
    #set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

    include(${./NixGNUInstallDirs.cmake})
    
    # Mark toolchain as configured
    set(NIX_CMAKE_TOOLCHAIN_CONFIGURED TRUE)
    cmake_policy(POP)
  '';
}
