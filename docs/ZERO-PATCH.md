# Zero-Patch Philosophy

This document explains how nix-cmake achieves hermetic builds without patching CMake, in contrast to nixpkgs' approach.

## The Problem

CMake's Find modules search for dependencies in system locations like `/usr`, `/usr/local`, `/opt`, etc. On systems with development tools installed (Homebrew, MacPorts, system packages), CMake will find and link against these libraries, breaking build reproducibility.

## Traditional Approach: Patching (nixpkgs)

Nixpkgs applies a [massive patch](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/cm/cmake/0001-CMake-Nix-patches.patch) that removes impure paths from:
- 50+ Find modules (FindJava, FindCUDA, FindQt, FindGTK, FindOpenGL, etc.)
- Platform files (Darwin.cmake, Linux.cmake, UnixPaths.cmake)
- Utility modules (GNUInstallDirs.cmake, GetPrerequisites.cmake)

**Problems with this approach:**
- 1000+ lines of patches to maintain
- Patches break with each CMake release
- Fragile: Easy to miss a new impure path
- Opaque: Unclear what's being ignored
- Incomplete: Can't catch all impure paths

## Our Approach: CMake Variables (nix-cmake)

CMake 3.23+ provides `CMAKE_SYSTEM_IGNORE_PREFIX_PATH` specifically for this use case. We simply set:

```bash
CMAKE_SYSTEM_IGNORE_PREFIX_PATH="/usr;/usr/local;/opt;/Library;/System/Library;/opt/local;/opt/homebrew;/sw"
```

This single variable affects all `find_*` commands across CMake:
- `find_package()`
- `find_library()`
- `find_file()`
- `find_path()`
- `find_program()`

## Benefits

| Aspect | Nixpkgs (Patching) | nix-cmake (Variables) |
|--------|-------------------|----------------------|
| **Lines of code** | 1000+ lines of patches | 10 lines of bash |
| **Maintenance** | Update patches for each CMake version | Works with any CMake 3.23+ |
| **Coverage** | Only patched modules | All Find modules automatically |
| **Transparency** | Buried in patch file | Explicit in build log |
| **Upstream** | Diverges from upstream | Uses stock CMake |
| **Robustness** | Breaks if patch fails to apply | Can't break |

## Implementation

In `pkgs/cmake-dependency-hook/default.nix`:

```bash
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
local ignorePathsStr="${ignorePaths[0]}"
for path in "${ignorePaths[@]:1}"; do
  ignorePathsStr="$ignorePathsStr;$path"
done
cmakeFlags+=("-DCMAKE_SYSTEM_IGNORE_PREFIX_PATH=$ignorePathsStr")
```

The ignored prefixes are printed in the build log:
```
Ignored prefixes: /usr;/usr/local;/opt;/Library;/System/Library;/opt/local;/opt/homebrew;/sw
```

## Other Impurities Handled via Variables and Wrappers

### SSL Certificates

**Nixpkgs approach**: Patch `Utilities/cmcurl/CMakeLists.txt` to remove auto-detection

**Our approach**: Set `CURL_CA_BUNDLE` variable:
```bash
if [[ -n "${NIX_SSL_CERT_FILE:-}" ]]; then
  cmakeFlags+=("-DCURL_CA_BUNDLE=${NIX_SSL_CERT_FILE}")
fi
```

### CPM.cmake Integration

**Problem**: CPM downloads dependencies by default

**Our approach**: Use CPM's built-in variable:
```bash
cmakeFlags+=("-DCPM_USE_LOCAL_PACKAGES=ON")
```

This makes CPM try `find_package()` before downloading, allowing it to use pre-built nixpkgs packages.

### Runtime Tool Dependencies

**Nixpkgs approach**: Patch CMake source to replace tool names with absolute Nix store paths:
```diff
- execute_process(COMMAND sw_vers -productVersion
+ execute_process(COMMAND @sw_vers@ -productVersion
```

Then use `replaceVars` to substitute templates with actual paths at build time.

**Our approach**: Use `wrapProgram` to ensure tools are available in `PATH`:
```nix
postInstall = ''
  for prog in cmake ctest cpack; do
    wrapProgram "$out/bin/$prog" \
      --prefix PATH : ${lib.makeBinPath ([
        git ps sysctl
      ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
        darwin.DarwinTools    # sw_vers
        darwin.system_cmds    # vm_stat
      ])}
  done
'';
```

This ensures CMake can find tools like:
- `git` - Used by FetchContent and FindGit.cmake
- `ps` - Process detection for platform info
- `sysctl` - System information (CPU count, architecture)
- `sw_vers` (macOS) - macOS version detection
- `vm_stat` (macOS) - Memory statistics

## Comparison Table

Here's what the nixpkgs patch removes vs what we handle via variables:

| Impure Path | Nixpkgs Patch | nix-cmake Variable |
|-------------|---------------|-------------------|
| `/usr/bin` | ✓ (manual) | ✓ (automatic via prefix) |
| `/usr/local` | ✓ (manual) | ✓ (automatic via prefix) |
| `/opt/*` | ✓ (manual) | ✓ (automatic via prefix) |
| `/Library/Frameworks` | ✓ (manual) | ✓ (automatic via prefix) |
| Homebrew paths | ✓ (manual) | ✓ (automatic via prefix) |
| MacPorts paths | ✓ (manual) | ✓ (automatic via prefix) |
| Java system paths | ✓ (manual) | ✓ (automatic) |
| Qt system paths | ✓ (manual) | ✓ (automatic) |
| CUDA system paths | ✓ (manual) | ✓ (automatic) |
| **New paths in future CMake versions** | ✗ (needs patch update) | ✓ (automatic) |

## Testing

All tests pass with zero patches:

```bash
$ nix flake check
✅ checks.aarch64-darwin.simple-cpm
✅ checks.aarch64-darwin.stdexec-discovery
✅ checks.aarch64-darwin.discovery-test
✅ checks.aarch64-darwin.simple-fetchcontent
✅ checks.aarch64-darwin.multi-dependency
✅ checks.aarch64-darwin.discovery-multi-test
```

Build logs show ignored prefixes being applied:
```
CMake configuration:
  Source directory: ..
  Build directory: /nix/var/nix/builds/.../build
  Ignored prefixes: /usr;/usr/local;/opt;/Library;/System/Library;/opt/local;/opt/homebrew;/sw
```

## Future Work

Additional impurities that could be handled via variables instead of patches:

1. **Python search paths**: Use `Python3_ROOT_DIR` instead of patching `FindPython`
2. **Java home detection**: Use `JAVA_HOME` instead of patching `FindJava.cmake`
3. **Framework search paths**: Already handled by `CMAKE_SYSTEM_IGNORE_PREFIX_PATH`
4. **Library architecture paths**: Use `CMAKE_LIBRARY_ARCHITECTURE` instead of patching

## Conclusion

By using CMake's built-in variables instead of patches, we achieve:
- **Simpler code**: 10 lines vs 1000+ lines
- **Better compatibility**: Works with any CMake version
- **More robust**: Can't break on CMake updates
- **More transparent**: Users can see what's being ignored
- **Easier to maintain**: No patch rebasing needed

This demonstrates that Nix can work with unmodified upstream CMake using declarative configuration instead of invasive patching.
