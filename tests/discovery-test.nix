{ stdenv
, cmake
, cmakeDependencyHook
, ninja
, git
}:

stdenv.mkDerivation {
  pname = "discovery-mode-test";
  version = "0.1.0";

  src = ./simple-fetchcontent;

  nativeBuildInputs = [
    cmake
    cmakeDependencyHook
    ninja
    git # Needed for FetchContent to actually attempt to download
  ];

  # Don't provide any buildInputs - we want to see what gets discovered
  buildInputs = [ ];

  # Set discovery mode environment variables
  NIX_CMAKE_DISCOVERY_MODE = "1";

  preConfigure = ''
    # Use a unique log file in the build directory
    export NIX_CMAKE_DISCOVERY_LOG=$PWD/cmake-discovery.log

    echo "=== Discovery Mode Test (v3) ==="
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
      echo "ERROR: No discovery log found at $NIX_CMAKE_DISCOVERY_LOG"
      ls -la
      exit 1
    fi
  '';

  # Don't build - discovery only happens during configure
  dontBuild = true;

  installPhase = ''
    mkdir -p $out
    if [ -f "$NIX_CMAKE_DISCOVERY_LOG" ]; then
      cp "$NIX_CMAKE_DISCOVERY_LOG" $out/cmake-discovery.log
      echo "Discovery log saved to $out/cmake-discovery.log"
    else
      # Fallback to build directory
      if [ -f "$PWD/cmake-discovery.log" ]; then
        cp "$PWD/cmake-discovery.log" $out/cmake-discovery.log
        echo "Discovery log saved from build dir to $out/cmake-discovery.log"
      else
        touch $out/no-log-found
        echo "No discovery log was generated"
      fi
    fi
  '';

  meta = {
    description = "Test CMake dependency discovery mode";
  };
}
