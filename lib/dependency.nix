{ lib }:

let
  # Loads a discovery log file (JSON-per-line) and returns a list of attribute sets
  loadDiscoveryLog = path:
    let
      content = builtins.readFile path;
      lines = lib.splitString "\n" content;
      nonEmptyLines = lib.filter (l: l != "" && l != null) lines;
    in
    map (l: builtins.fromJSON (builtins.unsafeDiscardStringContext l)) nonEmptyLines;

  # Coerces a dependency entry into a Nix fetcher call specification
  deriveFetcher = dep:
    if dep ? gitRepository && dep.gitRepository != "" then
      {
        type = "github"; # Generic git-like for now
        method = "fetchgit";
        args = {
          url = dep.gitRepository;
          rev = if dep ? gitTag && dep.gitTag != "" then dep.gitTag else "HEAD";
          # Use a placeholder hash that triggers a hash mismatch error with the actual hash
          hash = dep.hash or lib.fakeHash;
        };
      }
    else if dep ? url && dep.url != "" then
      {
        type = "url";
        method = "fetchurl";
        args = {
          inherit (dep) url;
          hash = dep.hash or lib.fakeHash;
        };
      }
    else
    # Local SOURCE_DIR dependencies and entries with no fetchable
    # location cannot become Nix fetchers.
      null;

  # Generates a list of fetcher specifications from a discovery log
  generateFetcherSpecs = logPath:
    let
      deps = loadDiscoveryLog logPath;
    in
    lib.filter (f: f != null) (map deriveFetcher deps);

  # Generates a standardized lock file structure from a discovery log
  generateLockFromLog = logPath:
    let
      deps = loadDiscoveryLog logPath;
      # Dependencies without a derivable fetcher (e.g. no git URL) cannot
      # become lock entries; drop them instead of crashing on `null // ...`.
      fetchable = lib.filter (dep: deriveFetcher dep != null) deps;
      # Create an attrset of dependencies indexed by name
      lockDeps = builtins.listToAttrs (map
        (dep: {
          inherit (dep) name;
          value = (deriveFetcher dep) // {
            inherit (dep) name;
            version = dep.version or "unknown";
            # Keep original metadata for reference
            metadata = builtins.removeAttrs dep [ "name" "hash" ];
          };
        })
        fetchable);
    in
    {
      version = "1.0";
      dependencies = lockDeps;
    };

in
{
  inherit loadDiscoveryLog deriveFetcher generateFetcherSpecs generateLockFromLog;
}
