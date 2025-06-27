# pkg-config Integration via cmake_pkg_config

## Overview

CMake 3.31+ introduced native pkg-config support via `cmake_pkg_config()`, and CMake 4.1+ enhanced it with `IMPORT` and `POPULATE` commands. This provides a **patch-free** way to integrate pkg-config-based dependencies into nix-cmake.

## Why cmake_pkg_config?

**Traditional approach (nixpkgs):**
```nix
# Requires pkg-config tool as dependency
nativeBuildInputs = [ pkg-config ];

# CMake invokes external pkg-config binary
find_package(PkgConfig REQUIRED)
pkg_check_modules(fmt REQUIRED IMPORTED_TARGET fmt)
target_link_libraries(myapp PkgConfig::fmt)
```

**cmake_pkg_config approach:**
```cmake
# No external tool needed - CMake parses .pc files natively
cmake_pkg_config(IMPORT fmt REQUIRED
  ENV_MODE IGNORE
  PC_LIBDIR "/nix/store/.../lib/pkgconfig"
)
target_link_libraries(myapp PkgConfig::fmt)
```

**Benefits:**
- ✅ No pkg-config tool dependency
- ✅ Reproducible (ENV_MODE IGNORE)
- ✅ Cross-compilation friendly (PC_SYSROOT_DIR)
- ✅ Native CMake targets
- ✅ Aligns with pure toolchain philosophy

## Architecture

### Three-Format Strategy

nix-cmake supports **three** dependency resolution formats:

1. **FetchContent** (CMake 3.11+) - Source dependencies via git/url
2. **pkg-config** (CMake 3.31+) - Binary packages with .pc files
3. **CPS** (CMake 4.0+) - Modern tool-agnostic standard

Choice depends on CMake version and package availability.

### Format Selection Logic

```cmake
macro(nix_dependency_provider method dep_type)
  if("${method}" STREQUAL "FIND_PACKAGE")
    set(pkg "${ARGN_FIND_PACKAGE_PACKAGE_NAME}")

    # Priority 1: Explicit override from lock file
    if(DEFINED ENV{NIX_${pkg}_METHOD})
      if("$ENV{NIX_${pkg}_METHOD}" STREQUAL "cps")
        # Use CPS (CMake 4.0+)
        find_package(${pkg} CONFIG)
      elseif("$ENV{NIX_${pkg}_METHOD}" STREQUAL "pkgconfig")
        # Use pkg-config (CMake 3.31+)
        nix_import_pkgconfig(${pkg})
      endif()
    # Priority 2: Auto-detect format
    elseif(DEFINED ENV{NIX_PKGCONFIG_${pkg}_PATH})
      nix_import_pkgconfig(${pkg})
    elseif(DEFINED ENV{NIX_CPS_${pkg}_PATH})
      nix_import_cps(${pkg})
    elseif(DEFINED ENV{NIX_FETCHCONTENT_${pkg}_SOURCE_DIR})
      nix_import_fetchcontent(${pkg})
    endif()
  endif()
endmacro()
```

## Generating pkg-config Files

### From Nix Packages

```nix
# lib/pkgconfig.nix
cmake2nix.lib.generatePkgConfig = {
  pkg,
  name ? pkg.pname,
  version ? pkg.version,
  description ? pkg.meta.description or "",
  libs ? [],
  cflags ? [],
  requires ? [],
  requiresPrivate ? [],
}: writeTextFile {
  name = "${name}.pc";
  destination = "/lib/pkgconfig/${name}.pc";

  text = ''
    prefix=${pkg}
    exec_prefix=''${prefix}
    libdir=''${exec_prefix}/lib
    includedir=''${prefix}/include

    Name: ${name}
    Description: ${description}
    Version: ${version}
    ${lib.optionalString (requires != [])
      "Requires: ${lib.concatStringsSep ", " requires}"}
    ${lib.optionalString (requiresPrivate != [])
      "Requires.private: ${lib.concatStringsSep ", " requiresPrivate}"}
    Libs: -L''${libdir} ${lib.concatMapStringsSep " " (l: "-l${l}") libs}
    Cflags: -I''${includedir} ${lib.concatStringsSep " " cflags}
  '';
};
```

