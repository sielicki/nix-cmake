{ lib
, pkgs
, cmake
, cmakeDependencyHook
, rapids-cmake
, fetchFromGitHub
}:

let
  nix-cmake = import ../../lib { inherit lib; };

  # Fetch stdexec source
  stdexecSrc = fetchFromGitHub {
    owner = "nvidia";
    repo = "stdexec";
    rev = "9082d76";
    hash = "sha256-XQ0qC5b70rrcF/ylX7SnOcVi6Yp7b36ncwqMoCQIqOA=";
  };

  # Load workspace with cmake-lock.json
  workspace = (nix-cmake.workspace pkgs).loadWorkspace {
    workspaceRoot = ./.;
  };
in
workspace.buildPackage {
  pname = "stdexec";
  version = "0.1.0";

  src = stdexecSrc;

  nativeBuildInputs = [ rapids-cmake pkgs.git ];

  cmakeFlags = [
    "-DSTDEXEC_BUILD_TESTS=OFF"
    "-DSTDEXEC_BUILD_EXAMPLES=OFF"
  ];

  # stdexec is header-only, so we just need to install headers
  installPhase = ''
    runHook preInstall
    mkdir -p $out/include
    cp -r ../include/stdexec $out/include/
    mkdir -p $out/lib/cmake/stdexec
    cp -r *.cmake $out/lib/cmake/stdexec/ || true
    runHook postInstall
  '';

  meta = {
    description = "Production test with NVIDIA stdexec library using RAPIDS-CMake";
  };
}
