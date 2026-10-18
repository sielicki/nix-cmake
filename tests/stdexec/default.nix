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

  # CPM release pinned by rapids-cmake 24.02 (cpm/detail/download.cmake)
  cpmFile = pkgs.fetchurl {
    url = "https://github.com/cpm-cmake/CPM.cmake/releases/download/v0.38.5/CPM.cmake";
    hash = "sha256-GSqgzNxX3+db2eSxdr9/tWkv0rPj97CcdIVvw5Vysxw=";
  };

  # Load workspace with cmake-lock.json
  workspace = (nix-cmake.workspace pkgs).loadWorkspace {
    workspaceRoot = ./.;
  };
in
workspace.buildPackage {
  inherit cmake cmakeDependencyHook;
  pname = "stdexec";
  version = "0.1.0";

  src = stdexecSrc;

  nativeBuildInputs = [ rapids-cmake pkgs.git ];

  # stdexec's CMakeLists downloads RAPIDS.cmake and execution.bs at
  # configure time, which cannot work in the sandbox. Seed hermetic
  # replacements into the build directory: a RAPIDS.cmake that points
  # CMAKE_MODULE_PATH at the Nix-provided rapids-cmake, and an
  # execution.bs carrying just the Revision line stdexec parses for
  # its project version.
  preConfigure = ''
    mkdir -p build/cmake
    cat > build/RAPIDS.cmake <<EOF
    set(rapids-cmake-dir "${rapids-cmake}/share/cmake/rapids-cmake/rapids-cmake")
    list(APPEND CMAKE_MODULE_PATH "${rapids-cmake}/share/cmake/rapids-cmake/rapids-cmake")
    set(rapids-cmake-version 24.02)
    EOF
    cp ${cpmFile} build/cmake/CPM_0.38.5.cmake
    chmod u+w build/cmake/CPM_0.38.5.cmake
    printf 'Revision: 9\n' > build/execution.bs
  '';

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
