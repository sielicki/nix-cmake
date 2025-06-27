# flake-parts Integration

## Overview

nix-cmake provides first-class [flake-parts](https://flake.parts/) integration, following the patterns established by successful Nix ecosystem tools like [haskell-flake](https://community.flake.parts/haskell-flake), [process-compose-flake](https://community.flake.parts/process-compose-flake), and [treefmt-nix](https://github.com/numtide/treefmt-nix).

## Design Philosophy

Following flake-parts best practices:

1. **Declarative workspace definitions** - Define CMake workspaces in `perSystem.cmake2nix.workspaces`
2. **Automatic output generation** - Packages, devShells, checks, and apps generated automatically
3. **Composable with other modules** - Works alongside other flake-parts modules
4. **Type-safe configuration** - Leverages flake-parts' module system
5. **Per-system configuration** - Native support for cross-compilation

## Quick Start

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    cmake2nix.url = "github:sielicki/nix-cmake";
  };

  outputs = inputs @ { flake-parts, cmake2nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        cmake2nix.flakeModules.default
      ];

      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      perSystem = { config, pkgs, ... }: {
        # Define your CMake workspace
        cmake2nix.workspaces.myapp = {
          root = ./.;
        };

        # Automatically provides:
        # - packages.myapp
        # - devShells.myapp
        # - checks.myapp-test
      };
    };
}
```

## Module Options

### perSystem.cmake2nix.workspaces.\<name\>

Define a CMake workspace.

#### Basic Options

```nix
cmake2nix.workspaces.myapp = {
  # Required: path to workspace root
  root = ./.;

  # Optional: lock file path (auto-discovered if not specified)
  lockFile = ./cmake.lock;

  # Optional: CPM lock file
  cpmLockFile = ./cmake/CPMLock.cmake;

  # Optional: workspace type
  type = "application";  # or "library", "header-only"

  # Optional: override auto-detected metadata
  meta = {
    description = "My awesome application";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.me ];
  };
};
```

#### Build Options

```nix
cmake2nix.workspaces.myapp = {
  root = ./.;

  # CMake configuration
  cmakeFlags = [
    (lib.cmakeBool "BUILD_TESTING" false)
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
  ];

  # Build type
  cmakeBuildType = "Release";  # or "Debug", "RelWithDebInfo"

  # Additional build inputs
  buildInputs = [ pkgs.openssl ];
  nativeBuildInputs = [ pkgs.pkg-config ];

  # Enable/disable features
  enableTests = true;
  enableDocs = true;
  enableExamples = false;
};
```

#### Dependency Configuration

```nix
cmake2nix.workspaces.myapp = {
  root = ./.;

  # Dependency resolution strategy
  preferSystemPackages = true;  # Use find_package when possible
  sourcePreference = "source";   # or "binary"

  # CPM configuration
  cpm = {
    enable = true;
    useNamedCacheDirectories = true;
  };

  # Override specific dependencies
  dependencyOverrides = {
    fmt = pkgs.fmt;  # Use nixpkgs version instead of FetchContent
  };

  # Dependency sets to build
  dependencySets = [ "default" "dev" ];  # or "all"
};
```

#### Cross-Compilation

```nix
cmake2nix.workspaces.myapp = {
  root = ./.;

  # Cross-compilation targets
  crossTargets = {
    aarch64-linux = {
      # Per-target overrides
      cmakeFlags = [ "-DENABLE_NEON=ON" ];
    };

    x86_64-windows = {
      # Windows-specific configuration
      buildInputs = [ pkgs.mingw-w64 ];
    };
  };
};
```

#### Output Configuration

```nix
cmake2nix.workspaces.myapp = {
  root = ./.;

  # Control which outputs are generated
  outputs = {
    package = true;      # Generate packages.<name>
    devShell = true;     # Generate devShells.<name>
    checks = true;       # Generate checks.<name>-*
    apps = {
      lock = true;       # Generate apps.<name>-lock
      run = true;        # Generate apps.<name> (if application)
    };
  };

  # Multi-output package configuration
  packageOutputs = [ "out" "dev" "doc" ];
};
```

### perSystem.cmake2nix.defaults

Set defaults for all workspaces.

```nix
perSystem = { ... }: {
  cmake2nix.defaults = {
    cmakeBuildType = "RelWithDebInfo";
    enableTests = true;
    preferSystemPackages = true;

    # These apply to all workspaces unless overridden
  };

  cmake2nix.workspaces = {
    app1.root = ./app1;  # Inherits defaults
    app2 = {
      root = ./app2;
      enableTests = false;  # Override default
    };
  };
};
```

### perSystem.cmake2nix.packageSet

Access the generated CMake package set.

```nix
perSystem = { config, ... }: {
  cmake2nix.workspaces.myapp.root = ./.;

  # Access generated packages
  packages.custom = config.cmake2nix.packageSet.myapp.overrideAttrs (old: {
    # Customize the generated package
  });

  # Use in other derivations
  devShells.custom = pkgs.mkShell {
    buildInputs = [ config.cmake2nix.packageSet.myapp ];
  };
};
```

## Generated Outputs

For each workspace `<name>`, the following outputs are generated:

### packages.\<name\>

The built CMake package.

```bash
# Build the package
nix build .#myapp

