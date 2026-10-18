{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-fmt";
  inherit (pkgs.fmt) version src;
  inherit cmake cmakeDependencyHook;
  cmakeFlags = [ "-DFMT_TEST=OFF" "-DFMT_DOC=OFF" "-DBUILD_SHARED_LIBS=ON" ];

  # Also install CPS package info generated from fmt's install(EXPORT),
  # without modifying upstream. compatVersion mirrors fmt's
  # SameMajorVersion script-config policy.
  cps.exports = [{
    export = "fmt-targets";
    package = "fmt";
    version = "@FMT_VERSION@";
    compatVersion = "@CPACK_PACKAGE_VERSION_MAJOR@";
    license = "MIT";
  }];

  meta.description = "Dogfood: fmt repackaged with nix-cmake builders (with CPS)";
}
