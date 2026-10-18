{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-brotli";
  inherit (pkgs.brotli) version src;
  inherit cmake cmakeDependencyHook;
  meta.description = "Dogfood: brotli libraries and tool";
}
