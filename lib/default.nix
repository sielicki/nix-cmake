{ lib }:

{
  parseCMakeLists = import ./parseCMakeLists.nix { inherit lib; };
  dependency = import ./dependency.nix { inherit lib; };
  workspace = pkgs: import ./workspace.nix { inherit lib pkgs; };
  builders = pkgs: import ./builders.nix { inherit lib pkgs; };
  toolchains = pkgs: import ./toolchains { inherit lib pkgs; };
  cps = import ./cps.nix { inherit lib; };
}
