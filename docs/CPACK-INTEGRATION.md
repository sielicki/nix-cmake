# CPack External Generator Integration

This document explores potential integration between CPack's External generator and nix-cmake. **This is currently deferred work** - documented for future consideration but not yet implemented.

## Background

CPack's External generator (available since CMake 3.13) outputs JSON metadata about package structure instead of creating actual packages. This metadata includes:

- Components and their files
- Component dependencies
- Installation types
- File permissions and types
- Package metadata (name, version, description)

Example output:
```json
{
  "formatVersionMajor": 1,
  "formatVersionMinor": 0,
  "components": [
    {
      "name": "Runtime",
      "displayName": "Runtime Libraries",
      "description": "Runtime libraries needed for execution",
      "isRequired": true,
      "installationTypes": ["Full", "Runtime"],
      "files": [
        {"path": "bin/myapp", "permissions": 755},
        {"path": "lib/libfoo.so.1.0", "permissions": 644}
      ]
    },
    {
      "name": "Development",
      "displayName": "Development Files",
      "depends": ["Runtime"],
      "files": [
        {"path": "include/foo.h", "permissions": 644},
        {"path": "lib/libfoo.so", "permissions": 644}
      ]
    }
  ]
}
```

## Use Cases

### 1. Automatic Nix Derivation Generation

Generate multi-output Nix derivations directly from CPack metadata:

```nix
# Generated from CPack External JSON
{ stdenv, cmake }:

stdenv.mkDerivation {
  pname = "myapp";
  version = "1.0.0";

  outputs = [ "out" "dev" "doc" ];

  # CPack components -> Nix outputs mapping
  # Runtime component -> out
  # Development component -> dev
  # Documentation component -> doc
}
```

### 2. Component-Based Multi-Output Derivations

CPack components map naturally to Nix outputs:

```cmake
# CMakeLists.txt
install(TARGETS mylib
  RUNTIME DESTINATION bin COMPONENT Runtime
  LIBRARY DESTINATION lib COMPONENT Runtime
  ARCHIVE DESTINATION lib COMPONENT Development
)
install(FILES mylib.h DESTINATION include COMPONENT Development)
```

CPack External JSON shows these components, which nix-cmake could use to automatically:
- Create appropriate outputs (`out`, `dev`, `doc`, etc.)
- Move files to correct outputs
- Set up inter-output dependencies

### 3. Hermetic Package Creation

Use CPack External with a Nix-aware CPack script:

```bash
#!/usr/bin/env bash
# cpack-nix-generator.sh - Hermetic CPack script
set -euo pipefail

cpack_json="$1"
output_dir="$2"

# Parse CPack JSON and create Nix store structure
jq -r '.components[] | .files[] | .path' "$cpack_json" | while read file; do
  install -D "$file" "$output_dir/$file"
done
```

Benefits:
- No system dependencies during packaging
- Reproducible package layouts
- Integration with Nix store

### 4. Dependency Graph Analysis

CPack's component dependencies provide a graph that could validate Nix output dependencies:

```json
{
  "components": [
    {"name": "Runtime", "depends": []},
    {"name": "Development", "depends": ["Runtime"]},
    {"name": "Debug", "depends": ["Runtime", "Development"]}
  ]
}
```

nix-cmake could verify that Nix output dependencies match CPack component dependencies.

### 5. Cross-Platform Package Matrix

CPack External can generate metadata for multiple platforms without building actual packages:

```bash
# Generate metadata for all platforms
for platform in linux darwin windows; do
  cmake -DCMAKE_SYSTEM_NAME=$platform -B build-$platform
  cd build-$platform && cpack -G External
done
```

This metadata could drive:
- Platform-specific output structure
- Conditional installation rules
- Cross-compilation setup

### 6. nix-cmake Integration: Auto-Discover Installation Layout

The most practical integration - add a workspace function to analyze CPack metadata:

```nix
workspace.analyzeCPackLayout {
  src = ./.;

  # Runs CMake configure + cpack -G External
  # Returns structured data about installation
}
# Returns:
# {
#   outputs = [ "out" "dev" "doc" ];
#   componentMap = {
#     Runtime = "out";
#     Development = "dev";
#     Documentation = "doc";
#   };
#   dependencies = {
#     dev = [ "out" ];
#     doc = [ ];
#   };
# }
```

