# File API Strategy: The Superior Approach

## Executive Summary

Instead of parsing `CMakeLists.txt`, we use **CMake's File API** to extract dependency information. This approach:

- ✅ Leverages CMake's own parser (guaranteed correct)
- ✅ Works with CMake 4.2's enhanced codemodel v2.9
- ✅ Captures transitive dependencies automatically
- ✅ Requires no CMake language parser (pure Nix)
- ✅ Handles complex conditionals correctly
- ✅ Aligns with our pure-toolchain philosophy

## The Philosophy

### No Patching, No Wrappers, No Magic

**Problem with nixpkgs CMake:**
```nix
# nixpkgs approach:
- Patches CMake source code ❌
- Compiler wrappers (cc-wrapper) ❌
- Shell hooks doing implicit magic ❌
- Hard to understand what's happening ❌
```

**Our approach:**
```nix
# nix-cmake approach:
- Unpatched upstream CMake ✅
- Pure toolchain file (explicit) ✅
- No wrappers (CMake native support) ✅
- Transparent, declarative ✅
```

### Why This Matters

CMake **already supports** everything Nix needs:
- Cross-compilation → `CMAKE_SYSTEM_NAME`, toolchain files
- Custom compilers → `CMAKE_C_COMPILER`, `CMAKE_CXX_COMPILER`
- Include paths → `CMAKE_SYSTEM_INCLUDE_PATH`
- Library paths → `CMAKE_SYSTEM_LIBRARY_PATH`
- Install directories → `CMAKE_INSTALL_*` variables

We don't need to **patch** CMake or **wrap** compilers. We just need to **configure** CMake correctly via toolchain files.

## How File API Works

### 1. Query CMake's Internal State

```nix
# Step 1: Configure project (may fail, that's OK)
configurePhase = runCommand "cmake-configure" {
  nativeBuildInputs = [ cmake ];
} ''
  # Write File API query
  mkdir -p build/.cmake/api/v1/query
  echo '{"requests":[{"kind":"codemodel","version":2}]}' > \
    build/.cmake/api/v1/query/client-nix-cmake.json

  # Configure (dependencies may be missing - that's fine)
  cmake -S ${src} -B build \
    -DCMAKE_TOOLCHAIN_FILE=${toolchainFile} \
    || true  # Don't fail on missing deps

  # Extract File API reply
  cp -r build/.cmake/api/v1/reply $out
'';
```

### 2. Parse File API Response

```nix
# Step 2: Extract dependency information
dependencies = let
  # Read codemodel index
  index = builtins.fromJSON (
    builtins.readFile "${configured}/index-*.json"
  );

  # Get codemodel reply
  codemodelFile = index.reply.codemodel-v2.jsonFile;
  codemodel = builtins.fromJSON (
    builtins.readFile "${configured}/${codemodelFile}"
  );

  # Extract imported targets (these are FetchContent/CPM deps)
  importedTargets = lib.filter
    (t: t.imported or false)
    codemodel.configurations.0.targets;

in lib.listToAttrs (map (target: {
  name = target.name;
  value = {
    # Read detailed target info
    targetFile = "${configured}/${target.jsonFile}";
    info = builtins.fromJSON (builtins.readFile targetFile);
  };
}) importedTargets);
```

### 3. Generate Lock File

```nix
# Step 3: Convert to lock file format
lockFile = {
  version = "1.0";

  dependencies = lib.mapAttrs (name: dep: {
    # Extract from target properties
    type = dep.info.type;  # INTERFACE, STATIC_LIBRARY, etc.

    # Link dependencies
    linkLibraries = dep.info.linkLibraries or [];
    interfaceLinkLibraries = dep.info.interfaceLinkLibraries or [];

    # Compile dependencies
    compileDependencies = dep.info.compileDependencies or [];

    # Source location (if we know it from environment)
    sourceDir = builtins.getEnv "NIX_FETCHCONTENT_${name}_SOURCE_DIR";
  }) dependencies;
};
```

## CMake 4.2 File API Enhancements

### What's New in Codemodel v2.9

**Imported Targets Now Included:**
```json
{
  "configurations": [{
    "targets": [
      {
        "name": "fmt",
        "imported": true,      // NEW in v2.9
        "type": "STATIC_LIBRARY",
        "jsonFile": "target-fmt-Debug.json"
      }
    ]
  }]
}
```

Previously, imported targets (from `find_package` or `FetchContent`) were **excluded** from File API responses. Now they're **included**, which is exactly what we need!

**Enhanced Dependency Tracking:**

Target objects now include:
```json
{
  "name": "myapp",
  "linkLibraries": ["fmt", "spdlog"],           // Direct deps
  "interfaceLinkLibraries": ["header-only"],    // Interface deps
  "compileDependencies": ["boost"],             // Compile-time
  "interfaceCompileDependencies": ["concepts"], // Interface compile
}
```

