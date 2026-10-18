{
  description = "Modular, zero-patch CMake integration for Nix (FetchContent/CPM interception, discovery, dynamic derivations)";

  # Neither dynamic derivations nor import-from-derivation are required
  # to evaluate or use this flake. lib.dynamic uses dynamic derivations
  # only when the evaluating Nix has them enabled (detected via
  # `builtins ? outputOf`); the dynamic test below is gated the same way.

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/0.1.914780";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
        inputs.treefmt-nix.flakeModule
        inputs.pre-commit-hooks.flakeModule
      ];
      # x86_64-darwin removed: dropped by nixpkgs (26.11 release notes).
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      perSystem = { config, self', pkgs, ... }: {
        packages = {
          cmakeToolchainHook = pkgs.callPackage ./pkgs/cmake-toolchain-hook { };
          cmakeDependencyHook = (pkgs.callPackage ./pkgs/cmake-dependency-hook { }).setupHook;
          cmakeMinimal = pkgs.callPackage ./pkgs/cmake/bootstrap.nix { };
          cmake = pkgs.callPackage ./pkgs/cmake {
            cmakeMinimal = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
            cmakeToolchainHook = self'.packages.cmakeToolchainHook;
          };
          cmake2nix = pkgs.callPackage ./pkgs/cmake2nix {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
          };
          rapids-cmake = pkgs.callPackage ./pkgs/rapids-cmake { };
          cmakeCpsCompat = pkgs.callPackage ./pkgs/cmake-cps-compat { };
          default = self'.packages.cmake;
          # Upstream projects repackaged with nix-cmake (see dogfood/).
          # Exposed as packages, deliberately not checks, so `nix flake
          # check` stays fast; build with e.g. `nix build .#dogfood-fmt`.
        } // pkgs.lib.mapAttrs'
          (name: pkg: pkgs.lib.nameValuePair "dogfood-${name}" pkg)
          (builtins.removeAttrs
            (pkgs.callPackage ./dogfood {
              cmake = self'.packages.cmakeMinimal;
              cmakeDependencyHook = self'.packages.cmakeDependencyHook;
            }) [ "override" "overrideDerivation" ]);

        checks = {
          simple-fetchcontent = pkgs.callPackage ./tests/simple-fetchcontent {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
            inherit (pkgs) fmt;
          };
          simple-cpm = pkgs.callPackage ./tests/simple-cpm {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
          };
          multi-dependency = pkgs.callPackage ./tests/multi-dependency {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
            inherit (pkgs) fmt;
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
            rapids-cmake = self'.packages.rapids-cmake;
          };
          stdexec-build = pkgs.callPackage ./tests/stdexec/default.nix {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
            rapids-cmake = self'.packages.rapids-cmake;
          };
          cps-consumption = pkgs.callPackage ./tests/cps {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
          };
          # The cmake2nix package itself is built as part of `packages`;
          # `nix flake check` builds it via this alias on all systems.
          cmake2nix = self'.packages.cmake2nix;
        } // pkgs.lib.optionalAttrs (builtins ? outputOf) {
          # Opt-in only: present when dynamic-derivations is enabled
          # for this evaluation, absent (rather than broken) otherwise.
          dynamic-fetchcontent = pkgs.callPackage ./tests/dynamic {
            cmake = self'.packages.cmakeMinimal;
            cmakeDependencyHook = self'.packages.cmakeDependencyHook;
          };
        };

        devShells.default = pkgs.mkShell {
          shellHook = config.pre-commit.installationScript;
          packages = [
            self'.packages.cmakeMinimal
            self'.packages.cmake2nix
            pkgs.ninja
            pkgs.git
          ];
        };

        # Formatting configuration
        treefmt.config = {
          projectRootFile = "flake.nix";
          programs = {
            nixpkgs-fmt.enable = true;
            clang-format.enable = true;
          };
        };

        # Pre-commit hooks configuration
        pre-commit.settings = {
          hooks = {
            treefmt.enable = true;
            statix.enable = true;
            deadnix.enable = true;
            shellcheck.enable = true;
            ruff.enable = true;
          };
        };

        # Overlay (via easyOverlay). The CMake derivations are exposed
        # under non-conflicting names on purpose: overriding `cmake` /
        # `cmakeMinimal` in a consumer's nixpkgs can interfere with
        # stdenv bootstrap (notably xcbuild on Darwin). Consumers who
        # want that can alias the attributes themselves.
        overlayAttrs = {
          cmakeUnpatched = self'.packages.cmake;
          cmakeUnpatchedMinimal = self'.packages.cmakeMinimal;
        };
      };
      flake = {
        lib = import ./lib { inherit (inputs.nixpkgs) lib; };
        flakeModules.default = import ./modules/flake-parts.nix;
      };
    };
}
