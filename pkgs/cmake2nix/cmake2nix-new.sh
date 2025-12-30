#!/usr/bin/env bash
set -euo pipefail

# Find the nix-cmake library path (this will be substituted by Nix)
NIX_CMAKE_LIB="@nix_cmake_lib@"

# Default values
INPUT_FILE="CMakeLists.txt"
LOCK_FILE="cmake-lock.json"
OUTPUT_DIR="."
PACKAGES_NIX="cmake-packages.nix"
ENV_NIX="cmake-env.nix"
COMPOSITION_NIX="default.nix"
CMAKE_FLAGS=""
RECURSIVE=""
NO_PREFETCH=0

show_help() {
  cat <<EOF
cmake2nix - Generate Nix expressions for CMake projects

Usage:
  cmake2nix [command] [options]

Commands:
  discover        Discover dependencies by running CMake (generates lock file)
  prefetch        Prefetch hashes for dependencies in lock file
  generate        Generate Nix expressions from lock file
  lock            Update lock file (discover + prefetch)
  init [dir]      Scaffold a new nix-cmake project
  shell           Enter development shell
  build           Build the project
  help            Show this message

Options:
  -i, --input <file>         CMakeLists.txt location (default: ./CMakeLists.txt)
  -l, --lock-file <file>     Lock file location (default: ./cmake-lock.json)
  -o, --output <dir>         Output directory (default: .)
  --packages-nix <file>      Packages file name (default: cmake-packages.nix)
  --env-nix <file>           Environment file name (default: cmake-env.nix)
  --composition <file>       Composition file name (default: default.nix)
  --cmake-flags <flags>      CMake flags for discovery
  --no-prefetch              Skip hash prefetching
  --recursive                Enable recursive discovery

Examples:
  # Standard workflow (discover + prefetch + generate)
  cmake2nix

  # Just update lock file
  cmake2nix lock

  # Generate from existing lock file
  cmake2nix generate

  # With custom paths
  cmake2nix -i src/CMakeLists.txt -o nix/
EOF
}

# Parse command-line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--input)
        INPUT_FILE="$2"
        shift 2
        ;;
      -l|--lock-file)
        LOCK_FILE="$2"
        shift 2
        ;;
      -o|--output)
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --packages-nix)
        PACKAGES_NIX="$2"
        shift 2
        ;;
      --env-nix)
        ENV_NIX="$2"
        shift 2
        ;;
      --composition)
        COMPOSITION_NIX="$2"
        shift 2
        ;;
      --cmake-flags)
        CMAKE_FLAGS="$2"
        shift 2
        ;;
      --no-prefetch)
        NO_PREFETCH=1
        shift
        ;;
      --recursive)
        RECURSIVE="-DNIX_CMAKE_RECURSIVE_DISCOVERY=1"
        shift
        ;;
      *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

