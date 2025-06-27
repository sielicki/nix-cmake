# CMake dependency setup hook - makes Nix dependencies available to CMake
{ lib, writeTextFile, writeShellScript }:

{
  # Main setup hook for CMake dependency management
  setupHook = writeTextFile {
    name = "cmake-nix-dependency-setup-hook";
    text = ''
      # ============================================================================
      # Nix CMake Dependency Setup Hook
      # ============================================================================

      # Hook to process all dependencies
      processCMakeDependencies() {
        echo "Hooking CMake for dependency resolution..." >&2
        export CMAKE_PROJECT_TOP_LEVEL_INCLUDES="''${CMAKE_PROJECT_TOP_LEVEL_INCLUDES:-}:${./cmakeBuildHook.cmake}"
      }
      
      # Override configure phase if using CMake
      if [[ -z "''${dontUseNixCMakeDependencyResolution:-}" ]]; then
        preConfigureHooks+=(processCMakeDependencies)
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
        
        local cmakeFlags=(
          "''${cmakeFlags[@]:-}"
          "-DCMAKE_BUILD_TYPE=''${cmakeBuildType:-Release}"
        )
        
        if [[ -n "''${CMAKE_PROJECT_TOP_LEVEL_INCLUDES:-}" ]]; then
          cmakeFlags+=("-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=$CMAKE_PROJECT_TOP_LEVEL_INCLUDES")
        fi
        
        echo "CMake configuration:"
        echo "  Source directory: $cmakeDir"
        echo "  Build directory: $PWD"
        echo "  Install prefix: ''${!outputBin:-$out}"
        echo "  Toolchain file: ''${CMAKE_TOOLCHAIN_FILE:-<default>}"
        echo "  Dependency provider: ''${CMAKE_PROJECT_TOP_LEVEL_INCLUDES:-<none>}"
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
