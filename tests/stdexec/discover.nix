{ lib
, pkgs
, cmake
, cmakeDependencyHook
, rapids-cmake
, fetchFromGitHub
}:

let
  nix-cmake = import ../../lib { inherit lib; };
  workspace = nix-cmake.workspace pkgs;

  stdexecSrc = fetchFromGitHub {
    owner = "nvidia";
    repo = "stdexec";
    rev = "9082d76";
    hash = "sha256-XQ0qC5b70rrcF/ylX7SnOcVi6Yp7b36ncwqMoCQIqOA=";
  };
in
workspace.discoverDependencies {
  pname = "stdexec-discovery";
  version = "0.1.0";

  src = stdexecSrc;

  nativeBuildInputs = [ rapids-cmake pkgs.git ];

  cmakeFlags = [
    "-DSTDEXEC_BUILD_TESTS=OFF"
    "-DSTDEXEC_BUILD_EXAMPLES=OFF"
  ];
}
