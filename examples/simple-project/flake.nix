{
  description = "Simple CMake project using nix-cmake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-cmake = {
      url = "github:sielicki/nix-cmake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nix-cmake, ... }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      # Load workspace - reads cmake-lock.json automatically
      mkWorkspace = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        (nix-cmake.lib.workspace pkgs).loadWorkspace {
          workspaceRoot = ./.;
        };
    in
    {
      # Development shell with all dependencies from lock file
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          workspace = mkWorkspace system;
        in
        {
          default = workspace.mkShell {
            packages = [ pkgs.git ];
          };
        }
      );

      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          workspace = mkWorkspace system;
          workspaceFns = nix-cmake.lib.workspace pkgs;
        in
        {
          # Build the package with dependencies from lock file
          default = workspace.buildPackage {
            pname = "my-project";
            version = "0.1.0";
          };

          # Discovery derivation for updating the lock file
          # Run: nix build .#discovery
          discovery = workspaceFns.discoverDependencies {
            src = ./.;
          };
        }
      );
    };
}