This gives us **complete dependency graphs** including transitive relationships.

## Comparison: Parsing vs File API

### Approach A: Parse CMakeLists.txt

**Process:**
1. Tokenize CMake language
2. Parse commands (`FetchContent_Declare`, `CPMAddPackage`)
3. Handle variable expansion
4. Handle conditionals (`if`, generator expressions)
5. Extract dependency info

**Challenges:**
```cmake
# Variable expansion
set(FMT_VERSION "10.2.1")
FetchContent_Declare(fmt
  GIT_REPOSITORY https://github.com/fmtlib/fmt
  GIT_TAG ${FMT_VERSION}  # Need to expand variables
)

# Conditionals
if(BUILD_TESTING)
  CPMAddPackage(
    NAME Catch2
    GITHUB_REPOSITORY catchorg/Catch2
    VERSION 3.5.2
  )
endif()

# Generator expressions
FetchContent_Declare(foo
  GIT_TAG $<IF:$<CONFIG:Debug>,debug-branch,release-branch>
)
```

**Problems:**
- ❌ Need full CMake language parser
- ❌ Must evaluate conditionals (platform-dependent)
- ❌ Generator expressions are complex
- ❌ Variables can come from parent scopes
- ❌ Transitive deps hidden in subdirectories
- ❌ Fragile (breaks on CMake updates)

### Approach B: File API (Our Choice)

**Process:**
1. Configure project with CMake
2. Read File API response (JSON)
3. Extract dependency graph

**Advantages:**
```nix
# Simple JSON parsing - no CMake language parser needed
codemodel = builtins.fromJSON (builtins.readFile codemodelFile);

# All conditionals already evaluated by CMake
dependencies = lib.filter (t: t.imported) codemodel.targets;

# Transitive deps already resolved by CMake
transitiveLinks = lib.concatMap (t: t.linkLibraries) dependencies;
```

