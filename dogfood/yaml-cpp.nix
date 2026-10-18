{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-yaml-cpp";
  inherit (pkgs.yaml-cpp) version src;
  inherit cmake cmakeDependencyHook;
  cmakeFlags = [ "-DYAML_CPP_BUILD_TESTS=OFF" "-DYAML_CPP_BUILD_TOOLS=OFF" ];
  meta.description = "Dogfood: yaml-cpp library";
}
