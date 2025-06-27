{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
      ];
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      perSystem = { config, final, self', inputs', pkgs, system, ... }: {
        overlayAttrs = {
          cmakeToolchainHook = final.callPackage ./pkgs/cmake-toolchain-hook { };
          cmakeDependencyHook = (final.callPackage ./pkgs/cmake-dependency-hook { }).setupHook;
          cmake = final.callPackage ./pkgs/cmake { };
          cmakeMinimal = final.callPackage ./pkgs/cmake/bootstrap.nix {};
          xcbuild = (pkgs.xcbuild.override {
            cmake = final.cmakeMinimal;
          }).overrideAttrs (prev: {
            cmakeFlags = (prev.cmakeFlags or []) ++ [
                "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
            ];
            nativeBuildInputs = (prev.nativeBuildInputs or []) ++ [ final.cmakeToolchainHook ];
            buildInputs = (prev.buildInputs or []) ++ [
                (final.lib.getDev final.zlib)
                (final.lib.getLib final.zlib)
                final.libpng
                final.libxml2
            ];
          });
          brotli = pkgs.brotli.override {
            cmake = final.cmakeMinimal;
          };
          #curl = final.callPackage ./pkgs/curl {};
          #cppdap = final.callPackage ./pkgs/cppdap {};
          #jsoncpp = final.callPackage ./pkgs/jsoncpp {};
        };
        packages.default = final.cmake;
        packages.cmakeMinimal = final.cmakeMinimal;
      };
      flake = {
      };
    };
}
