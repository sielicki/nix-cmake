{ lib }:

let
  /*
    CPM package-lock.cmake format:

    # CPM Package Lock
    # This file should be committed to version control

    CPMDeclarePackage(fmt
      VERSION 10.2.1
      GITHUB_REPOSITORY fmtlib/fmt
      EXCLUDE_FROM_ALL YES
    )

    CPMDeclarePackage(nlohmann_json
      VERSION 3.11.3
      URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz
      URL_HASH SHA256=...
    )
  */

  # Parse a single CPMDeclarePackage call
  parseCPMPackage = text:
    let
      # Match: CPMDeclarePackage(name ...options...)
      nameMatch = builtins.match ".*CPMDeclarePackage\\([ \n]*([a-zA-Z0-9_-]+)[ \n]+(.*)\\).*" text;
    in
    if nameMatch == null then null
    else
      let
        name = builtins.elemAt nameMatch 0;
        optionsText = builtins.elemAt nameMatch 1;

        # Extract VERSION
        versionMatch = builtins.match ".*VERSION[ \n]+([^ \n]+).*" optionsText;
        version = if versionMatch != null then builtins.elemAt versionMatch 0 else null;

        # Extract GITHUB_REPOSITORY
        ghRepoMatch = builtins.match ".*GITHUB_REPOSITORY[ \n]+([^ \n]+).*" optionsText;
        githubRepo = if ghRepoMatch != null then builtins.elemAt ghRepoMatch 0 else null;

        # Extract GIT_REPOSITORY
        gitRepoMatch = builtins.match ".*GIT_REPOSITORY[ \n]+([^ \n]+).*" optionsText;
        gitRepository = if gitRepoMatch != null then builtins.elemAt gitRepoMatch 0 else null;

        # Extract GIT_TAG
        gitTagMatch = builtins.match ".*GIT_TAG[ \n]+([^ \n]+).*" optionsText;
        gitTag = if gitTagMatch != null then builtins.elemAt gitTagMatch 0 else null;

        # Extract URL
        urlMatch = builtins.match ".*URL[ \n]+([^ \n]+).*" optionsText;
        url = if urlMatch != null then builtins.elemAt urlMatch 0 else null;

        # Extract URL_HASH (kept as the raw hex digest; see cpmToLockFormat
        # for why it is not mislabelled as an SRI hash)
        urlHashMatch = builtins.match ".*URL_HASH[ \n]+SHA256=([a-fA-F0-9]+).*" optionsText;
        urlHash = if urlHashMatch != null then builtins.elemAt urlHashMatch 0 else null;

      in
      {
        inherit name version;
        githubRepository = githubRepo;
        inherit gitRepository;
        inherit gitTag;
        inherit url;
        inherit urlHash;
        # Backwards-compatible alias (hex digest, not SRI).
        hash = urlHash;
      };

  # Parse entire package-lock.cmake file
  parsePackageLockCMake = path:
    let
      content = builtins.readFile path;
      # Split on CPMDeclarePackage to get each package
      parts = lib.splitString "CPMDeclarePackage" content;
      # Skip the first part (before any CPMDeclarePackage)
      packageTexts = builtins.tail parts;
      # Parse each package
      packages = map (text: parseCPMPackage ("CPMDeclarePackage" + text)) packageTexts;
      # Filter out nulls
      validPackages = lib.filter (p: p != null) packages;
    in
    validPackages;

  # Convert CPM package to nix-cmake lock format
  cpmToLockFormat = cpmPkg:
    let
      # `x or y` only falls back when the attribute is missing, not when
      # it is null, so nullable fields need explicit handling.
      firstNonNull = lib.findFirst (v: v != null) null;
      rev = firstNonNull [ cpmPkg.version cpmPkg.gitTag "HEAD" ];
      version = firstNonNull [ cpmPkg.version cpmPkg.gitTag "unknown" ];
      urlHash = cpmPkg.urlHash or cpmPkg.hash or null;

      fetcher =
        if cpmPkg.githubRepository != null then
          let
            parts = lib.splitString "/" cpmPkg.githubRepository;
          in
          if builtins.length parts != 2 then null
          else {
            method = "fetchFromGitHub";
            args = {
              owner = builtins.elemAt parts 0;
              repo = builtins.elemAt parts 1;
              inherit rev;
              # CPM locks carry no archive hash for git dependencies;
              # the placeholder fails with the correct hash on first build.
              hash = lib.fakeHash;
            };
          }
        else if cpmPkg.gitRepository != null then {
          method = "fetchgit";
          args = {
            url = cpmPkg.gitRepository;
            inherit rev;
            hash = lib.fakeHash;
          };
        }
        else if cpmPkg.url != null then {
          method = "fetchurl";
          # URL_HASH is a hex digest. It is passed through as the legacy
          # `sha256` (hex/base32) argument; labelling it `sha256-<hex>`
          # would produce an invalid SRI hash (SRI payloads are base64).
          args = { inherit (cpmPkg) url; } // (
            if urlHash != null then { sha256 = urlHash; }
            else { hash = lib.fakeHash; }
          );
        }
        else null;
    in
    if fetcher == null then null
    else {
      inherit (cpmPkg) name;
      inherit version;
      inherit (fetcher) method args;
      metadata = {
        source = "cpm-package-lock";
        inherit (cpmPkg) githubRepository gitRepository gitTag url;
      };
    };

  # Load CPM package lock and convert to cmake-lock.json format
  loadCPMPackageLock = path:
    let
      cpmPackages = parsePackageLockCMake path;
      lockPackages = map cpmToLockFormat cpmPackages;
      validPackages = lib.filter (p: p != null) lockPackages;
      packagesAttrSet = builtins.listToAttrs (map
        (pkg: {
          inherit (pkg) name;
          value = pkg;
        })
        validPackages);
    in
    {
      version = "1.0";
      source = "cpm-package-lock";
      dependencies = packagesAttrSet;
    };

in
{
  inherit parseCPMPackage parsePackageLockCMake cpmToLockFormat loadCPMPackageLock;
}
