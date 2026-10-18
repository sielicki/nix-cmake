{ lib }:

let
  # Parse a CPS requirement string. Forms (per CPS spec / CMake's
  # generator): ":component" (same package), "package:component",
  # or a bare "package" (component-less requirement).
  parseRequirement = req:
    let
      parts = lib.splitString ":" req;
    in
    if builtins.length parts == 2 && builtins.head parts == "" then
      { package = null; component = builtins.elemAt parts 1; }
    else if builtins.length parts == 2 then
      { package = builtins.head parts; component = builtins.elemAt parts 1; }
    else
      { package = req; component = null; };

  normalizeComponent = name: info: {
    inherit name;
    type = info.type or "interface";
    location = info.location or null;
    includes = info.includes or [ ];
    definitions = info.definitions or { };
    compileFeatures = info.compile_features or [ ];
    linkFlags = info.link_flags or [ ];
    linkLibraries = info.link_libraries or [ ];
    requires = map parseRequirement (info.requires or [ ]);
    raw = info;
  };

  normalize = content:
    let
      components = lib.mapAttrs normalizeComponent (content.components or { });

      # Package-level requirements: an explicit top-level `requires`
      # object when present, plus every external package referenced
      # by a component requirement.
      declared = lib.mapAttrs
        (name: info: {
          inherit name;
          version = info.version or null;
          compatVersion = info.compat_version or null;
          components = info.components or [ ];
          hints = info.hints or [ ];
        })
        (content.requires or { });

      externalRefs = lib.unique (lib.concatMap
        (c: map (r: r.package)
          (lib.filter (r: r.package != null) c.requires))
        (builtins.attrValues components));

      requires = declared // builtins.listToAttrs (map
        (name: {
          inherit name;
          value = {
            inherit name;
            version = null;
            compatVersion = null;
            components = [ ];
            hints = [ ];
          };
        })
        (lib.filter (name: !(declared ? ${name})) externalRefs));
    in
    {
      name = content.name or "unknown";
      version = content.version or null;
      compatVersion = content.compat_version or null;
      cpsVersion = content.cps_version or null;
      cpsPath = content.cps_path or null;
      configuration = content.configuration or null;
      defaultTargets = content.default_targets or [ ];
      inherit components requires;
      # External package names this package depends on, sorted.
      dependencies = lib.sort (a: b: a < b) (builtins.attrNames requires);
      # Backwards compatibility with the original prototype shape.
      targets = lib.mapAttrs
        (name: r: {
          inherit name;
          version = if r.version == null then "unknown" else r.version;
          inherit (r) components;
        })
        requires;
      raw = content;
    };

  /*
    parseCPSFile parses one .cps JSON file (root or appendix) into
    the normalized structure above. Real-world input is what CMake's
    install(PACKAGE_INFO) / CMAKE_INSTALL_EXPORTS_AS_PACKAGE_INFO
    generates (see docs/CPS-INTEGRATION.md).
  */
  # Note: reading a .cps file from a derivation output is
  # import-from-derivation, like the other discovery parsers. The
  # string context is discarded so results remain serialisable.
  parseCPSFile = path:
    normalize (builtins.fromJSON
      (builtins.unsafeDiscardStringContext (builtins.readFile path)));

  # Parse every .cps file in a directory (e.g. lib/cps/<name>),
  # returning { root, configurations } where root is the file without
  # a "configuration" field.
  parseCPSDir = dir:
    let
      entries = builtins.readDir dir;
      files = lib.filter (name: lib.hasSuffix ".cps" name) (builtins.attrNames entries);
      parsed = map (name: parseCPSFile (dir + "/${name}")) files;
      roots = lib.filter (p: p.configuration == null) parsed;
    in
    {
      root = if roots == [ ] then null else lib.head roots;
      configurations = lib.filter (p: p.configuration != null) parsed;
      all = parsed;
    };

  # Lock-file shaped view of a parsed CPS package's requirements:
  # [{ name, version }] with undeclared versions left null (callers
  # decide how strict to be; discovery/lock code uses "unknown").
  lockRequirements = cps:
    map
      (name: {
        inherit name;
        version = cps.requires.${name}.version;
      })
      cps.dependencies;

in
{
  inherit parseCPSFile parseCPSDir lockRequirements parseRequirement;
  # Original prototype name, kept for backwards compatibility.
  parseCPS = parseCPSFile;
}
