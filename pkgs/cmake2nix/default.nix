{ lib
, pkgs
, cmake
, ninja
, cmakeDependencyHook
, nix
, nix-prefetch-github
, git
, makeBinaryWrapper
}:

let
  # Import nix-cmake library
  nix-cmake = import ../../lib { inherit lib; };

  # Load workspace with cmake-lock.json
  workspace = (nix-cmake.workspace pkgs).loadWorkspace {
    workspaceRoot = ./.;
  };

in

# Use workspace.buildPackage for automatic dependency injection
workspace.buildPackage {
  pname = "cmake2nix";
  version = "0.2.0";

  nativeBuildInputs = [
    cmake
    ninja
    cmakeDependencyHook
    makeBinaryWrapper
  ];

  # Runtime dependencies that cmake2nix shells out to
  buildInputs = [
    nix
    nix-prefetch-github
    git
  ];

  cmakeFlags = [
    "-GNinja"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}"
  ];

  # Make nix commands available at runtime
  postInstall = ''
    wrapProgram $out/bin/cmake2nix \
      --prefix PATH : ${lib.makeBinPath [ nix nix-prefetch-github git ]}
  '';

  meta = with lib; {
    description = "Generate Nix expressions for CMake projects (C++23 implementation)";
    longDescription = ''
      cmake2nix is a tool for managing CMake-based C++ projects with Nix.
      It discovers dependencies via CMake's FetchContent and CPM, generates
      lock files with hashes, and produces standalone Nix expressions.

      This version is written in C++23 using CMake and CPM, demonstrating
      a meta-circular implementation where cmake2nix can generate its own
      lock file and Nix expressions.
    '';
    homepage = "https://github.com/sielicki/nix-cmake";
    license = licenses.asl20;
    maintainers = [ ];
    mainProgram = "cmake2nix";
    platforms = platforms.unix;
  };
}
