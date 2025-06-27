{ lib, pkgs }:

let
  mkToolchain = { 
    stdenv ? pkgs.stdenv,
    cmake ? (pkgs.cmakeMinimal or pkgs.cmake),
    extraFlags ? []
  }:
    pkgs.callPackage ../../pkgs/cmake-toolchain-hook { inherit stdenv; };

in {
  # Default stdenv toolchain
  default = mkToolchain {};

  # Clang-based toolchain
  clang = { 
    version ? null, 
    extraFlags ? [] 
  }:
    let
      # Select the desired clang version
      clangPkgs = if version == null then pkgs.llvmPackages else pkgs."llvmPackages_${version}";
    in mkToolchain {
      stdenv = clangPkgs.stdenv;
      inherit extraFlags;
    };

  # GCC-based toolchain
  gcc = { 
    version ? null, 
    extraFlags ? [] 
  }:
    let
      # Select the desired gcc version
      gccPkg = if version == null then pkgs.gcc else pkgs."gcc${version}";
      stdenv = pkgs.overrideCC pkgs.stdenv gccPkg;
    in mkToolchain {
      inherit stdenv extraFlags;
    };

  # Helper for custom stdenvs (e.g., cross-compilation)
  custom = mkToolchain;
}
