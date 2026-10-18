# Pure-evaluation unit tests for the library (no builds). Evaluation
# throws with the failure list if any test fails.
{ lib, pkgs }:

let
  nix-cmake = import ../lib { inherit lib; };

  results = lib.runTests {
    testParseQuotedFetchContent = {
      expr = map (d: { inherit (d) name repository version; })
        (nix-cmake.parseCMakeLists.parseCMakeListsFile ./multi-dependency/CMakeLists.txt);
      expected = [
        { name = "fmt"; repository = "https://github.com/fmtlib/fmt.git"; version = "10.2.1"; }
        { name = "nlohmann_json"; repository = "https://github.com/nlohmann/json.git"; version = "v3.11.3"; }
        { name = "Catch2"; repository = "https://github.com/catchorg/Catch2.git"; version = "v3.5.2"; }
      ];
    };

    testCpsRequirementParsing = {
      expr = map nix-cmake.cps.parseRequirement [ ":fmt" "fmt:fmt" "Threads" ];
      expected = [
        { package = null; component = "fmt"; }
        { package = "fmt"; component = "fmt"; }
        { package = "Threads"; component = null; }
      ];
    };

    testProjectParse = {
      expr = nix-cmake.generators.parseCMakeLists ../pkgs/cmake2nix/CMakeLists.txt;
      expected = { pname = "cmake2nix"; version = "0.2.0"; };
    };
  };
in
if results == [ ] then
  pkgs.runCommand "lib-tests" { } "touch $out"
else
  throw ("lib tests failed: " + builtins.toJSON results)