This could then inform buildPackage:

```nix
let
  layout = workspace.analyzeCPackLayout { src = ./.; };
in
workspace.buildPackage {
  pname = "myapp";
  version = "1.0.0";
  src = ./.;

  # Automatically use discovered layout
  outputs = layout.outputs;

  # Auto-generated postInstall to split outputs
  postInstall = layout.splitOutputsScript;
}
```

### 7. Installation Type Variants

CPack supports installation types (Full, Minimal, Custom). These could map to Nix variants:

```nix
{
  myapp-full = buildWithCPackType "Full";
  myapp-minimal = buildWithCPackType "Minimal";
  myapp-dev = buildWithCPackType "Developer";
}
```

### 8. Validation and Testing

Use CPack metadata to validate Nix package structure:

```nix
passthru.tests.cpack-compliance = runCommand "test-cpack" {} ''
  # Verify all CPack components are in correct outputs
  ${jq}/bin/jq -r '.components[] | .name' ${cpackMetadata} | while read component; do
    output=$(get_output_for_component "$component")
    # Verify files exist in output
  done
  touch $out
'';
```

## Recommended Implementation: workspace.analyzeCPackLayout

The most valuable integration would be a workspace function that:

1. **Runs CMake configuration** with CPack External generator
2. **Parses JSON metadata** to understand installation structure
3. **Returns structured data** that informs buildPackage

### Implementation Sketch

```nix
# lib/builders.nix
analyzeCPackLayout = args: pkgs.runCommand "analyze-cpack" {
  nativeBuildInputs = [ cmake cmakeDependencyHook jq ];
} ''
  cp -r ${args.src} source
  cd source

  cmake -B build -G Ninja \
    ${lib.concatStringsSep " " (args.cmakeFlags or [])}

  cd build
  cpack -G External --config CPackConfig.cmake

  # Parse CPackMetadata.json
  ${jq}/bin/jq '{
    outputs: [.components[] | .name | ascii_downcase],
    componentMap: (.components | map({(.name): (.name | ascii_downcase)}) | add),
    dependencies: (.components | map({
      (.name | ascii_downcase): [.depends[]? | ascii_downcase]
    }) | add)
  }' CPackMetadata.json > $out
'';
```

### Usage Example

```nix
let
  layout = workspace.analyzeCPackLayout {
    src = ./.;
    cmakeFlags = [ "-DBUILD_SHARED_LIBS=ON" ];
  };
in
workspace.buildPackage {
  pname = "mylib";
  version = "1.0.0";
  src = ./.;

  outputs = layout.outputs;

  postInstall = ''
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (component: output: ''
        # Move ${component} files to ${output}
        # Based on CPack metadata
      '') layout.componentMap
    )}
  '';
}
```

## Benefits

1. **Automatic output discovery** - No manual output specification needed
2. **Upstream compatibility** - Uses standard CPack, no nix-cmake-specific CMake code
3. **Component dependency validation** - Ensures Nix outputs respect CMake component dependencies
4. **Platform awareness** - CPack handles platform-specific installation rules
5. **Documentation** - CPack metadata documents package structure

## Trade-offs

**Pros:**
- Leverages existing CMake packaging knowledge
- No custom CMake code needed
- Works with any CMake project using CPack
- Validates installation structure

**Cons:**
- Additional build-time overhead (runs CMake twice - once to analyze, once to build)
- Requires projects to use CPack (but could fall back if not present)
- JSON parsing adds complexity
- May not capture all Nix-specific output splitting needs

## Future Work

If implemented, this feature would:

1. Add `workspace.analyzeCPackLayout` function
2. Optionally auto-apply in `buildPackage` if CPack is detected
3. Provide override mechanism for custom output splitting
4. Add tests demonstrating CPack integration
5. Document CPack best practices for Nix compatibility

## Status

**Deferred** - This is documented for future consideration but not currently implemented. The core nix-cmake functionality (dependency management, lock files, hermetic builds) takes priority. CPack integration would be a valuable enhancement for automatic output discovery and validation.
