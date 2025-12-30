{ lib }:

let
  # Parse a CMakeLists.txt file to extract FetchContent_Declare calls
  # This is a simple regex-based parser that handles basic cases
  # For complex cases, we'd need a proper CMake parser

  parseFetchContentDeclare = content:
    let
      # Match FetchContent_Declare with various formats
      # This regex captures:
      # 1. The dependency name
      # 2. GIT_REPOSITORY
      # 3. GIT_TAG or VERSION
      pattern = ''
        FetchContent_Declare\s*\(\s*
          ([a-zA-Z0-9_-]+)\s+                    # Dependency name
          (?:.*?)                                 # Optional other args
          (?:GIT_REPOSITORY|URL)\s+([^\s)]+)\s+ # Repository or URL
          (?:.*?)                                 # Optional other args
          (?:GIT_TAG|VERSION)\s+([^\s)]+)        # Version/tag
      '';

      # Extract all matches
      matches = builtins.match pattern content;
    in
    if matches != null then
      {
        name = builtins.elemAt matches 0;
        repository = builtins.elemAt matches 1;
        version = builtins.elemAt matches 2;
      }
    else
      null;

  # Parse all FetchContent declarations from a CMakeLists.txt file
  parseCMakeListsFile = path:
    let
      content = builtins.readFile path;

      # Split by FetchContent_Declare to find all declarations
      # This is a simplified approach - a full parser would handle nesting, comments, etc.
      declarations = lib.lists.filter (decl: decl != null)
        (map parseFetchContentDeclare (lib.splitString "FetchContent_Declare" content));
    in
    declarations;

in
{
  inherit parseFetchContentDeclare parseCMakeListsFile;
}
