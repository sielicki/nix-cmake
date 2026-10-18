{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-googletest";
  inherit (pkgs.gtest) version src;
  inherit cmake cmakeDependencyHook;
  cmakeFlags = [ "-DINSTALL_GTEST=ON" "-DBUILD_GMOCK=ON" ];
  meta.description = "Dogfood: googletest + gmock";
}
