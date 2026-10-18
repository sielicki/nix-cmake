{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-catch2";
  inherit (pkgs.catch2_3) version src;
  inherit cmake cmakeDependencyHook;
  cmakeFlags = [ "-DCATCH_BUILD_TESTING=OFF" "-DCATCH_INSTALL_DOCS=OFF" ];
  meta.description = "Dogfood: Catch2 v3 library";
}
