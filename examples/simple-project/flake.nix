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

    in
    {
      # Development shell with all dependencies from lock file
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # Load workspace - reads cmake-lock.json automatically
          workspace = nix-cmake.lib.workspace pkgs {
            workspaceRoot = ./.;
          };
        in
        {
          default = workspace.mkShell {
            packages = [ pkgs.git ];
          };
        }
      );

      # Build the package with dependencies from lock file
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          workspace = nix-cmake.lib.workspace pkgs {
            workspaceRoot = ./.;
          };
        in
        {
          default = workspace.buildPackage {
            pname = "my-project";
            version = "0.1.0";
          };
        }
      );

      # Discovery derivation for updating the lock file
      # Run: nix build .#discovery && cmake2nix lock
      apps = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          workspace = nix-cmake.lib.workspace pkgs {
            workspaceRoot = ./.;
          };
        in
        {
          discovery = {
            type = "app";
            program = toString (workspace.discoverDependencies {
              src = ./.;
            });
          };
        }
      );
    };
}
