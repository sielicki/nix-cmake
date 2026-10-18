{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-zstd";
  inherit (pkgs.zstd) version src;
  inherit cmake cmakeDependencyHook;
  # Upstream keeps its CMake project in build/cmake, not at the root.
  cmakeDir = "../build/cmake";
  cmakeFlags = [ "-DZSTD_BUILD_TESTS=OFF" ];
  meta.description = "Dogfood: zstd via its build/cmake subproject";
}
