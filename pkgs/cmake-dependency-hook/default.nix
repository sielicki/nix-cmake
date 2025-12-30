# CMake dependency setup hook - makes Nix dependencies available to CMake
{ lib, writeTextFile, writeShellScript, cmake ? null }:

{
  # Main setup hook for CMake dependency management
  setupHook = writeTextFile {
    name = "cmake-nix-dependency-setup-hook";
    text = ''
      # ============================================================================
      # Nix CMake Dependency Setup Hook
      # ============================================================================
      # This hook sets up the CMake dependency provider that intercepts
      # FetchContent calls and redirects them to find_package() for
      # pre-built Nix packages.

      # Set up CMAKE_PROJECT_TOP_LEVEL_INCLUDES to load our dependency provider
      # This needs to be passed as a CMake variable (-D flag), not an env var
      if [[ -n "''${NIX_CMAKE_TOP_LEVEL_INCLUDES:-}" ]]; then
        export NIX_CMAKE_TOP_LEVEL_INCLUDES="''${NIX_CMAKE_TOP_LEVEL_INCLUDES};${./cmakeBuildHook.cmake}"
      else
        export NIX_CMAKE_TOP_LEVEL_INCLUDES="${./cmakeBuildHook.cmake}"
      fi

      # Enhanced CMake configure phase with dependency management
      nixCmakeConfigurePhase() {
        echo "running preConfigure..." >&2
        runHook preConfigure
        echo "running configure..." >&2
        
        if [[ -z "''${cmakeBuildDir-}" ]]; then
          cmakeBuildDir=build
        fi
        
        if [[ -z "''${dontUseCmakeBuildDir-}" ]]; then
          mkdir -p "$cmakeBuildDir"
          cd "$cmakeBuildDir"
          cmakeDir=''${cmakeDir:-..}
        else
          cmakeDir=''${cmakeDir:-.}
        fi
        
        # Convert cmakeFlags from space-separated string to array
        # Nix passes lists as space-separated strings in environment variables
        local cmakeFlagsArray=()
        if [[ -n "''${cmakeFlags:-}" ]]; then
          read -ra cmakeFlagsArray <<< "$cmakeFlags"
        fi

        local cmakeFlags=(
          "''${cmakeFlagsArray[@]}"
          "-DCMAKE_BUILD_TYPE=''${cmakeBuildType:-Release}"
        )

        # Add CMAKE_PROJECT_TOP_LEVEL_INCLUDES if we have it
        if [[ -n "''${NIX_CMAKE_TOP_LEVEL_INCLUDES:-}" ]]; then
          cmakeFlags+=("-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=''${NIX_CMAKE_TOP_LEVEL_INCLUDES}")
        fi

        # Synchronize CMAKE_PREFIX_PATH with Nix search paths if needed
        # Our hook will also manage this in CMake, but setting it here helps boot-strapping find_package
        if [[ -n "''${CMAKE_PREFIX_PATH:-}" ]]; then
           cmakeFlags+=("-DCMAKE_PREFIX_PATH=''${CMAKE_PREFIX_PATH}")
        fi

        # Ignore impure system paths (zero-patch philosophy)
        # Instead of patching CMake modules, we use CMAKE_SYSTEM_IGNORE_PREFIX_PATH
        # to tell CMake not to search in system locations
        local ignorePaths=(
          "/usr"
          "/usr/local"
          "/opt"
          "/Library"
          "/System/Library"
          "/opt/local"           # MacPorts
          "/opt/homebrew"        # Homebrew on Apple Silicon
          "/sw"                  # Fink
        )
        local ignorePathsStr="''${ignorePaths[0]}"
        for path in "''${ignorePaths[@]:1}"; do
          ignorePathsStr="$ignorePathsStr;$path"
        done
        cmakeFlags+=("-DCMAKE_SYSTEM_IGNORE_PREFIX_PATH=$ignorePathsStr")

        # Also set CURL_CA_BUNDLE if cacert is available in buildInputs
        # This avoids needing to patch curl's CMakeLists.txt
        if [[ -n "''${NIX_SSL_CERT_FILE:-}" ]]; then
          cmakeFlags+=("-DCURL_CA_BUNDLE=''${NIX_SSL_CERT_FILE}")
        fi

        echo "CMake configuration:"
        echo "  Source directory: $cmakeDir"
        echo "  Build directory: $PWD"
        echo "  Install prefix: ''${!outputBin:-$out}"
        echo "  Toolchain file: ''${CMAKE_TOOLCHAIN_FILE:-<default>}"
        echo "  Top-level includes: ''${NIX_CMAKE_TOP_LEVEL_INCLUDES:-<not set>}"
        echo "  Ignored prefixes: $ignorePathsStr"
        echo "  Flags: ''${cmakeFlags[*]}"

        # Run CMake
        cmake "$cmakeDir" "''${cmakeFlags[@]}"
        
        runHook postConfigure
      }
      
      # Override configure phase if using CMake
      if [[ -z "''${dontUseNixCMakeSetup:-}" ]]; then
        configurePhase=nixCmakeConfigurePhase
      fi
    '';
  };

  # Utility script for debugging CMake dependency resolution
  debugScript = writeShellScript "cmake-debug-deps" ''
    echo "=== CMake Dependency Debug ==="
    echo "CMAKE_PREFIX_PATH: ''${CMAKE_PREFIX_PATH:-<not set>}"
    echo "CMAKE_INCLUDE_PATH: ''${CMAKE_INCLUDE_PATH:-<not set>}"
    echo "CMAKE_LIBRARY_PATH: ''${CMAKE_LIBRARY_PATH:-<not set>}"
    echo "CMAKE_PROGRAM_PATH: ''${CMAKE_PROGRAM_PATH:-<not set>}"
    echo "CMAKE_TOOLCHAIN_FILE: ''${CMAKE_TOOLCHAIN_FILE:-<not set>}"
    echo "CMAKE_PROJECT_TOP_LEVEL_INCLUDES: ''${CMAKE_PROJECT_TOP_LEVEL_INCLUDES:-<not set>}"
    echo ""
    echo "Available packages in CMAKE_PREFIX_PATH:"
    IFS=':' read -ra PATHS <<< "''${CMAKE_PREFIX_PATH:-}"
    for path in "''${PATHS[@]}"; do
      if [[ -d "$path/lib/cmake" ]]; then
        echo "  $path/lib/cmake:"
        find "$path/lib/cmake" -name "*Config.cmake" -o -name "*-config.cmake" 2>/dev/null | sed 's/^/    /'
      fi
    done
  '';
}
