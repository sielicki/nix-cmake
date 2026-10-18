{ lib }:

let
  # Parse a CMakeLists.txt file to extract FetchContent_Declare calls.
  #
  # NOTE: This is a best-effort regex parser for simple, literal
  # declarations. The supported way to enumerate dependencies is
  # discovery (see workspace.discoverDependencies and lib/dynamic.nix),
  # which asks CMake itself. This parser cannot handle variables,
  # nested parentheses, or conditional declarations.
  #
  # Nix's builtins.match uses POSIX extended regular expressions:
  # `.*` also matches newlines, and character classes such as
  # `[[:space:]]` must be used instead of `\s`.

  # Extract `<keyword> <value>` from a declaration argument string.
  argValue = keyword: args:
    let
      m = builtins.match ".*${keyword}[[:space:]]+([^[:space:])]+).*" args;
    in
    if m == null then null else lib.head m;

  # Parse one FetchContent_Declare(...) call. Accepts either the full
  # call text or the text following the `FetchContent_Declare` keyword.
  parseFetchContentDeclare = text:
    let
      full = builtins.match
        ".*FetchContent_Declare[[:space:]]*\\([[:space:]]*([A-Za-z0-9_-]+)([^)]*)\\).*"
        text;
      m =
        if full != null then full
        else builtins.match "[[:space:]]*\\([[:space:]]*([A-Za-z0-9_-]+)([^)]*)\\).*" text;
    in
    if m == null then null
    else
      let
        name = builtins.elemAt m 0;
        args = builtins.elemAt m 1;
        gitRepository = argValue "GIT_REPOSITORY" args;
        url = argValue "URL" args;
        gitTag = argValue "GIT_TAG" args;
      in
      {
        inherit name gitRepository url gitTag;
        # Backwards-compatible aliases.
        repository = if gitRepository != null then gitRepository else url;
        version = gitTag;
      };

  # Parse all FetchContent declarations from a CMakeLists.txt file.
  parseCMakeListsFile = path:
    let
      content = builtins.readFile path;
      chunks = builtins.tail (lib.splitString "FetchContent_Declare" content);
    in
    lib.filter (decl: decl != null)
      (map parseFetchContentDeclare chunks);

in
{
  inherit parseFetchContentDeclare parseCMakeListsFile;
}
