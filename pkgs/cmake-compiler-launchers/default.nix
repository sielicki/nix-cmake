{ lib, writeShellScript, stdenv }:

let
  inherit (stdenv) hostPlatform;
  inherit (stdenv.cc) libc;

  nixIncludePaths = [
    "${lib.getDev libc}/include"
  ];

  nixLibraryPaths = [
    "${lib.getLib libc}/lib"
  ];

  platformFlags = lib.optionalAttrs hostPlatform.isDarwin
    {
      commonLinkerFlags = [
        "-Wl,-headerpad_max_install_names"
      ];
    } // lib.optionalAttrs hostPlatform.isLinux {
    commonLinkerFlags = [
      "-Wl,--enable-new-dtags"
    ];
  };

in
{
  cCompilerLauncher = writeShellScript "nix-gcc-launcher" ''
    set -euo pipefail
    compiler="$1"
    shift
    
    nix_flags=()
    ${lib.concatMapStringsSep "\n" (path: ''
      nix_flags+=("-I${path}")
    '') nixIncludePaths}
    
    ${lib.concatMapStringsSep "\n" (path: ''
      nix_flags+=("-L${path}")
    '') nixLibraryPaths}
    
    ${lib.optionalString hostPlatform.isDarwin ''
    nix_flags+=("-mmacosx-version-min=${hostPlatform.darwinMinVersion}")
    ''}
    
    if [[ "''${NIX_DEBUG_CMAKE:-}" == "1" ]]; then
      echo "NIX CMAKE COMPILER LAUNCHER: $compiler ''${nix_flags[@]} $@" >&2
    fi
    
    exec "$compiler" "''${nix_flags[@]}" "$@"
  '';

  cxxCompilerLauncher = writeShellScript "nix-g++-launcher" ''
    set -euo pipefail
    compiler="$1"
    shift
    
    nix_flags=()
    ${lib.concatMapStringsSep "\n" (path: ''
      nix_flags+=("-I${path}")
    '') nixIncludePaths}
    
    ${lib.concatMapStringsSep "\n" (path: ''
      nix_flags+=("-L${path}")
    '') nixLibraryPaths}
    
    ${lib.optionalString hostPlatform.isDarwin ''
    nix_flags+=("-mmacosx-version-min=${hostPlatform.darwinMinVersion}")
    ''}
    
    if [[ "''${NIX_DEBUG_CMAKE:-}" == "1" ]]; then
      echo "NIX CMAKE COMPILER LAUNCHER: $compiler ''${nix_flags[@]} $@" >&2
    fi
    
    exec "$compiler" "''${nix_flags[@]}" "$@"
  '';

  cLinkerLauncher = writeShellScript "nix-ld-c-launcher" ''
    set -euo pipefail
    compiler="$1" 
    shift
    
    nix_flags=()
    
    ${lib.concatMapStringsSep "\n" (path: ''
      nix_flags+=("-L${path}")
    '') nixLibraryPaths}
    
    ${lib.concatMapStringsSep "\n" (path: ''
      nix_flags+=("-Wl,-rpath,${path}")
    '') nixLibraryPaths}
    
    ${lib.concatStringsSep "\n" (map (flag: ''
      nix_flags+=("${flag}")
    '') (platformFlags.commonLinkerFlags or []))}
    
    if [[ "''${NIX_DEBUG_CMAKE:-}" == "1" ]]; then
      echo "NIX CMAKE LINKER LAUNCHER: $compiler ''${nix_flags[@]} $@" >&2
    fi
    
    exec "$compiler" "''${nix_flags[@]}" "$@"
  '';

  cxxLinkerLauncher = writeShellScript "nix-ld-cxx-launcher" ''
    set -euo pipefail
    compiler="$1"
    shift
    
    nix_flags=()
    
    ${lib.concatMapStringsSep "\n" (path: ''
      nix_flags+=("-L${path}")
    '') nixLibraryPaths}
    
    ${lib.concatMapStringsSep "\n" (path: ''
      nix_flags+=("-Wl,-rpath,${path}")
    '') nixLibraryPaths}
    
    ${lib.concatStringsSep "\n" (map (flag: ''
      nix_flags+=("${flag}")
    '') (platformFlags.commonLinkerFlags or []))}
    
    if [[ "''${NIX_DEBUG_CMAKE:-}" == "1" ]]; then
      echo "NIX CMAKE LINKER LAUNCHER: $compiler ''${nix_flags[@]} $@" >&2
    fi
    
    exec "$compiler" "''${nix_flags[@]}" "$@"
  '';
}
