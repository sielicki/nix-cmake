{ lib
, pkgs
, cmake
, cmakeDependencyHook
, ninja
, git
, fetchurl
}:

let
  # Load workspace with cmake-lock.json
  nix-cmake = import ../../lib { inherit lib; };
  workspace = (nix-cmake.workspace pkgs).loadWorkspace {
    workspaceRoot = ./.;
  };

  # CPM.cmake is a single file, but FetchContent expects a directory
  cpm-cmake-dir = pkgs.stdenv.mkDerivation {
    name = "cpm-cmake-0.40.2";
    src = fetchurl {
      url = "https://github.com/cpm-cmake/CPM.cmake/releases/download/v0.40.2/CPM.cmake";
      hash = "sha256-yM3DLAOBZTjOInge1ylk3IZLKjSjENO3EEgSpcotg10=";
    };
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out
      cp $src $out/CPM.cmake
    '';
  };
in
workspace.buildPackage {
  pname = "simple-cpm-test";
  version = "0.1.0";

  nativeBuildInputs = [ ninja git ];

  # Provide CPM.cmake directory for FetchContent
  CPM_SOURCE_DIR = cpm-cmake-dir;

  cmakeFlags = [ ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./test_cpm
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp test_cpm $out/bin/
    runHook postInstall
  '';

  meta = {
    description = "Test CPM.cmake interception with fmt library from lock file";
  };
}
