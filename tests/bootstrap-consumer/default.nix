# The full `cmake` package must remain a working build tool for
# consumers: its shipped setup hook (the dependency hook, which
# provides the configure phase) has to keep working even though
# full cmake's *own* build no longer uses it (it self-bootstraps
# via ./bootstrap). Only `cmake` itself is given as input -- no
# hook is added explicitly -- so this fails if the shipped hook
# stops functioning.
{ stdenv
, cmake
, ninja
}:

stdenv.mkDerivation {
  pname = "bootstrap-consumer-test";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    cmake
    ninja
  ];

  cmakeFlags = [ "-GNinja" ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./hello | grep -qx hello-bootstrap
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp hello $out/bin/
    runHook postInstall
  '';

  meta.description = "Full cmake (self-bootstrapped) still ships working setup hooks";
}
