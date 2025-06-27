{ stdenv
, cmake
, cmakeDependencyHook
, ninja
, fmt
}:

stdenv.mkDerivation {
  pname = "simple-fetchcontent-test";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    cmake
    cmakeDependencyHook
    ninja
  ];

  # Provide fmt as a pre-built CMake package
  # The dependency provider will intercept FetchContent_MakeAvailable(fmt)
  # and redirect to find_package(fmt)
  buildInputs = [
    fmt
  ];

  cmakeFlags = [ "-GNinja" ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./test_fmt
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp test_fmt $out/bin/
    runHook postInstall
  '';

  meta = {
    description = "Test FetchContent interception with fmt library";
  };
}
