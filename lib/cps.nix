{ lib }:

let
  /*
    parseCPS parses a Common Package Specification (CPS) JSON file
    and returns a normalized dependency structure for Nix-CMake.
  */
  parseCPS = path:
    let
      content = builtins.fromJSON (builtins.readFile path);

      # Extract requirement specifications
      # (In a real CPS file, these are in the 'requirements' or 'requires' fields)
      requires = content.requires or { };

      # Map to our internal representation
      # CPS targets often map to CMake imported targets
      mappedTargets = lib.mapAttrs
        (name: info: {
          inherit name;
          version = info.version or "unknown";
        })
        requires;

    in
    {
      inherit (content) name version;
      targets = mappedTargets;
      raw = content;
    };

in
{
  inherit parseCPS;
}
