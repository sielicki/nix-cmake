# CMake dependency setup hook - makes Nix dependencies available to CMake
{ writeTextFile, writeShellScript }:

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
        
        # Convert cmakeFlags from space-separated string to array.
        # Nix passes lists as space-separated strings in environment
        # variables (so a flag containing spaces cannot be expressed
        # this way). A pre-existing `cmakeFlagsArray` bash array, e.g.
        # set by preConfigure, is honoured as-is.
        local parsedCmakeFlags=()
        if [[ -n "''${cmakeFlags:-}" ]]; then
          read -ra parsedCmakeFlags <<< "$cmakeFlags"
        fi
        if [[ -v cmakeFlagsArray ]]; then
          parsedCmakeFlags+=("''${cmakeFlagsArray[@]}")
        fi

        local cmakeFlags=(
          "''${parsedCmakeFlags[@]}"
          "-DCMAKE_BUILD_TYPE=''${cmakeBuildType:-Release}"
        )

        # Install into the Nix output(s) with absolute GNUInstallDirs
        # paths (mirrors nixpkgs' cmake hook). Without these, projects
        # install libraries into lib64 and executables end up without
        # an RPATH to their own libraries. User-supplied -D values for
        # the same variables win: CMake uses the last -D on the command
        # line, and ours are appended only when absent from user flags.
        if [[ -z "''${dontAddPrefix:-}" ]]; then
          local _nixCmakeHasFlag=""
          for _flag in "''${parsedCmakeFlags[@]}"; do
            case "$_flag" in
              -DCMAKE_INSTALL_PREFIX=*|-DCMAKE_INSTALL_BINDIR=*|-DCMAKE_INSTALL_SBINDIR=*|-DCMAKE_INSTALL_INCLUDEDIR=*|-DCMAKE_INSTALL_MANDIR=*|-DCMAKE_INSTALL_INFODIR=*|-DCMAKE_INSTALL_DOCDIR=*|-DCMAKE_INSTALL_LIBDIR=*|-DCMAKE_INSTALL_LIBEXECDIR=*|-DCMAKE_INSTALL_LOCALEDIR=*|-DCMAKE_INSTALL_NAME_DIR=*)
                _nixCmakeHasFlag="$_nixCmakeHasFlag ''${_flag%%=*} " ;;
            esac
          done
          _nixCmakeMaybe() {
            case " $_nixCmakeHasFlag " in
              *" $1 "*) ;;
              *) cmakeFlags+=("$1=$2") ;;
            esac
          }
          _nixCmakeMaybe -DCMAKE_INSTALL_PREFIX "''${!outputBin:-$out}"
          _nixCmakeMaybe -DCMAKE_INSTALL_BINDIR "''${!outputBin:-$out}/bin"
          _nixCmakeMaybe -DCMAKE_INSTALL_SBINDIR "''${!outputBin:-$out}/sbin"
          _nixCmakeMaybe -DCMAKE_INSTALL_INCLUDEDIR "''${!outputInclude:-$out}/include"
          _nixCmakeMaybe -DCMAKE_INSTALL_MANDIR "''${!outputMan:-$out}/share/man"
          _nixCmakeMaybe -DCMAKE_INSTALL_INFODIR "''${!outputInfo:-$out}/share/info"
          _nixCmakeMaybe -DCMAKE_INSTALL_DOCDIR "''${!outputDoc:-$out}/share/doc"
          _nixCmakeMaybe -DCMAKE_INSTALL_LIBDIR "''${!outputLib:-$out}/lib"
          _nixCmakeMaybe -DCMAKE_INSTALL_LIBEXECDIR "''${!outputLib:-$out}/libexec"
          _nixCmakeMaybe -DCMAKE_INSTALL_LOCALEDIR "''${!outputLib:-$out}/share/locale"
          _nixCmakeMaybe -DCMAKE_INSTALL_NAME_DIR "''${!outputLib:-$out}/lib"
          unset -f _nixCmakeMaybe
        fi

        # Add CMAKE_PROJECT_TOP_LEVEL_INCLUDES if we have it
        if [[ -n "''${NIX_CMAKE_TOP_LEVEL_INCLUDES:-}" ]]; then
          cmakeFlags+=("-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=''${NIX_CMAKE_TOP_LEVEL_INCLUDES}")
        fi

        # Synchronize CMAKE_PREFIX_PATH with Nix search paths.
        # cmakeBuildHook.cmake also manages this in CMake, but passing
        # it explicitly makes module-mode find_package calls (e.g.
        # FindOpenSSL) work before/regardless of hook processing.
        # Note: the environment form is colon-separated; CMake lists
        # are semicolon-separated.
        # Iterate stdenv's accumulated dependency arrays (which include
        # the propagated-input closure, e.g. fmt via spdlog's
        # propagatedBuildInputs) rather than only the direct input
        # strings. Falls back to the plain variables when the arrays
        # are unavailable.
        local cmakePrefixPath=""
        local _allDeps=()
        if [[ -v pkgsHostTarget ]]; then _allDeps+=("''${pkgsHostTarget[@]}"); fi
        if [[ -v pkgsBuildBuild ]]; then _allDeps+=("''${pkgsBuildBuild[@]}"); fi
        if [[ -v pkgsBuildTarget ]]; then _allDeps+=("''${pkgsBuildTarget[@]}"); fi
        _allDeps+=(''${buildInputs:-} ''${propagatedBuildInputs:-} ''${nativeBuildInputs:-})
        for dep in "''${_allDeps[@]}"; do
          if [[ -d "$dep" ]]; then
            case ";$cmakePrefixPath;" in
              *";$dep;"*) ;;
              *) cmakePrefixPath="''${cmakePrefixPath:+$cmakePrefixPath;}$dep" ;;
            esac
          fi
        done
        if [[ -n "''${CMAKE_PREFIX_PATH:-}" ]]; then
          local envPrefixPath="''${CMAKE_PREFIX_PATH//:/;}"
          cmakePrefixPath="''${cmakePrefixPath:+$cmakePrefixPath;}$envPrefixPath"
        fi
        if [[ -n "$cmakePrefixPath" ]]; then
          cmakeFlags+=("-DCMAKE_PREFIX_PATH=$cmakePrefixPath")
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
