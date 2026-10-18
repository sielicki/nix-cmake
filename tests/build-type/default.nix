{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "build-type-override-test";
  version = "0.1.0";
  src = ./.;
  inherit cmake cmakeDependencyHook;
  # The hook's Release default must not override this.
  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Debug" ];
  meta.description = "Regression test: user CMAKE_BUILD_TYPE wins over hook default";
}
