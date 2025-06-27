{ self, lib, ... }:

{
  options.perSystem = lib.mkOption {
    type = lib.types.submoduleWith {
      modules = [
        ({ config, pkgs, ... }: {
          options.cmake-project = lib.mkOption {
            description = "Declarative Nix-CMake project configuration";
            default = null;
            type = lib.types.nullOr (lib.types.submodule {
              options = {
                src = lib.mkOption {
                  type = lib.types.path;
                  description = "Project source directory";
                };
                lockFile = lib.mkOption {
                  type = lib.types.nullOr lib.types.path;
                  default = null;
                  description = "Path to cmake-lock.json";
                };
                pname = lib.mkOption {
                  type = lib.types.str;
                  description = "Package name";
                };
                version = lib.mkOption {
                  type = lib.types.str;
                  description = "Package version";
                };
                cmakeFlags = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                };
              };
            });
          };

          config = lib.mkIf (config.cmake-project != null) (
            let
              nix-cmake = import ../lib { inherit (pkgs) lib; };
              workspace = nix-cmake.workspace pkgs {
                inherit (config.cmake-project) src lockFile;
              };
            in {
              packages = {
                ${config.cmake-project.pname} = workspace.buildPackage {
                  inherit (config.cmake-project) pname version cmakeFlags;
                };
                default = config.packages.${config.cmake-project.pname};
              };

              devShells.default = workspace.mkShell {};

              checks.discovery = workspace.discoverDependencies {
                inherit (config.cmake-project) src cmakeFlags;
              };
            }
          );
        })
      ];
    };
  };
}
