# Integration of CMake toolchain generation into stdenv
{ lib, stdenv, makeSetupHook, writeTextFile, writeShellScript }:

let
  cmakeToolchainGenerator = import ./cmake-toolchain.nix {
    inherit lib writeTextFile writeShellScript;
  };

  cmakeToolchain = cmakeToolchainGenerator stdenv;
in
makeSetupHook
{
  name = "cmake-nix-toolchain-hook.sh";
  substitutions = {
    cmakeToolchainPath = "${cmakeToolchain}";
  };
} ./cmake-nix-toolchain-hook.sh
