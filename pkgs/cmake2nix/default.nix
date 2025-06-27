{ lib, stdenv, makeWrapper, nix, coreutils, nix-cmake-lib }:

stdenv.mkDerivation {
  pname = "cmake2nix";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp cmake2nix.sh $out/bin/cmake2nix
    chmod +x $out/bin/cmake2nix

    # Substitute the library path
    # We point to the local copy we're about to make
    substituteInPlace $out/bin/cmake2nix \
      --replace-quiet "@nix_cmake_lib@" "$out/share/nix-cmake/lib"

    mkdir -p $out/share/nix-cmake
    cp -r ${nix-cmake-lib} $out/share/nix-cmake/lib

    wrapProgram $out/bin/cmake2nix \
      --prefix PATH : ${lib.makeBinPath [ nix coreutils ]}
  '';

  meta = with lib; {
    description = "A CLI for managing Nix-CMake projects";
    license = licenses.asl20;
    maintainers = [ ];
  };
}
