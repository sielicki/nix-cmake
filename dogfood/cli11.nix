{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-cli11";
  inherit (pkgs.cli11) version src;
  inherit cmake cmakeDependencyHook;
  cmakeFlags = [ "-DCLI11_BUILD_TESTS=OFF" "-DCLI11_BUILD_EXAMPLES=OFF" ];
  meta.description = "Dogfood: CLI11 header-only library";
}