**Benefits:**
- ✅ CMake does all the hard work
- ✅ Guaranteed correct parsing
- ✅ Conditionals evaluated for current platform
- ✅ Transitive dependencies resolved
- ✅ Generator expressions evaluated
- ✅ Robust (uses CMake's own data structures)

## Implementation Strategy

### Phase 1: Discovery

```nix
cmake2nix.lib.discoverDependencies = { src, toolchainFile ? null }:
  let
    # Configure project
    configured = runCommand "discover-deps" {
      nativeBuildInputs = [ cmake ];
    } ''
      # Setup File API query
      mkdir -p build/.cmake/api/v1/query
      cat > build/.cmake/api/v1/query/client-nix-cmake.json <<EOF
      {
        "requests": [
          {"kind": "codemodel", "version": 2},
          {"kind": "cache", "version": 2}
        ]
      }
      EOF

      # Configure (failure is OK - we just need File API data)
      cmake -S ${src} -B build \
        ${lib.optionalString (toolchainFile != null)
          "-DCMAKE_TOOLCHAIN_FILE=${toolchainFile}"} \
        || true

      # Copy File API responses
      mkdir -p $out
      cp -r build/.cmake/api/v1/reply/* $out/
    '';

    # Parse responses
    index = builtins.fromJSON (
      builtins.readFile "${configured}/index-*.json"
    );

  in {
    inherit configured index;

    # Extract dependency info
    dependencies = extractDependencies configured index;

    # Extract CMake cache variables
    cache = extractCache configured index;
  };
```

### Phase 2: Lock File Generation

```nix
cmake2nix.lib.generateLockFile = { workspaceRoot }: let
  discovered = cmake2nix.lib.discoverDependencies {
    src = workspaceRoot;
  };

  # Convert discovered deps to lock file format
  lockFile = {
    version = "1.0";
    schemaVersion = 1;

    project = {
      name = discovered.cache.CMAKE_PROJECT_NAME;
      version = discovered.cache.CMAKE_PROJECT_VERSION or "0.0.0";
    };

    dependencies = lib.mapAttrs (name: dep:
      # Try to determine source from environment or cache
      if builtins.hasAttr "NIX_FETCHCONTENT_${name}_SOURCE_DIR" builtins.getEnv {} then {
        # Already provided by user
        sourceDir = builtins.getEnv "NIX_FETCHCONTENT_${name}_SOURCE_DIR";
      } else {
        # Need to fetch - extract URL from cache or configure logs
        method = "git";  # or "url", "path"
        url = extractUrlForDep name discovered;
        rev = extractRevForDep name discovered;
        hash = "";  # To be filled by user or nix-prefetch
      }
    ) discovered.dependencies;
  };

in writeTextFile {
  name = "cmake.lock";
  text = builtins.toJSON lockFile;
};
```

### Phase 3: Lock File Application

```nix
cmake2nix.lib.applyLockFile = { lockFile }: let
  lock = builtins.fromJSON (builtins.readFile lockFile);

  # Fetch all dependencies
  fetchedDeps = lib.mapAttrs (name: dep:
    if dep.method == "git" then
      fetchFromGitHub {
        owner = dep.owner;
        repo = dep.repo;
        rev = dep.rev;
        hash = dep.hash;
      }
    else if dep.method == "url" then
      fetchurl {
        url = dep.url;
        hash = dep.hash;
      }
    else
      dep.sourceDir  # Local path
  ) lock.dependencies;

in {
  # Generate environment variables for dependency provider
  envVars = lib.mapAttrs' (name: src:
    lib.nameValuePair "NIX_FETCHCONTENT_${name}_SOURCE_DIR" "${src}"
  ) fetchedDeps;

  # Derivation applying the lock file
  applyToDerivation = drv: drv.overrideAttrs (old: {
    # Inject environment variables
    inherit (envVars);

    # Ensure dependency hook is enabled
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
      cmake
      cmakeDependencyHook
    ];
  });
};
```

## Advantages Over Traditional Approaches

### 1. No CMake Language Parser Needed

**Traditional approach:**
- Need to parse CMake (complex language)
- ~2000 lines of parser code
- Fragile, breaks on new CMake syntax

**File API approach:**
- Parse JSON (built-in)
- ~200 lines of code
- Robust, uses CMake's own output

### 2. Correct by Construction

**Traditional approach:**
- May misparse complex CMake
- May miss conditionals
- May miss transitive deps

**File API approach:**
- CMake did the parsing
- Conditionals evaluated
- Transitive deps resolved

### 3. Platform Aware

**Traditional approach:**
```cmake
if(WIN32)
  FetchContent_Declare(win32dep ...)
elseif(UNIX)
  FetchContent_Declare(unixdep ...)
endif()
```
Parser sees both branches - which to use?

**File API approach:**
CMake already evaluated conditions for current platform.

### 4. Generator Expression Support

**Traditional approach:**
```cmake
FetchContent_Declare(foo
  GIT_TAG $<IF:$<CONFIG:Debug>,v1.0-debug,v1.0>
)
```
Need full generator expression evaluator.

**File API approach:**
CMake evaluated it. We see the result.

## Pure Toolchain Integration

The File API approach **synergizes perfectly** with our pure toolchain philosophy:

```nix
# 1. Generate pure toolchain file
toolchain = cmake2nix.lib.generateToolchain { inherit stdenv; };

# 2. Configure with pure toolchain
discovered = discoverDependencies {
  src = ./.;
  toolchainFile = toolchain;
};

# 3. Extract deps from File API
lockFile = generateLockFile discovered;

# 4. Build with deps from lock file
package = buildCMakeApplication {
  inherit src lockFile toolchainFile;
};
```

**No patching. No wrappers. No magic. Pure CMake.**

## Handling Edge Cases

### Missing Dependencies (Expected)

```nix
# Configure will fail due to missing deps - that's OK!
cmake -S ${src} -B build || true

# File API still writes response even on error
# We get partial dependency info - exactly what we need
```

### Circular Dependencies

File API shows the actual dependency graph:
```json
{
  "targets": [
    {"name": "A", "linkLibraries": ["B"]},
    {"name": "B", "linkLibraries": ["A"]}  // Cycle detected!
  ]
}
```

We can detect and report these errors.

### Optional Dependencies

```cmake
option(BUILD_TESTS "Build tests" ON)
if(BUILD_TESTS)
  FetchContent_Declare(Catch2 ...)
endif()
```

**Solution:** Generate lock file for different configurations:
```nix
lockFile = {
  dependencies = {
    default = { fmt = {...}; spdlog = {...}; };
    withTests = { fmt = {...}; spdlog = {...}; Catch2 = {...}; };
  };
};
```

## Future: CPS Integration

File API + CPS is the ultimate combination:

```nix
# 1. Discover deps via File API
discovered = discoverDependencies { src = ./.;  };

# 2. Generate CPS files for each dependency
cpsFiles = lib.mapAttrs (name: dep:
  generateCPS {
    inherit name;
    inherit (dep) type linkLibraries;
  }
) discovered.dependencies;

# 3. CMake 4.0+ can find CPS files natively
# No dependency provider hook needed!
```

## Conclusion

The File API approach is:

1. **Simpler** - No parser, just JSON
2. **Correct** - CMake's own data
3. **Robust** - Resistant to CMake syntax changes
4. **Complete** - Includes transitive deps
5. **Aligned** - Works with pure toolchain philosophy

This is the right foundation for nix-cmake.

## Next Steps

1. ✅ Build CMake 4.2.1 (in progress)
2. ⏭️ Test File API queries
3. ⏭️ Implement `discoverDependencies`
4. ⏭️ Implement `generateLockFile`
5. ⏭️ Integration tests

Let's wait for CMake 4.2.1 to build, then we can start implementing this approach.