### Usage Example

```nix
# Generate .pc file for fmt
fmt-pkgconfig = cmake2nix.lib.generatePkgConfig {
  pkg = fmt;
  libs = [ "fmt" ];
};

# Use in build
stdenv.mkDerivation {
  nativeBuildInputs = [ cmake ];

  # Point CMake to our generated .pc file
  NIX_PKGCONFIG_fmt_PATH = "${fmt-pkgconfig}/lib/pkgconfig/fmt.pc";
}
```

## Dependency Provider Integration

### Enhanced cmakeBuildHook.cmake

```cmake
# Helper to import pkg-config packages
function(nix_import_pkgconfig pkg)
  if(NOT DEFINED ENV{NIX_PKGCONFIG_${pkg}_PATH})
    return()
  endif()

  set(pc_path "$ENV{NIX_PKGCONFIG_${pkg}_PATH}")

  # Use cmake_pkg_config to import
  cmake_pkg_config(IMPORT "${pc_path}"
    QUIET
    NAME ${pkg}
    ENV_MODE IGNORE  # Reproducible - ignore PKG_CONFIG_* env vars
    PC_SYSROOT_DIR "$ENV{NIX_CMAKE_SYSROOT}"  # Cross-compilation
  )

  if(PKGCONFIG_${pkg}_FOUND)
    # Create find_package-compatible alias
    if(NOT TARGET ${pkg}::${pkg})
      add_library(${pkg}::${pkg} ALIAS PkgConfig::${pkg})
    endif()

    set(${pkg}_FOUND TRUE PARENT_SCOPE)
    message(STATUS "Found ${pkg} via pkg-config: ${pc_path}")
  endif()
endfunction()

# Main dependency provider
macro(nix_dependency_provider method dep_type)
  if("${method}" STREQUAL "FIND_PACKAGE")
    set(pkg "${ARGN_FIND_PACKAGE_PACKAGE_NAME}")

    # Try pkg-config import
    nix_import_pkgconfig(${pkg})
    if(${pkg}_FOUND)
      set(${pkg}_FOUND TRUE PARENT_SCOPE)
      return()
    endif()

    # Fall back to other methods (CPS, FetchContent)...
  endif()
endmacro()
```

## Lock File Format

### Multi-Format Support

```nix
# cmake-lock.nix
{
  version = "1.0";

  dependencies = {
    # pkg-config format
    fmt = {
      method = "pkgconfig";
      package = "fmt";
      version = "10.2.1";
      # Could be:
      # - path to .pc file
      # - package name (search PKG_CONFIG_PATH)
      pcFile = "${fmt-pkgconfig}/lib/pkgconfig/fmt.pc";
    };

    # CPS format (CMake 4.0+)
    spdlog = {
      method = "cps";
      package = "spdlog";
      version = "1.13.0";
      cpsFile = "${spdlog-cps}/lib/cps/spdlog.cps";
    };

    # FetchContent (any CMake version)
    Catch2 = {
      method = "fetchcontent";
      url = "https://github.com/catchorg/Catch2";
      rev = "v3.5.2";
      hash = "sha256-...";
    };
  };
}
```

### Applying Lock File

```nix
# lib/lock-file.nix
cmake2nix.lib.applyLockFile = { lockFile }:
  let
    lock = import lockFile;

    # Generate environment variables for each dependency
    envVars = lib.mapAttrs' (name: dep:
      if dep.method == "pkgconfig" then
        lib.nameValuePair "NIX_PKGCONFIG_${name}_PATH" dep.pcFile
      else if dep.method == "cps" then
        lib.nameValuePair "NIX_CPS_${name}_PATH" dep.cpsFile
      else if dep.method == "fetchcontent" then
        lib.nameValuePair "NIX_FETCHCONTENT_${name}_SOURCE_DIR"
          (fetchFromGitHub dep)
      else
        throw "Unknown method: ${dep.method}"
    ) lock.dependencies;

  in {
    inherit envVars;

    # Apply to derivation
    applyToDerivation = drv: drv.overrideAttrs (old: {
      # Inject environment variables
      passthru = (old.passthru or {}) // envVars;

      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        cmake
        cmakeDependencyHook
      ];
    });
  };
```

