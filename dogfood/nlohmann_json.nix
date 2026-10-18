{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-nlohmann-json";
  inherit (pkgs.nlohmann_json) version src;
  inherit cmake cmakeDependencyHook;
  cmakeFlags = [
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DJSON_BuildTests=OFF"
    "-DJSON_MultipleHeaders=ON"
  ];
  meta.description = "Dogfood: nlohmann_json header-only library";
}
