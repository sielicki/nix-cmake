# Basic CMake setup hook - runs cmake during configure phase
# This is separate from cmakeToolchainHook and cmakeDependencyHook

addCMakeParams() {
    cmakeFlags="$cmakeFlags ${1@Q}"
}

fixCmakeFiles() {
    # Avoid depending on `build-machines.nix` and `default-gcc-libc-paths.patch`, for now.
    # Remove absolute paths from CMake config files.
    for file in "$1"/*.cmake "$1"/cmake/*.cmake; do
        [ -f "$file" ] || continue
        substituteInPlace "$file" \
            --replace-fail '@PACKAGE_PREFIX_PATH@/' '@PACKAGE_PREFIX_PATH@'
    done
}

cmakeConfigurePhase() {
    runHook preConfigure

    if [ -z "${dontFixCmake-}" ]; then
        find . -name "*.cmake" -o -name "*.cmake.in" | while IFS= read -r file; do
            substituteInPlace "$file" \
                --replace-quiet '@PACKAGE_' '@PACKAGE@'
        done
    fi

    if [ -z "${dontUseCmakeBuildDir-}" ]; then
        cmakeBuildDir=${cmakeBuildDir:-build}
        mkdir -p "$cmakeBuildDir"
        cd "$cmakeBuildDir"
        cmakeDir=${cmakeDir:-..}
    fi

    if [ -z "$dontAddPrefix" ]; then
        cmakeFlags="-DCMAKE_INSTALL_PREFIX=${!outputBin:-$out} $cmakeFlags"
    fi

    # Build CMAKE_PREFIX_PATH from all dependencies
    # This allows find_package() to locate dependencies
    local cmakePrefixPath=""
    for dep in $buildInputs $propagatedBuildInputs $nativeBuildInputs; do
        if [ -d "$dep" ]; then
            if [ -n "$cmakePrefixPath" ]; then
                cmakePrefixPath="$cmakePrefixPath;$dep"
            else
                cmakePrefixPath="$dep"
            fi
        fi
    done

    if [ -n "$cmakePrefixPath" ]; then
        cmakeFlags="-DCMAKE_PREFIX_PATH=$cmakePrefixPath $cmakeFlags"
    fi

    # We should set the proper `CMAKE_SYSTEM_NAME`.
    # http://www.cmake.org/Wiki/CMake_Cross_Compiling
    #
    # Unfortunately cmake seems to expect absolute paths for ar, ranlib, and strip.
    # Otherwise they are taken to be relative to the source root of the package
    # being built.
    if [ -n "${cmakePlatforms-}" ]; then
        cmakeFlagsArray+=(
            ${cmakePlatforms}
        )
    fi

    echo "cmake flags: $cmakeFlags ${cmakeFlagsArray[@]}"

    cmake ${cmakeDir:-.} $cmakeFlags "${cmakeFlagsArray[@]}"

    if ! [[ -v enableParallelBuilding ]]; then
        enableParallelBuilding=1
        echo "cmake: enabled parallel building"
    fi

    runHook postConfigure
}

if [ -z "${dontUseCmakeConfigure-}" ] && [ -z "${configurePhase-}" ]; then
    setOutputFlags=
    configurePhase=cmakeConfigurePhase
fi

if [ -n "${dontUseCmakeConfigure-}" ] || [ -n "${dontUseNixCMakeSetup-}" ]; then
    unset -f cmakeConfigurePhase
fi
