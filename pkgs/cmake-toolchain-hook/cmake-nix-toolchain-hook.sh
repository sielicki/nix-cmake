_cmakeToolchainSetupHook() {
  if [[ -z "${CMAKE_TOOLCHAIN_FILE:-}" ]]; then
    export CMAKE_TOOLCHAIN_FILE="@cmakeToolchainPath@"
    echo "Using Nix CMake toolchain: $CMAKE_TOOLCHAIN_FILE"
  fi
}


if [[ -z "${dontUseCmakeToolchain:-}" ]]; then
  preConfigureHooks+=(_cmakeToolchainSetupHook)
fi
