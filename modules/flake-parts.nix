{ lib, flake-parts-lib, ... }:

let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) mkOption types;
in
{
  options.perSystem = mkPerSystemOption ({ config, pkgs, ... }: {
    options.cmake-project = mkOption {
      description = "Declarative nix-cmake project configuration";
      default = null;
      type = types.nullOr (types.submodule {
        options = {
          src = mkOption {
            type = types.path;
            description = "Project source directory (workspace root)";
          };
          lockFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to cmake-lock.json (default: <src>/cmake-lock.json)";
          };
          pname = mkOption {
            type = types.str;
            description = "Package name";
          };
          version = mkOption {
            type = types.str;
            description = "Package version";
          };
          cmakeFlags = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Extra CMake configuration flags";
          };
        };
      });
    };

    config = lib.mkIf (config.cmake-project != null) (
      let
        nix-cmake = import ../lib { inherit (pkgs) lib; };
        workspaceFns = nix-cmake.workspace pkgs;
        workspace = workspaceFns.loadWorkspace {
          workspaceRoot = config.cmake-project.src;
          inherit (config.cmake-project) lockFile;
        };
      in
      {
        packages = {
          ${config.cmake-project.pname} = workspace.buildPackage {
            inherit (config.cmake-project) pname version cmakeFlags src;
          };
          default = config.packages.${config.cmake-project.pname};
        };

        devShells.default = workspace.mkShell { };

        checks.discovery = workspaceFns.discoverDependencies {
          inherit (config.cmake-project) src cmakeFlags;
        };
      }
    );
  });
}