# Discover dependencies by running CMake
command_discover() {
  echo "cmake2nix: Discovering dependencies..."

  if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: $INPUT_FILE not found"
    exit 1
  fi

  local src_dir
  src_dir=$(dirname "$INPUT_FILE")

  # Check if we're in a flake
  local has_flake=0
  if [ -f "flake.nix" ]; then
    has_flake=1
    echo "cmake2nix: Detected flake.nix, using flake-based discovery"
  fi

  # Create discovery derivation
  local discovery_drv
  if [ $has_flake -eq 1 ]; then
    # Try to use flake's discovery output
    if nix eval .#discovery --extra-experimental-features "nix-command flakes" >/dev/null 2>&1; then
      discovery_drv=$(nix build .#discovery --no-link --print-out-paths --extra-experimental-features "nix-command flakes")
    else
      # Fall back to manual discovery
      discovery_drv=$(run_manual_discovery "$src_dir")
    fi
  else
    # Non-flake: manual discovery
    discovery_drv=$(run_manual_discovery "$src_dir")
  fi

  echo "cmake2nix: Generating lock file from discovery results..."

  # Generate lock file from discovery log
  nix eval --json --impure --expr "
    let
      pkgs = import <nixpkgs> {};
      nix-cmake = import ${NIX_CMAKE_LIB} { inherit (pkgs) lib; };
      workspace = nix-cmake.workspace pkgs;
    in workspace.generateLock \"${discovery_drv}\"
  " > "$LOCK_FILE"

  echo "cmake2nix: Lock file generated: $LOCK_FILE"

  if [ $NO_PREFETCH -eq 0 ]; then
    echo "cmake2nix: ⚠️  Lock file contains placeholder hashes. Run 'cmake2nix prefetch' to get real hashes."
  fi
}

# Run manual discovery without flake
run_manual_discovery() {
  local src_dir="$1"

  # Build discovery derivation
  nix-build --no-out-link --expr "
    let
      pkgs = import <nixpkgs> {};
      nix-cmake = import ${NIX_CMAKE_LIB} { inherit (pkgs) lib; };
      workspace = nix-cmake.workspace pkgs;
    in
    workspace.discoverDependencies {
      src = $src_dir;
      cmakeFlags = [ $CMAKE_FLAGS $RECURSIVE ];
    }
  "
}

# Prefetch hashes for all dependencies
command_prefetch() {
  echo "cmake2nix: Prefetching dependency hashes..."

  if [ ! -f "$LOCK_FILE" ]; then
    echo "Error: Lock file not found: $LOCK_FILE"
    echo "Run 'cmake2nix discover' first"
    exit 1
  fi

  # Read lock file and prefetch each dependency
  local temp_lock
  temp_lock=$(mktemp)

  nix eval --json --impure --expr "
    let
      pkgs = import <nixpkgs> {};
      lib = pkgs.lib;
      lock = builtins.fromJSON (builtins.readFile ./$LOCK_FILE);

      # Prefetch each dependency
      prefetchDep = name: dep:
        if dep.method == \"fetchFromGitHub\" then
          let
            result = builtins.fetchGit {
              url = \"https://github.com/\${dep.args.owner}/\${dep.args.repo}\";
              ref = dep.args.rev;
            };
          in dep // {
            args = dep.args // {
              hash = result.narHash or dep.args.hash;
            };
          }
        else if dep.method == \"fetchgit\" then
          let
            result = builtins.fetchGit {
              url = dep.args.url;
              ref = dep.args.rev or \"HEAD\";
            };
          in dep // {
            args = dep.args // {
              sha256 = result.narHash or dep.args.sha256;
            };
          }
        else
          dep;

      prefetchedDeps = lib.mapAttrs prefetchDep (lock.dependencies or {});

    in
    lock // { dependencies = prefetchedDeps; }
  " > "$temp_lock"

  mv "$temp_lock" "$LOCK_FILE"

  local count
  count=$(jq '.dependencies | length' "$LOCK_FILE")
  echo "cmake2nix: ✓ Lock file updated with $count dependencies"
}

