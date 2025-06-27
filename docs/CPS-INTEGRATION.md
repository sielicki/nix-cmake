# CPS (Common Package Specification) Integration

## What is CPS?

The [Common Package Specification (CPS)](https://cps-org.github.io/cps/) is a **tool-agnostic, JSON-based standard** for describing C++ packages and their dependencies. It's designed to solve the same problems we're tackling with nix-cmake, but at a different layer of the stack.

### Key Concepts

- **JSON-based package metadata** - Machine-readable, language-agnostic
- **Transitive dependency resolution** - Automatically resolves nested dependencies
- **Tool-agnostic** - Works with any build system, not just CMake
- **CMake 4.0+ support** - Native `find_package()` integration via experimental flag

### Example CPS File

```json
{
  "cps_version": "0.12",
  "name": "fmt",
  "version": "10.2.1",
  "prefix": "/nix/store/...-fmt-10.2.1",
  "components": {
    "fmt": {
      "type": "dylib",
      "location": "@prefix@/lib/libfmt.so",
      "includes": ["@prefix@/include"],
      "compile_flags": ["-std=c++17"]
    }
  }
}
```

## Why CPS Matters for nix-cmake

CPS addresses fundamental problems in C++ dependency management:

### 1. **Transitive Dependencies** (The Big One)

**Traditional CMake problem:**
```cmake
# Consumer has to manually list ALL dependencies, even transitive ones
find_package(spdlog REQUIRED)   # spdlog depends on fmt
find_package(fmt REQUIRED)       # Manual transitive dep
target_link_libraries(myapp spdlog::spdlog fmt::fmt)  # Redundant
```

**With CPS:**
```cmake
set(CMAKE_EXPERIMENTAL_FIND_CPS_PACKAGES "e82e467b-f997-4464-8ace-b00808fff261")
find_package(spdlog REQUIRED)
target_link_libraries(myapp spdlog::spdlog)  # fmt resolved automatically!
```

### 2. **Tool Agnostic**

CPS isn't tied to CMake. This means:
- Meson, Bazel, vcpkg, Conan can all read CPS files
- **Nix can read CPS files directly**
- No need to reverse-engineer CMake scripts

### 3. **Declarative Package Metadata**

CPS is **pure data**, not code. This is huge for Nix:
- Easy to parse (just JSON)
- Easy to generate from Nix
- No CMake evaluation required
- Perfect for lock files!

## Strategic Opportunity

**CPS could be the "missing link" between Nix and CMake.**

Instead of:
```
Nix → CMake hooks → FetchContent/CPM interception → Build
```

We could have:
```
Nix → Generate CPS files → CMake 4.0 reads them → Build
```

### The Vision

```nix
# In nix-cmake
stdenv.mkDerivation {
  pname = "myapp";

  nativeBuildInputs = [ cmake ];
  buildInputs = [ fmt spdlog ];

  # nix-cmake automatically generates CPS files for all dependencies
  # CMake 4.0 discovers them via find_package()
  # No FetchContent, no CPM, no interception needed!
}
```

**Benefits:**
- ✅ Works with unmodified CMake projects
- ✅ No custom hooks needed (CMake 4.0 native support)
- ✅ Transitive dependencies "just work"
- ✅ Tool-agnostic (works with Meson, etc.)
- ✅ Simpler implementation

## How nix-cmake Should Integrate CPS

### Phase 1: CPS Generation (Immediate)

**Generate CPS files for Nix packages**

Every Nix package with CMake support gets a `.cps` file:

```nix
# In nixpkgs, or our overlay
fmt = stdenv.mkDerivation {
  # ... normal build ...

  postInstall = ''
    mkdir -p $out/share/cps
    cat > $out/share/cps/fmt.cps <<EOF
    {
      "cps_version": "0.12",
      "name": "fmt",
      "version": "${version}",
      "prefix": "$out",
      "components": {
        "fmt": {
          "type": "dylib",
          "location": "@prefix@/lib/libfmt.so",
          "includes": ["@prefix@/include"]
        }
      }
    }
    EOF
  '';
};
```

**Automatic CPS generation helper:**

```nix
cmake2nix.lib.generateCPS = {
  name,
  version,
  prefix,
  components
}: writeTextFile {
  name = "${name}.cps";
  text = builtins.toJSON {
    cps_version = "0.12";
    inherit name version prefix components;
  };
};
```

### Phase 2: CPS Discovery Hook

**cmakeCPSHook** - Set up CPS search paths

```nix
# cmake-cps-hook/default.nix
makeSetupHook {
  name = "cmake-cps-hook";
  substitutions = {
    # Enable CPS in CMake 4.0+
    cpsFlag = "-DCMAKE_EXPERIMENTAL_FIND_CPS_PACKAGES=e82e467b-f997-4464-8ace-b00808fff261";
  };
} ./cmake-cps-hook.sh
```

```bash
# cmake-cps-hook.sh
cmakeCPSSetupHook() {
  # Collect CPS files from all dependencies
  export CMAKE_CPS_PATH=""

  for dep in $buildInputs $nativeBuildInputs; do
    if [[ -d "$dep/share/cps" ]]; then
      export CMAKE_CPS_PATH="${CMAKE_CPS_PATH:+$CMAKE_CPS_PATH:}$dep/share/cps"
    fi
  done

  # Enable CPS support in CMake 4.0+
  cmakeFlags+=(
    "-DCMAKE_EXPERIMENTAL_FIND_CPS_PACKAGES=e82e467b-f997-4464-8ace-b00808fff261"
    "-DCMAKE_CPS_PATH=$CMAKE_CPS_PATH"
  )
}

addEnvHooks "$hostOffset" cmakeCPSSetupHook
```

### Phase 3: Lock File Integration

**CPS as our lock file format!**

Instead of inventing `cmake.lock`, we could use CPS:

```json
// cmake.deps.cps - Describes ALL dependencies
{
  "cps_version": "0.12",
  "name": "myapp-dependencies",
  "version": "1.0.0",
  "requires": {
    "fmt": {
      "version": "10.2.1",
      "cps_path": "/nix/store/...-fmt-10.2.1/share/cps/fmt.cps"
    },
    "spdlog": {
      "version": "1.13.0",
      "cps_path": "/nix/store/...-spdlog-1.13.0/share/cps/spdlog.cps",
      "requires": ["fmt"]  // Transitive deps explicit
    }
  }
}
```

**Benefits:**
- Standard format (not nix-cmake specific)
- Tool-agnostic (vcpkg, Conan could generate these too)
- Already has schema validation
- Transitive deps first-class

### Phase 4: Parser Integration

**Parse CMakeLists.txt → Generate CPS**

```nix
cmake2nix.lib.generateCPSFromCMake = { cmakeLists }: let
  parsed = cmake2nix.lib.parsers.parseCMakeLists cmakeLists;
in {
  cps_version = "0.12";
  name = parsed.project.name;
  version = parsed.project.version;

  # Convert FetchContent/CPM deps to CPS requires
  requires = lib.mapAttrs (name: dep: {
    version = dep.version or "*";
    # Generate CPS for each dependency
  }) parsed.dependencies;
};
```

## Comparison: Current Approach vs CPS Approach

### Current Approach (FetchContent Interception)

```nix
stdenv.mkDerivation {
  nativeBuildInputs = [ cmake cmakeDependencyHook ];

  # Manual env var for each dep
  NIX_FETCHCONTENT_fmt_SOURCE_DIR = pkgs.fmt;
  NIX_FETCHCONTENT_spdlog_SOURCE_DIR = pkgs.spdlog;

  # Hook intercepts FetchContent_MakeAvailable()
  # Provides Nix paths instead of downloading
}
```

**Pros:**
- ✅ Works with CMake 3.24+
- ✅ No CMakeLists.txt modifications

**Cons:**
- ❌ Nix-specific mechanism
- ❌ Requires custom hooks
- ❌ Doesn't solve transitive deps
- ❌ Doesn't help other build systems

### CPS Approach

```nix
stdenv.mkDerivation {
  nativeBuildInputs = [ cmake cmakeCPSHook ];
  buildInputs = [ pkgs.fmt pkgs.spdlog ];

  # That's it! CPS files auto-discovered and loaded
}
```

**Pros:**
- ✅ Standards-based (CPS spec)
- ✅ Works with CMake 4.0+ natively
- ✅ Solves transitive deps
- ✅ Tool-agnostic (helps entire ecosystem)
- ✅ Simpler implementation
- ✅ Better ecosystem alignment

**Cons:**
- ❌ Requires CMake 4.0+ (experimental feature)
- ❌ Not yet widely adopted
- ❌ Need to generate CPS for nixpkgs packages

## Migration Strategy

### Timeline

#### 2025: Foundation (Parallel Track)

**Continue current approach** for CMake 3.x compatibility:
- Finish FetchContent/CPM interception hooks
- Build parser and lock file system
- Release v1.0 based on current architecture

**Start CPS integration:**
- Add CPS generation for nix-cmake built packages
- Create cmakeCPSHook for CMake 4.0+
- Prototype CPS-based workflow

#### 2026: Transition (Dual Support)

- Support both approaches
- Document CPS workflow as "preferred"
- Contribute CPS support to nixpkgs (opt-in)
- Advocate for CPS in CMake/C++ community

#### 2027+: Future (CPS First)

- Make CPS the default for CMake 4.0+ projects
- Keep legacy hooks for CMake 3.x
- CPS becomes standard in nixpkgs

### Compatibility Matrix

| CMake Version | Best Approach | Fallback |
|---------------|---------------|----------|
| 3.24 - 3.30 | FetchContent hooks | Manual packaging |
| 4.0+ (experimental) | CPS | FetchContent hooks |
| 4.x (stable CPS) | CPS (preferred) | FetchContent hooks |

## Implementation Plan

### Immediate (Phase 0)

- [ ] Research CPS specification in depth
- [ ] Prototype CPS file generation
- [ ] Test with CMake 4.0 experimental CPS support
- [ ] Validate transitive dependency resolution

### Short Term (3-6 months)

- [ ] **Add CPS generation to nix-cmake**
  - [ ] `lib.generateCPS` function
  - [ ] Automatic CPS generation in builders
  - [ ] CPS validation

- [ ] **Create cmakeCPSHook**
  - [ ] CPS search path setup
  - [ ] CMake 4.0 flag configuration
  - [ ] Integration with existing hooks

- [ ] **Documentation**
  - [ ] CPS integration guide
  - [ ] Migration from FetchContent to CPS
  - [ ] Best practices

### Medium Term (6-12 months)

- [ ] **Nixpkgs integration**
  - [ ] Propose CPS support for cmake builder
  - [ ] Generate CPS for common packages (fmt, spdlog, catch2)
  - [ ] Upstream cmakeCPSHook

- [ ] **Parser enhancement**
  - [ ] Generate CPS from CMakeLists.txt
  - [ ] Convert FetchContent/CPM to CPS requires
  - [ ] Handle transitive dependencies

- [ ] **Lock file integration**
  - [ ] Use CPS as lock file format
  - [ ] Generate CPS from parsed dependencies
  - [ ] Validate against CPS schema

### Long Term (1-2 years)

- [ ] **Ecosystem advocacy**
  - [ ] Contribute to CPS specification
  - [ ] Promote CPS in CMake community
  - [ ] Collaborate with vcpkg/Conan on CPS

- [ ] **Advanced features**
  - [ ] Multi-platform CPS files
  - [ ] CPS-based binary caching
  - [ ] Cross-compilation with CPS

## Why This is the Right Direction

### 1. **Alignment with Standards**

CPS is a **community-driven standard** with buy-in from:
- Kitware (CMake maintainers)
- Build system vendors
- Package manager developers

We should build **with** the ecosystem, not against it.

### 2. **Future-Proof**

CMake 4.0 is the future. By targeting CPS:
- We're ahead of the curve
- Our work helps the broader community
- We avoid lock-in to CMake 3.x patterns

### 3. **Simpler Implementation**

CPS is **just JSON**. Compare:

**Parsing CMake (current plan):**
- Tokenize CMake language
- Handle string evaluation, variable expansion
- Execute CMake scripts (or approximate)
- Extract dependency info

**Parsing CPS:**
- `builtins.fromJSON (builtins.readFile "foo.cps")`

Done! 🎉

### 4. **Broader Impact**

Our work on CPS helps:
- Meson users (can read CPS too)
- Bazel users
- vcpkg users
- Conan users
- The entire C++ ecosystem

Not just CMake in Nix.

## Open Questions

1. **CMake 4.0 adoption timeline?**
   - How long until CMake 4.0 is stable?
   - When will projects require CMake 4.0?
   - Do we support CMake 3.x long-term?

2. **CPS generation for existing nixpkgs packages?**
   - Automated vs manual?
   - Opt-in vs default?
   - How to handle non-CMake packages?

3. **CPS schema evolution?**
   - Is CPS 0.12 stable?
   - How to handle schema changes?
   - Version compatibility strategy?

4. **Integration with other *2nix tools?**
   - Can uv2nix, crane learn from CPS pattern?
   - General "package spec" for all languages?

## Recommendation

**Dual-track approach:**

### Track 1: Near-term (CMake 3.x)
- Continue with FetchContent/CPM hooks
- Build parser and lock file
- Release v1.0 for current CMake ecosystem

### Track 2: Future (CPS)
- Prototype CPS integration in parallel
- Validate with CMake 4.0
- Position as "v2.0" or "next-gen" option

**Rationale:**
- Don't block v1.0 on CMake 4.0 adoption
- But invest in the future now
- When CMake 4.0 is stable, we're ready

## References

- [CPS Specification](https://cps-org.github.io/cps/)
- [Kitware Blog: Navigating CMake Dependencies with CPS](https://www.kitware.com/navigating-cmake-dependencies-with-cps/)
- [CMake 4.0 Documentation](https://cmake.org/cmake/help/v4.0/)
- [CPS JSON Schema](https://cps-org.github.io/cps/schema.html)

Sources:
- [Navigating CMake Dependencies with CPS](https://www.kitware.com/navigating-cmake-dependencies-with-cps/)
- [Common Package Specification](https://cps-org.github.io/cps/)
