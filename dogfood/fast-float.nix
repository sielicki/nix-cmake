{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-fast-float";
  inherit (pkgs.fast-float) version src;
  inherit cmake cmakeDependencyHook;
  # Upstream tests FetchContent doctest (and supplemental data).
  # Use the system doctest copy and disable the supplemental-data
  # download; tests still exercise the test FetchContent path off.
  buildInputs = [ pkgs.doctest ];
  cmakeFlags = [
    "-DFASTFLOAT_TEST=ON"
    "-DSYSTEM_DOCTEST=ON"
    "-DFASTFLOAT_SUPPLEMENTAL_TESTS=OFF"
  ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ctest --output-on-failure
    runHook postCheck
  '';
  meta.description = "Dogfood: fast_float tests with system doctest";
}
