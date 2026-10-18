{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-spdlog";
  inherit (pkgs.spdlog) version src;
  inherit cmake cmakeDependencyHook;
  # Consume the dogfood fmt so this also exercises CPS transitive
  # resolution (spdlog's CPS requires fmt).
  propagatedBuildInputs = [ (pkgs.callPackage ./fmt.nix { inherit cmake cmakeDependencyHook; }) ];
  cmakeFlags = [
    "-DSPDLOG_FMT_EXTERNAL=ON"
    "-DSPDLOG_BUILD_EXAMPLE=OFF"
    "-DSPDLOG_BUILD_BENCH=OFF"
    "-DSPDLOG_BUILD_TESTS=OFF"
  ];
  cps.exports = [{
    export = "spdlog";
    package = "spdlog";
    compatVersion = "1";
    license = "MIT";
  }];

  meta.description = "Dogfood: spdlog with external fmt via find_package (with CPS)";
}
