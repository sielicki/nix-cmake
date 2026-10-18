{ lib, pkgs, cmake }:

let
  builders = (import ../../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "hookless-fetchcontent-test";
  version = "0.1.0";
  src = ./.;
  inherit cmake;
  # fetchContentDeps must work without the dependency hook: the
  # builders pass FETCHCONTENT_SOURCE_DIR_* as cache variables.
  cmakeDependencyHook = null;
  fetchContentDeps.fmt = pkgs.fetchFromGitHub {
    owner = "fmtlib";
    repo = "fmt";
    rev = "10.2.1";
    hash = "sha256-pEltGLAHLZ3xypD/Ur4dWPWJ9BGVXwqQyKcDWVmC3co=";
  };
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./app
    runHook postCheck
  '';
}
