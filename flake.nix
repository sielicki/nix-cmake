{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/0.1.914780";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
      ];
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      perSystem = { config, final, self', inputs', pkgs, system, ... }: {
        # For now, expose packages directly without overlay
        # The overlay approach causes stdenv bootstrap issues with xcbuild
        packages = {
          cmakeToolchainHook = pkgs.callPackage ./pkgs/cmake-toolchain-hook { };
          cmakeDependencyHook = (pkgs.callPackage ./pkgs/cmake-dependency-hook { }).setupHook;
          cmakeMinimal = pkgs.callPackage ./pkgs/cmake/bootstrap.nix {};
          cmake = pkgs.callPackage ./pkgs/cmake {
            cmakeMinimal = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
            cmakeToolchainHook = self'.packages.cmakeToolchainHook;
          };
          # Use nixpkgs' fmt which has proper CMake config files
          fmt = pkgs.fmt;
          cmake2nix = pkgs.callPackage ./pkgs/cmake2nix { 
            nix-cmake-lib = ./lib;
          };
          rapids-cmake = pkgs.callPackage ./pkgs/rapids-cmake { };
          default = self'.packages.cmake;
        };

        checks = {
          simple-fetchcontent = pkgs.callPackage ./tests/simple-fetchcontent {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
            fmt = self'.packages.fmt;
          };
          simple-cpm = pkgs.callPackage ./tests/simple-cpm {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
          };
          multi-dependency = pkgs.callPackage ./tests/multi-dependency {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
            fmt = self'.packages.fmt;
          };
          discovery-test = pkgs.callPackage ./tests/discovery-test.nix {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
          };
          discovery-multi-test = pkgs.callPackage ./tests/discovery-multi-test.nix {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
          };
          stdexec-discovery = pkgs.callPackage ./tests/stdexec/discover.nix {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
            rapids-cmake = self'.packages.rapids-cmake;
          };
        };

        # TODO: Re-enable overlay once we figure out stdenv bootstrap
        # overlayAttrs = {
        #   cmakeToolchainHook = final.callPackage ./pkgs/cmake-toolchain-hook { };
        #   cmakeDependencyHook = (final.callPackage ./pkgs/cmake-dependency-hook { }).setupHook;
        #   cmake = final.callPackage ./pkgs/cmake { };
        #   cmakeMinimal = final.callPackage ./pkgs/cmake/bootstrap.nix {};
        # };
      };
      flake = {
        lib = import ./lib { inherit (inputs.nixpkgs) lib; };
        flakeModules.default = import ./modules/flake-parts.nix;
      };
    };
}
