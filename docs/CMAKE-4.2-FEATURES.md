# CMake 4.2 Features Relevant to nix-cmake

## Overview

nix-cmake now uses **CMake 4.2.1**, which brings several features that are valuable for our dependency management and CPS integration goals.

## Key Features for nix-cmake

### 1. Enhanced File-Based API (codemodel v2.9)

**What changed:**
- File API codemodel version updated to 2.9
- **Imported targets now included** in codemodel responses
- All interface library targets included (not just build participants)
- New fields: `imported`, `local`, `abstract`, `codemodelVersion`
- New dependency tracking: `linkLibraries`, `interfaceLinkLibraries`, `compileDependencies`, etc.

**Why this matters for nix-cmake:**

This is **huge** for our dependency analysis and lock file generation!

```nix
# We can now introspect imported targets from the file API
cmake2nix.lib.analyzeDependencies = { buildDir }: let
  codemodel = builtins.fromJSON (
    builtins.readFile "${buildDir}/.cmake/api/v1/reply/codemodel-v2.9.json"
  );
in {
  # Extract ALL dependencies, including imported ones
  importedTargets = lib.filter (t: t.imported) codemodel.configurations.0.targets;

  # Get transitive link dependencies
  linkGraph = lib.map (t: {
    name = t.name;
    links = t.linkLibraries;
    interfaceLinks = t.interfaceLinkLibraries;
  }) codemodel.configurations.0.targets;
};
```

**Use cases:**
1. **Lock file generation** - Parse project after configure, extract all FetchContent/CPM deps
2. **Dependency graph visualization** - Build complete dep graphs including transitive deps
3. **CPS generation** - Convert CMake targets to CPS format automatically
4. **Validation** - Verify our dependency provider hooked all expected deps

### 2. Link Dependency Tracking

**New target object fields:**
- `linkLibraries` - Direct link dependencies
- `interfaceLinkLibraries` - Interface (header-only) dependencies
- `compileDependencies` - Compile-time dependencies
- `interfaceCompileDependencies` - Interface compile dependencies
- `objectDependencies` - Object file dependencies
- `orderDependencies` - Build ordering dependencies

**Why this matters:**

Perfect for **transitive dependency resolution** in CPS integration:

```json
// Generated CPS file can now include accurate dependency info
{
  "name": "mylib",
  "components": {
    "mylib": {
      "type": "dylib",
      "requires": ["fmt", "spdlog"],  // from linkLibraries
      "compile_requires": ["boost"]    // from compileDependencies
    }
  }
}
```

### 3. Cross-Compilation for Emscripten

**What changed:**
- Simple toolchain file support for Emscripten
- Aligns with our toolchain hook patterns

**Why this matters:**

Shows CMake is moving toward **simpler, declarative toolchain files** - validates our cmakeToolchainHook approach.

### 4. cmake_language(TRACE) Command

**What changed:**
```cmake
cmake_language(TRACE ENABLE)  # Enable tracing
# ... code to trace ...
cmake_language(TRACE DISABLE) # Disable tracing
```

**Why this matters:**

Could be useful for **debugging our dependency provider hook**:

```cmake
# In cmakeBuildHook.cmake
if(DEFINED ENV{NIX_CMAKE_DEBUG})
  cmake_language(TRACE ENABLE)
endif()

macro(nix_dependency_provider method)
  # ... our hook logic ...
endmacro()

cmake_language(SET_DEPENDENCY_PROVIDER nix_dependency_provider ...)
```

### 5. Improved Find Module Version Variables

**What changed:**
- All find modules now provide `<PackageName>_VERSION` (consistent casing)
- Deprecates variants like `<PACKAGENAME>_VERSION` and `<PackageName>_VERSION_STRING`

**Why this matters:**

**Standardization** for our parsers and CPS generation:

```nix
# Parse find_package results consistently
cmake2nix.lib.extractFoundPackages = { buildDir }:
  # All packages now have consistent Foo_VERSION format
  # No more guessing FooBar_VERSION vs FOOBAR_VERSION vs FooBar_VERSION_STRING
```

### 6. Target File Base Name Generator Expressions

**New in 4.2:**
```cmake
$<TARGET_FILE_BASE_NAME:tgt POSTFIX>
$<TARGET_IMPORT_FILE_BASE_NAME:tgt POSTFIX>
# ... etc
```

**Why this matters:**

Helps with **multi-output package generation** and CPS file creation:

```nix
# Generate accurate CPS component locations
component.location = "@prefix@/lib/lib${baseNameWithPostfix}.so";
```

### 7. TARGET_INTERMEDIATE_DIR Generator Expression

**What changed:**
```cmake
$<TARGET_INTERMEDIATE_DIR:tgt>
# Refers to target's intermediate files directory
```

**Why this matters:**

Useful for **build introspection** and understanding CMake's internal build structure for advanced features.

## Features from CMake 4.0-4.1 We're Already Using

### CMAKE_EXPERIMENTAL_FIND_CPS_PACKAGES (4.0)

**The foundation for CPS integration!**

```cmake
set(CMAKE_EXPERIMENTAL_FIND_CPS_PACKAGES "e82e467b-f997-4464-8ace-b00808fff261")
find_package(fmt REQUIRED)  # Can now find .cps files!
```

Already documented in [CPS-INTEGRATION.md](./CPS-INTEGRATION.md).

### Dependency Provider API Improvements (4.0+)

The `cmake_language(SET_DEPENDENCY_PROVIDER)` we're using was stabilized across 4.0-4.2 releases with better error handling and edge case support.

### cmake_pkg_config() Command (4.1)

**New command for pkg-config integration:**

