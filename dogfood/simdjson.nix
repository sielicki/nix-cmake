{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-simdjson";
  inherit (pkgs.simdjson) version src;
  inherit cmake cmakeDependencyHook;
  cmakeFlags = [ "-DSIMDJSON_DEVELOPER_MODE=OFF" "-DBUILD_SHARED_LIBS=ON" ];
  meta.description = "Dogfood: simdjson compiled library";
}
