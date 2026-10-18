{ pkgs, cmake, cmakeDependencyHook }:

let
  call = f: pkgs.callPackage f { inherit cmake cmakeDependencyHook; };
in
{
  fmt = call ./fmt.nix;
  spdlog = call ./spdlog.nix;
  nlohmann_json = call ./nlohmann_json.nix;
  catch2 = call ./catch2.nix;
  pugixml = call ./pugixml.nix;
  brotli = call ./brotli.nix;
  zstd = call ./zstd.nix;
  simdjson = call ./simdjson.nix;
  tl-expected = call ./tl-expected.nix;
  abseil-cpp = call ./abseil-cpp.nix;
  googletest = call ./googletest.nix;
  yaml-cpp = call ./yaml-cpp.nix;
  cli11 = call ./cli11.nix;
  fast-float = call ./fast-float.nix;
}
