#!/usr/bin/env bash
set -euo pipefail

# Find the nix-cmake library path (this will be substituted by Nix)
NIX_CMAKE_LIB="@nix_cmake_lib@"

show_help() {
  echo "cmake2nix - A CLI for managing Nix-CMake projects"
  echo ""
  echo "Usage:"
  echo "  cmake2nix lock          Update cmake-lock.json from project state"
  echo "  cmake2nix init [dir]    Scaffold a new Nix-CMake project"
  echo "  cmake2nix help          Show this message"
}

command_lock() {
  echo "Nix-CMake: Generating discovery log..."
  
  # Ensure we have a flake.nix or expression to build discovery
  if [ ! -f "flake.nix" ]; then
    echo "Error: No flake.nix found in current directory."
    exit 1
  fi

  # Build the discovery derivation
  # We assume the flake has a 'discovery' output or we evaluate it directly
  DISCOVERY_DIR=$(nix build .#discovery --no-link --print-out-paths --extra-experimental-features "nix-command flakes")

  echo "Nix-CMake: Generating lock file..."
  
  # Evaluate generateLock for the discovery result
  # We use a temporary Nix expression to call the library
  nix eval --json --extra-experimental-features "nix-command flakes" --expr "
    let
      pkgs = import <nixpkgs> {};
      nix-cmake = import ${NIX_CMAKE_LIB} { inherit (pkgs) lib; };
      workspace = nix-cmake.workspace pkgs;
    in workspace.generateLock \"${DISCOVERY_DIR}\"
  " > cmake-lock.json

  echo "Nix-CMake: Successfully updated cmake-lock.json"
}

command_init() {
  DIR=${1:-.}
  mkdir -p "$DIR"
  cd "$DIR"

  echo "Nix-CMake: Scaffolding project in $DIR..."

  cat > CMakeLists.txt <<EOF
cmake_minimum_required(VERSION 3.24)
project(my-nix-project)
add_executable(app main.cpp)
EOF

  cat > main.cpp <<EOF
#include <iostream>
int main() {
    std::cout << "Hello from Nix-CMake!" << std::endl;
    return 0;
}
EOF

  cat > flake.nix <<EOF
{
  inputs.nix-cmake.url = "github:sielicki/nix-cmake";

  outputs = { self, nixpkgs, nix-cmake }: 
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      workspace = nix-cmake.lib.workspace pkgs {
        src = ./.;
        lockFile = ./cmake-lock.json;
      };
    in {
      packages.x86_64-linux.default = workspace.buildPackage {
        pname = "my-project";
        version = "0.1.0";
      };

      devShells.x86_64-linux.default = workspace.mkShell {};

      checks.x86_64-linux.discovery = workspace.discoverDependencies {
        src = ./.;
      };
    };
}
EOF

  echo "Nix-CMake: Project initialized. Run 'cmake2nix lock' to generate initial lock file if needed (once dependencies are added)."
}

COMMAND=${1:-help}
shift || true

case "$COMMAND" in
  lock) command_lock ;;
  init) command_init "${1:-.}" ;;
  help|--help|-h) show_help ;;
  *)
    echo "Unknown command: $COMMAND"
    show_help
    exit 1
    ;;
esac
