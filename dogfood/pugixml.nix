{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-pugixml";
  inherit (pkgs.pugixml) version src;
  inherit cmake cmakeDependencyHook;
  cmakeFlags = [ "-DBUILD_TESTS=OFF" "-DBUILD_SHARED_LIBS=ON" ];
  meta.description = "Dogfood: pugixml compiled library";
}
