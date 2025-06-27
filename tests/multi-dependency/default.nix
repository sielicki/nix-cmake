{ stdenv
, cmake
, cmakeDependencyHook
, ninja
, fmt
, nlohmann_json
, catch2_3
}:

stdenv.mkDerivation {
  pname = "multi-dependency-test";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    cmake
    cmakeDependencyHook
    ninja
  ];

  # Provide all dependencies as pre-built CMake packages
  # The dependency provider will intercept FetchContent_MakeAvailable calls
  buildInputs = [
    fmt
    nlohmann_json
    catch2_3
  ];

  cmakeFlags = [ "-GNinja" ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./test_multi
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp test_multi $out/bin/
    runHook postInstall
  '';

  meta = {
    description = "Test FetchContent with multiple dependencies (fmt, nlohmann_json, Catch2)";
  };
}
