{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  pname = "rapids-cmake";
  version = "24.02.00"; # Example version

  src = fetchFromGitHub {
    owner = "rapidsai";
    repo = "rapids-cmake";
    rev = "v${version}";
    hash = "sha256-abl8pT81osBMcxJM/wtB8oBu1DK/lz5k/O1bzqCLPvY=";
  };

  # Inject our hook into the core configuration so it loads automatically
  installPhase = ''
    mkdir -p $out/share/cmake/rapids-cmake
    cp -r * $out/share/cmake/rapids-cmake/
    
    # Copy our hook
    cp ${./hook.cmake} $out/share/cmake/rapids-cmake/nix-rapids-hook.cmake
    
    # Append include to the main config file if it exists, or create a simple init
    # In rapids-cmake, the entry point is typically rapids-cmake-config.cmake or similar
    if [ -f $out/share/cmake/rapids-cmake/rapids-cmake-config.cmake ]; then
      echo "include(\''${CMAKE_CURRENT_LIST_DIR}/nix-rapids-hook.cmake)" >> $out/share/cmake/rapids-cmake/rapids-cmake-config.cmake
    fi
  '';

  meta = with lib; {
    description = "CMake integration for RAPIDS projects";
    homepage = "https://github.com/rapidsai/rapids-cmake";
    license = licenses.asl20;
  };
}