```cmake
cmake_pkg_config(IMPORT libfoo)  # Import pkg-config package
```

**Potential synergy with nix-cmake:**

We could generate **both CPS files and pkg-config .pc files** from our package metadata:

```nix
cmake2nix.lib.generatePackageMetadata = { name, version, ... }: {
  cps = generateCPS { inherit name version; };
  pkgconfig = generatePkgConfig { inherit name version; };
};
```

### CMAKE_LINK_WARNING_AS_ERROR (4.0)

Useful for our test suite - ensure no warnings in our generated builds.

## Roadmap Impact

### Immediate (Phase 1-2)

**File API enhancements enable:**
- Better testing of our hooks (validate all deps were intercepted)
- Dependency graph extraction for visualization
- Lock file generation without parsing CMakeLists.txt

### Medium Term (Phase 3-4)

**Link dependency tracking enables:**
- Accurate CPS file generation
- Transitive dependency resolution
- Better lock file format (include compile vs link deps)

### Long Term (Phase 7-8)

**CPS support (4.0+) + enhanced codemodel (4.2) enables:**
- Full CPS integration as primary dependency mechanism
- Automatic conversion: CMake targets → CPS files
- Tool-agnostic package metadata

## Migration Notes

### Policy Changes

CMake 4.0-4.2 introduced several new policies. Our hooks should set appropriate `cmake_minimum_required()` or `cmake_policy()` versions:

```cmake
# In cmakeBuildHook.cmake
cmake_minimum_required(VERSION 3.24...4.2)
# Ensures we get 4.2 behavior when available, but work with 3.24+
```

### Removed Features

- **Visual Studio 14 2015 and 15 2017 deprecated** (4.0)
  - Not relevant for Nix (we don't use VS generators)

- **Compatibility with CMake < 3.5 removed** (4.0)
  - Also not relevant - we already require 3.24+ for dependency providers

## Testing Strategy

### Test with File API

```nix
# Test: Validate our hooks intercepted all dependencies
cmake2nix.tests.validateInterception = stdenv.mkDerivation {
  # ... build with our hooks ...

  checkPhase = ''
    # Use CMake 4.2 file API to extract dependency info
    cmake -B build --graphviz=deps.dot

    # Parse codemodel v2.9
    codemodel="build/.cmake/api/v1/reply/codemodel-v2.json"

    # Verify all expected deps are marked as imported
    if ! jq '.configurations[0].targets[] | select(.imported) | .name' "$codemodel" | \
         grep -q "fmt"; then
      echo "ERROR: fmt not found in imported targets"
      exit 1
    fi
  '';
};
```

### Test CPS Generation

```nix
# Test: Generate CPS from CMake target
cmake2nix.tests.cpsGeneration = runCommand "test-cps-gen" {} ''
  # Configure CMake project
  cmake -S ${./test-project} -B build \
    -DCMAKE_EXPERIMENTAL_FIND_CPS_PACKAGES="e82e467b-f997-4464-8ace-b00808fff261"

  # Extract codemodel
  codemodel="build/.cmake/api/v1/reply/codemodel-v2.json"

  # Generate CPS from target info
  ${cmake2nix}/bin/cmake2nix generate-cps \
    --from-codemodel "$codemodel" \
    --target mylib \
    --output $out/mylib.cps

  # Validate CPS schema
  ${cps-validator}/bin/cps-validate $out/mylib.cps
'';
```

## Documentation Updates

### API.md Updates

Add new functions leveraging CMake 4.2:

```nix
cmake2nix.lib.introspection = {
  # Extract dependency graph from file API v2.9
  extractDependencyGraph = { buildDir }: ...;

  # Generate CPS from CMake codemodel
  codemodelToCPS = { codemodel, target }: ...;

  # Validate our hooks intercepted all deps
  validateInterception = { buildDir, expectedDeps }: ...;
};
```

### ROADMAP.md Updates

Update Phase 3 (Parsing) to note we can now use file API instead of parsing CMakeLists.txt:

**Alternative approach:**
1. Configure project with CMake (let it fail if deps missing)
2. Parse file API codemodel v2.9
3. Extract all imported targets
4. Generate lock file from that

**Pros:**
- No CMake language parser needed!
- Guaranteed accuracy (CMake did the parsing)
- Includes transitive deps

**Cons:**
- Requires partial build (even if it fails)
- Can't generate lock file without CMake

## Conclusion

CMake 4.2 gives us **exactly** the tools we need to build a robust, standards-based dependency manager:

1. ✅ **File API v2.9** - Introspect all dependencies including imported targets
2. ✅ **Link dependency tracking** - Build accurate transitive dependency graphs
3. ✅ **CPS support** - Foundation for tool-agnostic package metadata
4. ✅ **Improved standardization** - Consistent APIs across find modules

This validates our design direction and gives us multiple implementation paths forward. We can choose between:

- **Path A:** Parse CMakeLists.txt → generate lock file (more upfront work)
- **Path B:** Configure → parse file API → generate lock file (simpler, leverages CMake 4.2)
- **Path C:** Hybrid - parse for discovery, file API for validation

Recommendation: **Path B or C** - leverage CMake 4.2's excellent introspection capabilities.

## References

- [CMake 4.2 Release Notes](https://cmake.org/cmake/help/v4.2/release/4.2.html)
- [CMake 4.1 Release Notes](https://cmake.org/cmake/help/v4.1/release/4.1.html)
- [CMake 4.0 Release Notes](https://cmake.org/cmake/help/v4.0/release/4.0.html)
- [File API v1 Documentation](https://cmake.org/cmake/help/latest/manual/cmake-file-api.7.html)
- [CPS Specification](https://cps-org.github.io/cps/)
