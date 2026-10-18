{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-abseil-cpp";
  inherit (pkgs.abseil-cpp) version src;
  inherit cmake cmakeDependencyHook;
  cmakeFlags = [ "-DABSL_BUILD_TESTING=OFF" "-DABSL_PROPAGATE_CXX_STD=ON" "-DCMAKE_CXX_STANDARD=17" ];
  meta.description = "Dogfood: abseil-cpp multi-library build";
}
