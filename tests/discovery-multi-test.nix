{ stdenv
, cmake
, cmakeDependencyHook
, ninja
, git
}:

stdenv.mkDerivation {
  pname = "discovery-multi-test";
  version = "0.1.0";

  src = ./multi-dependency;

  nativeBuildInputs = [
    cmake
    cmakeDependencyHook
    ninja
    git
  ];

  # Don't provide any buildInputs - we want to discover all dependencies
  buildInputs = [ ];

  # Set discovery mode
  NIX_CMAKE_DISCOVERY_MODE = "1";

  preConfigure = ''
    # Use a unique log file in the build directory
    export NIX_CMAKE_DISCOVERY_LOG=$PWD/cmake-discovery.log

    echo "=== Multi-Dependency Discovery Test ==="
    echo "NIX_CMAKE_DISCOVERY_MODE=$NIX_CMAKE_DISCOVERY_MODE"
    echo "NIX_CMAKE_DISCOVERY_LOG=$NIX_CMAKE_DISCOVERY_LOG"
    echo ""
  '';

  postConfigure = ''
    echo ""
    echo "=== Discovery log contents ==="
    if [ -f "$NIX_CMAKE_DISCOVERY_LOG" ]; then
      cat "$NIX_CMAKE_DISCOVERY_LOG"
      echo ""
      echo "=== Discovery successful ==="
    else
      echo "ERROR: No discovery log found"
      exit 1
    fi
  '';

  # Don't build
  dontBuild = true;

  installPhase = ''
    mkdir -p $out
    cp "$NIX_CMAKE_DISCOVERY_LOG" $out/cmake-discovery.log
    echo "Discovery log saved to $out/cmake-discovery.log"
  '';

  meta = {
    description = "Test CMake dependency discovery with multiple dependencies";
  };
}