## CMake Version Compatibility

| Feature | CMake Version | Status |
|---------|--------------|--------|
| FetchContent | 3.11+ | ✅ Widely supported |
| Dependency Provider | 3.24+ | ✅ Our baseline |
| cmake_pkg_config EXTRACT | 3.31+ | ✅ Available |
| cmake_pkg_config IMPORT/POPULATE | 4.1+ | ✅ We use 4.2 |
| CPS experimental | 4.0+ | ⚠️ Experimental flag required |

**Recommendation:** Use pkg-config as primary format for CMake 3.31-4.x, transition to CPS when it's stable.

## Advantages Over CPS (Short Term)

### Why pkg-config now, CPS later?

**pkg-config advantages:**
1. **Mature ecosystem** - Most packages already have .pc files
2. **Easier generation** - Simpler format than CPS
3. **Stable API** - No experimental flags needed (as of CMake 4.1)
4. **Bidirectional** - Can consume system .pc files when needed
5. **Gradual migration** - Can mix with FetchContent

**CPS advantages (long-term):**
1. **Tool-agnostic** - Works with Meson, Bazel, etc.
2. **Rich metadata** - Components, configurations, features
3. **Transitive deps** - Better dependency graph modeling
4. **Modern design** - JSON-based, extensible

**Strategy:** Support **both** via lock file `method` field, let users choose.

## Integration with High-Level API

### Workspace Loading

```nix
# User's flake.nix
{
  outputs = { cmake2nix, ... }: {
    packages.default = cmake2nix.lib.buildCMakeApplication {
      src = ./.;
      lockFile = ./cmake-lock.nix;

      # Optional: force pkg-config for specific deps
      dependencyMethods = {
        fmt = "pkgconfig";
        spdlog = "cps";
        Catch2 = "fetchcontent";
      };
    };
  };
}
```

### Lock File Generation

```bash
# Scan project, generate lock file with pkg-config where possible
$ cmake2nix lock --prefer-pkgconfig

# Generate lock file with CPS where possible
$ cmake2nix lock --prefer-cps

# Mixed strategy (default)
$ cmake2nix lock
```

## Testing Strategy

### Test pkg-config Integration

```nix
cmake2nix.tests.pkgconfig-integration = stdenv.mkDerivation {
  name = "test-pkgconfig";
  src = writeTextFile {
    name = "CMakeLists.txt";
    text = ''
      cmake_minimum_required(VERSION 4.1)
      project(test)

      find_package(fmt REQUIRED)

      add_executable(test test.cpp)
      target_link_libraries(test fmt::fmt)
    '';
  };

  nativeBuildInputs = [ cmake cmakeDependencyHook ];

  # Use pkg-config for fmt
  NIX_PKGCONFIG_fmt_PATH = "${fmt-pkgconfig}/lib/pkgconfig/fmt.pc";

  doCheck = true;
  checkPhase = ''
    ./test
  '';
};
```

## Migration Path

### Phase 1: pkg-config Support (Immediate)
- Generate .pc files for common packages
- Update dependency provider to support cmake_pkg_config
- Test with CMake 4.2

### Phase 2: Dual Format (Near-term)
- Support both .pc and .cps in lock file
- Let users choose via `method` field
- Document trade-offs

### Phase 3: CPS Primary (When Stable)
- Make CPS default for CMake 4.x+
- Keep pkg-config for compatibility
- Full tool-agnostic integration

## Conclusion

`cmake_pkg_config` provides a **patch-free, reproducible** way to integrate pkg-config-based dependencies. It complements our CPS strategy and provides immediate value for CMake 3.31+ users.

**Key Benefits:**
- No external pkg-config tool needed
- Reproducible (ENV_MODE IGNORE)
- Cross-compilation friendly
- Native CMake integration
- Bridges gap until CPS is stable

This is the right foundation alongside FetchContent and CPS for a comprehensive dependency management solution.
