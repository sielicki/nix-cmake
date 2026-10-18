# flake-parts Integration

`nix-cmake` ships a [flake-parts](https://flake.parts/) module at
`nix-cmake.flakeModules.default` ([`modules/flake-parts.nix`](../modules/flake-parts.nix)).

## Usage

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-cmake.url = "github:sielicki/nix-cmake";
  };

  outputs = inputs@{ flake-parts, nix-cmake, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ nix-cmake.flakeModules.default ];
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      perSystem = { ... }: {
        cmake-project = {
          src = ./.;
          pname = "my-app";
          version = "0.1.0";
          # lockFile = ./cmake-lock.json;  # optional; default <src>/cmake-lock.json
          # cmakeFlags = [ "-DMY_OPTION=ON" ];
        };
      };
    };
}
```

The project is loaded with
`workspace.loadWorkspace { workspaceRoot = src; }`, so dependencies
come from the project's `cmake-lock.json` (or `package-lock.cmake`).

## Options (`perSystem.cmake-project`)

| Option       | Type             | Default                 | Description                          |
|--------------|------------------|-------------------------|--------------------------------------|
| `enable`     | (set non-null)   | `null` (disabled)       | Set the whole attrset to enable      |
| `src`        | path             | — (required)            | Project directory / workspace root   |
| `pname`      | string           | — (required)            | Package name                         |
| `version`    | string           | — (required)            | Package version                      |
| `lockFile`   | null or path     | `null`                  | Explicit `cmake-lock.json` location  |
| `cmakeFlags` | list of strings  | `[]`                    | Extra CMake configuration flags      |

## Generated outputs

For each system, setting `cmake-project` produces:

- `packages.<pname>` — the built package (also `packages.default`).
- `devShells.default` — `workspace.mkShell` with dependency sources
  exported as `FETCHCONTENT_SOURCE_DIR_*`.
- `checks.discovery` — a `discoverDependencies` derivation (File API
  replies + discovery log) for inspecting/updating the lock file.

For anything beyond this single-project shape (multiple projects,
custom inputs, dynamic-derivation builds), use the library directly:
see [API.md](API.md) and [DYNAMIC-DERIVATIONS.md](DYNAMIC-DERIVATIONS.md).
