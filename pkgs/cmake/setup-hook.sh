# shellcheck shell=bash
# Basic CMake setup hook - runs cmake during configure phase.
# This is separate from cmakeToolchainHook and cmakeDependencyHook.
# It is sourced by stdenv, which provides variables such as
# $buildInputs, $cmakeFlags and $out.
# shellcheck disable=SC2154

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

    # NOTE: unlike nixpkgs' cmake hook, we deliberately do not rewrite
    # @PACKAGE_*@ placeholders in the project's source files
    # (zero-patch philosophy; templates such as @PACKAGE_INIT@ are
    # valid CMake and must pass through untouched).

    if [ -z "${dontUseCmakeBuildDir-}" ]; then
        cmakeBuildDir=${cmakeBuildDir:-build}
        mkdir -p "$cmakeBuildDir"
        cd "$cmakeBuildDir" || return
        cmakeDir=${cmakeDir:-..}
    fi

    # Default build type (prepended: user -D later in $cmakeFlags wins)
    cmakeFlags="-DCMAKE_BUILD_TYPE=${cmakeBuildType:-Release} $cmakeFlags"

    if [ -z "$dontAddPrefix" ]; then
        # Absolute GNUInstallDirs paths into the Nix output(s), mirroring
        # nixpkgs' cmake hook; without these, libraries land in lib64
        # and executables lack an RPATH to their own libraries. These
        # flags are prepended, so user -D values (later) still win.
        cmakeFlags="-DCMAKE_INSTALL_PREFIX=${!outputBin:-$out} $cmakeFlags"
        cmakeFlags="-DCMAKE_INSTALL_BINDIR=${!outputBin:-$out}/bin $cmakeFlags"
        cmakeFlags="-DCMAKE_INSTALL_SBINDIR=${!outputBin:-$out}/sbin $cmakeFlags"
        cmakeFlags="-DCMAKE_INSTALL_INCLUDEDIR=${!outputInclude:-$out}/include $cmakeFlags"
        cmakeFlags="-DCMAKE_INSTALL_MANDIR=${!outputMan:-$out}/share/man $cmakeFlags"
        cmakeFlags="-DCMAKE_INSTALL_INFODIR=${!outputInfo:-$out}/share/info $cmakeFlags"
        cmakeFlags="-DCMAKE_INSTALL_DOCDIR=${!outputDoc:-$out}/share/doc $cmakeFlags"
        cmakeFlags="-DCMAKE_INSTALL_LIBDIR=${!outputLib:-$out}/lib $cmakeFlags"
        cmakeFlags="-DCMAKE_INSTALL_LIBEXECDIR=${!outputLib:-$out}/libexec $cmakeFlags"
        cmakeFlags="-DCMAKE_INSTALL_LOCALEDIR=${!outputLib:-$out}/share/locale $cmakeFlags"
        cmakeFlags="-DCMAKE_INSTALL_NAME_DIR=${!outputLib:-$out}/lib $cmakeFlags"
    fi

    # Build CMAKE_PREFIX_PATH from all dependencies, including the
    # propagated-input closure (stdenv accumulates it in the
    # pkgsHostTarget/pkgsBuild* arrays). This allows find_package()
    # to locate (transitive) dependencies.
    local cmakePrefixPath=""
    local -a _allDeps=()
    if [[ -v pkgsHostTarget ]]; then _allDeps+=("${pkgsHostTarget[@]}"); fi
    if [[ -v pkgsBuildBuild ]]; then _allDeps+=("${pkgsBuildBuild[@]}"); fi
    if [[ -v pkgsBuildTarget ]]; then _allDeps+=("${pkgsBuildTarget[@]}"); fi
    # shellcheck disable=SC2206 # scalar fallbacks are space-separated lists
    _allDeps+=(${buildInputs-} ${propagatedBuildInputs-} ${nativeBuildInputs-})
    local dep
    for dep in "${_allDeps[@]}"; do
        if [ -d "$dep" ]; then
            case ";$cmakePrefixPath;" in
                *";$dep;"*) ;;
                *) cmakePrefixPath="${cmakePrefixPath:+$cmakePrefixPath;}$dep" ;;
            esac
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
        # $cmakePlatforms is a space-separated flag list; splitting is intended.
        # shellcheck disable=SC2206
        cmakeFlagsArray+=(${cmakePlatforms})
    fi

    echo "cmake flags: $cmakeFlags ${cmakeFlagsArray[*]+"${cmakeFlagsArray[*]}"}"

    # $cmakeFlags is a space-separated flag list; splitting is intended.
    # shellcheck disable=SC2086
    cmake "${cmakeDir:-.}" $cmakeFlags ${cmakeFlagsArray[@]+"${cmakeFlagsArray[@]}"}

    if ! [[ -v enableParallelBuilding ]]; then
        enableParallelBuilding=1
        echo "cmake: enabled parallel building"
    fi

    runHook postConfigure
}

if [ -z "${dontUseCmakeConfigure-}" ] && [ -z "${configurePhase-}" ]; then
    # Read by stdenv's setOutputFlags logic, hence "unused" locally.
    # shellcheck disable=SC2034
    setOutputFlags=
    configurePhase=cmakeConfigurePhase
fi

if [ -n "${dontUseCmakeConfigure-}" ] || [ -n "${dontUseNixCMakeSetup-}" ]; then
    unset -f cmakeConfigurePhase
fi
