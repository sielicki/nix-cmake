{ lib, pkgs, cmake, cmakeDependencyHook }:

let
  builders = (import ../lib { inherit lib; }).builders pkgs;
in
builders.buildCMakePackage {
  pname = "dogfood-tl-expected";
  inherit (pkgs.tl-expected) version src;
  inherit cmake cmakeDependencyHook;
  # Upstream FetchContents Catch2 v2 when tests are enabled; provide
  # the exact nixpkgs catch2 (v2) source through nix-cmake instead of
  # letting it download anything.
  fetchContentDeps.Catch2 = pkgs.catch2.src;
  cmakeFlags = [ "-DEXPECTED_BUILD_TESTS=ON" ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ctest --output-on-failure
    runHook postCheck
  '';
  meta.description = "Dogfood: tl-expected tests with FetchContent-provided Catch2";
}
