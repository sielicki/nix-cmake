{ lib, pkgs }:

let
  mkToolchain =
    { stdenv ? pkgs.stdenv
    , extraFlags ? [ ]
    }:
    lib.warnIf (extraFlags != [ ])
      "nix-cmake toolchains: extraFlags is not implemented yet and will be ignored"
      (pkgs.callPackage ../../pkgs/cmake-toolchain-hook { inherit stdenv; });

in
{
  # Default stdenv toolchain
  default = mkToolchain { };

  # Clang-based toolchain
  clang =
    { version ? null
    , extraFlags ? [ ]
    }:
    let
      clangPkgs = if version == null then pkgs.llvmPackages else pkgs."llvmPackages_${toString version}";
    in
    mkToolchain {
      inherit (clangPkgs) stdenv;
      inherit extraFlags;
    };

  # GCC-based toolchain
  gcc =
    { version ? null
    , extraFlags ? [ ]
    }:
    let
      gccPkg = if version == null then pkgs.gcc else pkgs."gcc${toString version}";
      stdenv = pkgs.overrideCC pkgs.stdenv gccPkg;
    in
    mkToolchain {
      inherit stdenv extraFlags;
    };

  # Helper for custom stdenvs (e.g., cross-compilation)
  custom = mkToolchain;
}
