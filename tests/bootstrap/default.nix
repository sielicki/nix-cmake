# Bootstrap-parity properties (Linux-first scope):
#
# 1. The full `cmake` derivation must be buildable without any CMake:
#    no `cmakeMinimal`/`cmake` derivation among its inputs, and the
#    nix-cmake setup hooks must not be *activated* during its build
#    (they are shipped payload, referenced only via `setupHooks`).
#    It self-bootstraps via `./bootstrap`, mirroring nixpkgs, where
#    full CMake never depends on `cmakeMinimal` to build.
# 2. `cmakeMinimal` must be buildable with (essentially) only a
#    compiler: no ninja, no system libraries among its inputs.
# 3. `cmakeMinimal`'s runtime closure stays tiny and free of the
#    curl/OpenSSL-tier packages a bootstrap CMake must not depend on
#    (cf. the Darwin bootstrap's curl ban).
#
# (1)/(2) inspect the .drv files (passed as inputs, not built):
# input-derivation lists and env values name every build input.
# (3) inspects closureInfo for cmakeMinimal.
{ lib, pkgs, cmake, cmakeMinimal }:

let
  minimalClosure = pkgs.closureInfo { rootPaths = [ cmakeMinimal ]; };
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
pkgs.runCommand "bootstrap-properties"
{
  fullDrvPath = cmake.drvPath;
  minimalDrvPath = cmakeMinimal.drvPath;
} ''
  fail=0
  note() { echo "FAIL: $*" >&2; fail=1; }

  echo "== full cmake: no CMake needed to build it =="
  if grep -Eq -- '-cmakeMinimal-[^"]*\.drv|-cmake-[0-9][^"]*\.drv|-ninja-[^"]*\.drv' "$fullDrvPath"; then
    note "full cmake .drv has a cmake/ninja input derivation"
    grep -Eo -- '-[^"/]*-cmake[^"]*\.drv|-ninja-[^"]*\.drv' "$fullDrvPath" | sort -u >&2 || true
  fi
  for var in nativeBuildInputs depsBuildBuild propagatedNativeBuildInputs buildInputs; do
    val=$(grep -o "\"$var\",\"[^\"]*\"" "$fullDrvPath" || true)
    case "$val" in
      *cmakeMinimal*|*cmake-nix-*) note "full cmake $var activates a CMake/hook: $val" ;;
    esac
  done
  grep -q -- '"configureScript","./bootstrap"' "$fullDrvPath" \
    || note "full cmake does not configure via ./bootstrap"

  echo "== cmakeMinimal: compiler-only inputs =="
  banned='-ninja-|-curl-|-openssl-|-libidn2-|-libarchive-|-libuv-|-rhash-'
  ${lib.optionalString isLinux "banned=\"$banned|-libiconv-\""}
  if grep -Eq -- "$banned" "$minimalDrvPath"; then
    note "cmakeMinimal .drv mentions a non-compiler build input"
    grep -Eo -- '-(ninja|curl|openssl|libidn2|libarchive|libuv|rhash|libiconv)-[^",]*' "$minimalDrvPath" | sort -u >&2 || true
  fi

  echo "== cmakeMinimal runtime closure =="
  grep '^/nix/store' ${minimalClosure}/registration | sort -u
  count=$(grep '^/nix/store' ${minimalClosure}/registration | sort -u | wc -l)
  echo "closure size: $count"
  ${lib.optionalString isLinux ''
    [ "$count" -le 15 ] || note "cmakeMinimal closure has $count paths (> 15)"
  ''}
  # (libidn2/libunistring may legitimately appear: glibc itself
  # links them in current nixpkgs; cmake must not link them, which
  # the .drv input check above covers.)
  if grep -Eq -- '-(curl|openssl|perl|git|libssh2|krb5)-[0-9]' ${minimalClosure}/registration; then
    note "cmakeMinimal closure contains a bootstrap-banned package"
    grep -E -- '-(curl|openssl|perl|git|libssh2|krb5)-[0-9]' ${minimalClosure}/registration >&2 || true
  fi

  [ "$fail" -eq 0 ] || exit 1
  touch $out
''