# Generate Nix expressions from lock file
command_generate() {
  echo "cmake2nix: Generating Nix expressions..."

  if [ ! -f "$LOCK_FILE" ]; then
    echo "Error: Lock file not found: $LOCK_FILE"
    echo "Run 'cmake2nix discover' first"
    exit 1
  fi

  mkdir -p "$OUTPUT_DIR"

  # Parse CMakeLists.txt for project info
  local project_info
  project_info=$(nix eval --json --impure --expr "
    let
      pkgs = import <nixpkgs> {};
      nix-cmake = import ${NIX_CMAKE_LIB} { inherit (pkgs) lib; };
      generators = nix-cmake.generators;
    in
    generators.parseCMakeLists ./$INPUT_FILE
  ")

  local pname
  local version
  pname=$(echo "$project_info" | jq -r '.pname')
  version=$(echo "$project_info" | jq -r '.version')

  echo "cmake2nix: Detected project: $pname v$version"

  # Generate cmake-packages.nix
  echo "cmake2nix: Generating $OUTPUT_DIR/$PACKAGES_NIX..."
  nix eval --raw --impure --expr "
    let
      pkgs = import <nixpkgs> {};
      nix-cmake = import ${NIX_CMAKE_LIB} { inherit (pkgs) lib; };
      generators = nix-cmake.generators;
      lock = builtins.fromJSON (builtins.readFile ./$LOCK_FILE);
    in
    generators.generatePackagesNix lock
  " > "$OUTPUT_DIR/$PACKAGES_NIX"

  # Generate cmake-env.nix
  echo "cmake2nix: Generating $OUTPUT_DIR/$ENV_NIX..."
  nix eval --raw --impure --expr "
    let
      pkgs = import <nixpkgs> {};
      nix-cmake = import ${NIX_CMAKE_LIB} { inherit (pkgs) lib; };
      generators = nix-cmake.generators;
    in
    generators.generateEnvNix { nixCmakePath = \"${NIX_CMAKE_LIB}\"; }
  " > "$OUTPUT_DIR/$ENV_NIX"

  # Generate default.nix
  echo "cmake2nix: Generating $OUTPUT_DIR/$COMPOSITION_NIX..."
  nix eval --raw --impure --expr "
    let
      pkgs = import <nixpkgs> {};
      nix-cmake = import ${NIX_CMAKE_LIB} { inherit (pkgs) lib; };
      generators = nix-cmake.generators;
    in
    generators.generateDefaultNix {
      pname = \"$pname\";
      version = \"$version\";
    }
  " > "$OUTPUT_DIR/$COMPOSITION_NIX"

  echo "cmake2nix: ✓ Generated:"
  echo "  - $OUTPUT_DIR/$PACKAGES_NIX"
  echo "  - $OUTPUT_DIR/$ENV_NIX"
  echo "  - $OUTPUT_DIR/$COMPOSITION_NIX"
  echo ""
  echo "Usage:"
  echo "  nix-build -A package       # Build the project"
  echo "  nix-shell -A shell         # Enter development shell"
}

# Update lock file (discover + prefetch)
command_lock() {
  command_discover
  if [ $NO_PREFETCH -eq 0 ]; then
    command_prefetch
  fi
}

# Initialize a new project
command_init() {
  local dir="${1:-.}"
  mkdir -p "$dir"
  cd "$dir"

  echo "cmake2nix: Scaffolding project in $dir..."

  cat > CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.24)
project(my-nix-project VERSION 0.1.0)

add_executable(app main.cpp)
EOF

  cat > main.cpp <<'EOF'
#include <iostream>

int main() {
    std::cout << "Hello from nix-cmake!" << std::endl;
    return 0;
}
EOF

  echo "cmake2nix: Project initialized"
  echo "cmake2nix: Run 'cmake2nix' to generate Nix expressions"
}

# Enter development shell
command_shell() {
  if [ -f "$OUTPUT_DIR/$COMPOSITION_NIX" ]; then
    nix-shell "$OUTPUT_DIR/$COMPOSITION_NIX" -A shell
  else
    echo "Error: $OUTPUT_DIR/$COMPOSITION_NIX not found"
    echo "Run 'cmake2nix generate' first"
    exit 1
  fi
}

# Build the project
command_build() {
  if [ -f "$OUTPUT_DIR/$COMPOSITION_NIX" ]; then
    nix-build "$OUTPUT_DIR/$COMPOSITION_NIX" -A package
  else
    echo "Error: $OUTPUT_DIR/$COMPOSITION_NIX not found"
    echo "Run 'cmake2nix generate' first"
    exit 1
  fi
}

# Main command dispatcher
COMMAND=${1:-}
shift || true

# Parse remaining arguments
if [ -n "$COMMAND" ] && [ "$COMMAND" != "help" ] && [ "$COMMAND" != "init" ]; then
  parse_args "$@"
fi

case "$COMMAND" in
  discover)
    command_discover
    ;;
  prefetch)
    command_prefetch
    ;;
  generate)
    command_generate
    ;;
  lock)
    command_lock
    ;;
  init)
    command_init "${1:-.}"
    ;;
  shell)
    command_shell
    ;;
  build)
    command_build
    ;;
  help|--help|-h|"")
    show_help
    ;;
  *)
    # Default: full workflow (discover + prefetch + generate)
    COMMAND="generate"
    parse_args "$@"
    command_discover
    if [ $NO_PREFETCH -eq 0 ]; then
      command_prefetch
    fi
    command_generate
    ;;
esac
