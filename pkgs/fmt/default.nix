{ stdenv
, cmake
, fetchFromGitHub
, ninja
}:

stdenv.mkDerivation rec {
  pname = "fmt";
  version = "10.2.1";

  src = fetchFromGitHub {
    owner = "fmtlib";
    repo = "fmt";
    rev = version;
    hash = "sha256-pEltGLAHLZ3xypD/Ur4dWPWJ9BGVXwqQyKcDWVmC3co=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  cmakeFlags = [
    "-GNinja"
    "-DFMT_TEST=OFF"
    "-DFMT_DOC=OFF"
  ];

  # Don't use custom configure phase - use standard CMake
  dontUseCmakeBuildDir = false;

  meta = {
    description = "A modern formatting library";
    homepage = "https://fmt.dev";
  };
}
