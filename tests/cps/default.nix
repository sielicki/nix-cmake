{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../../lib { inherit lib; }).builders pkgs;
  dogfood = pkgs.callPackage ../../dogfood {
    inherit cmake cmakeDependencyHook;
  };
in
builders.buildCMakePackage {
  pname = "cps-consumption-test";
  version = "0.1.0";
  src = ./.;
  inherit cmake cmakeDependencyHook;

  buildInputs = [ dogfood.spdlog ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./cps_app
    runHook postCheck
  '';

  meta.description = "Test CPS generation and transitive consumption (spdlog -> fmt)";
}