# Build for different system
nix build .#packages.aarch64-linux.myapp
```

### devShells.\<name\>

Development shell with all dependencies and tools.

```bash
# Enter development shell
nix develop .#myapp

# Available in the shell:
# - cmake, ninja, etc.
# - All project dependencies
# - Project source in editable mode
```

The devShell includes:
- CMake and build tools (cmake, ninja, ccache)
- All runtime and build dependencies
- Development tools (clang-format, clang-tidy if configured)
- Language servers (clangd)

### checks.\<name\>-test

Test suite execution.

```bash
# Run tests
nix flake check .#myapp-test

# Or via nix build
nix build .#checks.x86_64-linux.myapp-test
```

### checks.\<name\>-format

Code formatting check (if enabled).

```bash
nix flake check .#myapp-format
```

### apps.\<name\>-lock

Generate or update lock file.

```bash
# Generate/update lock file
nix run .#myapp-lock

# Update specific dependency
nix run .#myapp-lock -- --update fmt
```

### apps.\<name\> (for applications)

Run the application directly.

```bash
# Run the application
nix run .#myapp

# With arguments
nix run .#myapp -- --help
```

## Integration Examples

### Example 1: Simple Application

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    cmake2nix.url = "github:sielicki/nix-cmake";
  };

  outputs = inputs @ { flake-parts, cmake2nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ cmake2nix.flakeModules.default ];
      systems = [ "x86_64-linux" "aarch64-darwin" ];

      perSystem = { ... }: {
        cmake2nix.workspaces.hello = {
          root = ./.;
          type = "application";
        };
      };
    };
}
```

**Provides:**
- `packages.hello` - Built executable
- `devShells.hello` - Development environment
- `checks.hello-test` - Test suite
- `apps.hello` - Run the application
- `apps.hello-lock` - Update dependencies

### Example 2: Multi-Workspace Monorepo

```nix
perSystem = { pkgs, lib, ... }: {
  cmake2nix = {
    defaults = {
      cmakeBuildType = "RelWithDebInfo";
      enableTests = true;
    };

    workspaces = {
      # Core library
      mylib = {
        root = ./lib;
        type = "library";
        packageOutputs = [ "out" "dev" "doc" ];
      };

      # Application using the library
      myapp = {
        root = ./app;
        type = "application";
        buildInputs = [ config.cmake2nix.packageSet.mylib ];
      };

      # Python bindings
      pymylib = {
        root = ./bindings/python;
        type = "library";
        buildInputs = [
          config.cmake2nix.packageSet.mylib
          pkgs.python3
        ];
      };

      # Examples
      examples = {
        root = ./examples;
        enableTests = false;
        outputs.package = false;  # Don't publish examples
      };
    };
  };
};
```

### Example 3: RAPIDS Project

```nix
perSystem = { ... }: {
  cmake2nix.workspaces.rapids-app = {
    root = ./.;

    # RAPIDS-specific configuration
    rapids = {
      enable = true;
      version = "24.02";
    };

    # CUDA support
    cuda = {
      enable = true;
      cudaCapabilities = [ "8.0" "8.6" "9.0" ];
    };

    cmakeFlags = [
      (lib.cmakeBool "BUILD_TESTS" true)
    ];
  };
};
```

### Example 4: Cross-Platform Library

```nix
perSystem = { pkgs, ... }: {
  cmake2nix.workspaces.crosslib = {
    root = ./.;
    type = "library";

    # Platform-specific configurations
    crossTargets = {
      aarch64-linux = {
        cmakeFlags = [ "-DENABLE_NEON=ON" ];
      };

      x86_64-darwin = {
        cmakeFlags = [ "-DENABLE_METAL=ON" ];
      };

      x86_64-windows = {
        buildInputs = [ pkgs.mingw-w64 ];
        cmakeFlags = [ "-DENABLE_DIRECTX=ON" ];
      };
    };

    # Generate packages for all targets
    outputs.crossPackages = true;
  };
};
```

### Example 5: Integration with Other Modules

