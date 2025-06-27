# Comparison to Other Ecosystems

`nix-cmake` aims to provide a declarative, `*2nix`-style solution for CMake projects, making them as easy to package in Nix as Python projects with `uv2nix` or Rust projects with `crane`.

| Ecosystem | Tool | Nix Integration | CMake Equivalent |
|-----------|------|-----------------|------------------|
| Python | uv2nix | ✅ Excellent | **nix-cmake** |
| Python | poetry2nix | ✅ Excellent | **nix-cmake** |
| Rust | crane | ✅ Excellent | **nix-cmake** |
| Haskell | haskell-flake | ✅ Excellent | **nix-cmake** |
| JavaScript | node2nix | ✅ Good | **nix-cmake** |
| CMake | ❌ Manual packaging | ⚠️ Ad-hoc | **nix-cmake** |

## Real-World Example: stdexec

stdexec is a complex C++ project that uses RAPIDS CMake, which traditionally requires significant boilerplate to package in Nix.

### The Challenge
`stdexec` downloads several dependencies at configure time:
1. `rapids-cmake` itself (via FetchContent)
2. CPM.cmake (via download)
3. ICM library (via CPMAddPackage)
4. Catch2 (via CPMAddPackage, if tests enabled)
5. `execution.bs` file (for version info)

### Traditional Manual Approach (~56 lines of boilerplate)
```nix
let
  rapids-cmake = fetchFromGitHub { ... };
  icm-src = fetchFromGitHub { ... };
  cpm-cmake = fetchurl { ... };
  execution-bs = fetchurl { ... };
in stdenv.mkDerivation {
  preConfigure = ''
    export CPM_SOURCE_CACHE=$TMPDIR/cpm-cache
    mkdir -p $CPM_SOURCE_CACHE/cpm
    mkdir -p $CPM_SOURCE_CACHE/icm
    cp ${cpm-cmake} $CPM_SOURCE_CACHE/cpm/CPM_0.38.5.cmake
    ln -s ${icm-src} $CPM_SOURCE_CACHE/icm/<hash>
  '';

  postPatch = ''
    sed -i '/download RAPIDS/d' CMakeLists.txt
    substituteInPlace CMakeLists.txt ...
  '';
}
```

### The `nix-cmake` Approach (~12 lines)
```nix
nix-cmake.builders.buildCMakePackage {
  pname = "stdexec";
  src = ./.;
  
  # Automatically discovered and satisfied by the dependency provider
  lockFile = ./cmake-lock.json;

  rapids.version = "24.02";  # Can be handled automatically
}
```
