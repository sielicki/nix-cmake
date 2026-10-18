{ lib
, pkgs
, cmake
, cmakeDependencyHook
}:

let
  nix-cmake = import ../../lib { inherit lib; };
  dynamic = nix-cmake.dynamic pkgs;
in
dynamic.buildCMakePackage {
  pname = "dynamic-fetchcontent-test";
  version = "0.1.0";
  src = ./.;
  lockFile = ./cmake-lock.json;

  inherit cmake cmakeDependencyHook;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./test_fmt
    runHook postCheck
  '';

  meta = {
    description = "Test dynamic-derivation discovery and build with fmt";
  };
}