```nix
{
  imports = [
    cmake2nix.flakeModules.default
    inputs.treefmt-nix.flakeModules.default
  ];

  perSystem = { ... }: {
    # CMake workspace
    cmake2nix.workspaces.myapp = {
      root = ./.;
      enableTests = true;
    };

    # Formatting (treefmt-nix)
    treefmt = {
      projectRootFile = "flake.nix";
      programs = {
        clang-format.enable = true;
        cmake-format.enable = true;
        nixpkgs-fmt.enable = true;
      };
    };

    # Formatting check integrates with cmake2nix checks
    checks.formatting = config.treefmt.build.check;
  };
}
```

## Advanced Features

### Custom Package Transformations

```nix
perSystem = { config, lib, ... }: {
  cmake2nix.workspaces.myapp = {
    root = ./.;

    # Transform the generated package
    packageTransform = pkg: pkg.overrideAttrs (old: {
      postInstall = old.postInstall or "" + ''
        # Additional installation steps
        wrapProgram $out/bin/myapp \
          --set MY_DATA_DIR $out/share/myapp
      '';
    });
  };
};
```

### Conditional Workspace Activation

```nix
perSystem = { pkgs, lib, ... }: {
  cmake2nix.workspaces = lib.optionalAttrs pkgs.stdenv.isLinux {
    # Only build on Linux
    linux-app = {
      root = ./linux-only;
    };
  } // lib.optionalAttrs pkgs.stdenv.isDarwin {
    # Only build on macOS
    macos-app = {
      root = ./macos-only;
    };
  };
};
```

### Workspace Dependencies

```nix
perSystem = { config, ... }: {
  cmake2nix.workspaces = {
    core = {
      root = ./core;
      type = "library";
    };

    utils = {
      root = ./utils;
      type = "library";
      # Depends on core
      workspaceDependencies = [ "core" ];
    };

    app = {
      root = ./app;
      # Depends on both core and utils
      workspaceDependencies = [ "core" "utils" ];
    };
  };
};
```

## Migration from Manual Flakes

### Before (Manual)

```nix
{
  outputs = { nixpkgs, ... }: {
    packages.x86_64-linux.myapp = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in pkgs.stdenv.mkDerivation {
      name = "myapp";
      src = ./.;

      nativeBuildInputs = [ pkgs.cmake ];

      # Manual dependency setup
      preConfigure = ''
        export CPM_SOURCE_CACHE=$TMPDIR/cpm
        # ... 50 more lines of boilerplate
      '';
    };

    devShells.x86_64-linux.default = pkgs.mkShell {
      # ... manual shell setup
    };
  };
}
```

### After (with flake-parts)

```nix
{
  outputs = inputs @ { flake-parts, cmake2nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ cmake2nix.flakeModules.default ];
      systems = [ "x86_64-linux" ];

      perSystem = { ... }: {
        cmake2nix.workspaces.myapp.root = ./.;
      };
    };
}
```

**Reduction:** ~60 lines → 12 lines

## Testing

The flake-parts module includes test utilities:

```nix
perSystem = { config, ... }: {
  cmake2nix.workspaces.myapp = {
    root = ./.;
    enableTests = true;

    # Test configuration
    tests = {
      # Run tests with specific flags
      unit = {
        cmakeFlags = [ "-DUNIT_TESTS_ONLY=ON" ];
      };

      integration = {
        cmakeFlags = [ "-DINTEGRATION_TESTS=ON" ];
      };
    };
  };

  # Generates:
  # - checks.myapp-test-unit
  # - checks.myapp-test-integration
};
```

## Best Practices

1. **Use lock files** - Always commit `cmake.lock` to version control
2. **Pin inputs** - Pin flake inputs for reproducibility
3. **Enable tests** - Set `enableTests = true` for CI integration
4. **Use defaults** - Set common options in `cmake2nix.defaults`
5. **Workspace per package** - One workspace per buildable unit
6. **Development shells** - Use generated devShells for development
7. **CI integration** - Use `nix flake check` in CI

## Troubleshooting

### Issue: Workspace not detected

**Solution:** Ensure `root` points to directory with `CMakeLists.txt`

```nix
cmake2nix.workspaces.myapp = {
  root = ./.;  # Should contain CMakeLists.txt
};
```

### Issue: Lock file not found

**Solution:** Generate lock file first

```bash
nix run .#myapp-lock
```

### Issue: Cross-compilation fails

**Solution:** Ensure target is in `systems` list

```nix
{
  systems = [ "x86_64-linux" "aarch64-linux" ];  # Add target
  perSystem.cmake2nix.workspaces.myapp.root = ./.;
}
```

## See Also

- [API Documentation](./API.md)
- [Design Document](./DESIGN.md)
- [flake-parts documentation](https://flake.parts)
- [haskell-flake](https://community.flake.parts/haskell-flake) - Similar pattern for Haskell
