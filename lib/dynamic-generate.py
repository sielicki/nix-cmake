#!/usr/bin/env python3
"""Generate build.nix for a dynamic CMake build.

Reads configuration from environment variables (set by lib/dynamic.nix),
combines the CMake discovery log with cmake-lock.json, and writes a
self-contained Nix expression describing the real build. The caller
instantiates that expression with recursive Nix, and the resulting .drv
becomes the output of the (text-hashed) producer derivation.
"""

import json
import os
import re
import sys

IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_'-]*$")
ALLOWED_METHODS = {
    "fetchFromGitHub",
    "fetchFromGitLab",
    "fetchFromGitea",
    "fetchFromSourcehut",
    "fetchgit",
    "fetchurl",
    "fetchzip",
    "fetchsvn",
    "fetchhg",
}


def fail(msg):
    print(f"nix-cmake dynamic: error: {msg}", file=sys.stderr)
    sys.exit(1)


def nix_string(value):
    """Render a Python string as a Nix double-quoted string."""
    out = []
    for ch in value:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        else:
            out.append(ch)
    return '"' + "".join(out).replace("${", "\\${") + '"'


def nix_key(key):
    return key if IDENT_RE.match(key) else nix_string(key)


def nix_value(value):
    if isinstance(value, str):
        return nix_string(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, list):
        return "[ " + " ".join(nix_value(v) for v in value) + " ]"
    fail(f"unsupported lock file argument value: {value!r}")


def load_discovery_log(path):
    deps = []
    if not path or not os.path.isfile(path):
        return deps
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError as exc:
                fail(f"invalid discovery log line {line!r}: {exc}")
            if entry.get("name"):
                deps.append(entry)
    return deps


def load_lock(path):
    if not path:
        return {}
    if not os.path.isfile(path):
        fail(f"lock file not found: {path} (run discovery and commit cmake-lock.json)")
    with open(path, encoding="utf-8") as fh:
        lock = json.load(fh)
    deps = lock.get("dependencies") or {}
    if not isinstance(deps, dict):
        fail("lock file 'dependencies' must be an object")
    return deps


def render_fetcher(name, dep):
    method = dep.get("method")
    args = dep.get("args") or {}
    if method not in ALLOWED_METHODS:
        fail(
            f"dependency '{name}' has unsupported fetcher method {method!r}; "
            f"expected one of {sorted(ALLOWED_METHODS)}"
        )
    if not isinstance(args, dict) or not args:
        fail(f"dependency '{name}' is missing fetcher args in lock file")
    lines = [f"pkgs.{method} {{"]
    for key in sorted(args):
        lines.append(f"      {nix_key(key)} = {nix_value(args[key])};")
    lines.append("    }")
    return "\n".join(lines)


def main():
    pname = os.environ.get("DYNAMIC_PNAME", "")
    version = os.environ.get("DYNAMIC_VERSION", "0.0.0")
    src = os.environ.get("DYNAMIC_SRC", "")
    nixpkgs = os.environ.get("DYNAMIC_NIXPKGS", "")
    cmake = os.environ.get("DYNAMIC_CMAKE", "")
    hook = os.environ.get("DYNAMIC_DEPENDENCY_HOOK", "")
    output = os.environ.get("DYNAMIC_OUTPUT", "build.nix")
    cmake_flags = [f for f in os.environ.get("DYNAMIC_CMAKE_FLAGS", "").split("\n") if f]
    native_inputs = [p for p in os.environ.get("DYNAMIC_NATIVE_INPUTS", "").split(" ") if p]
    build_inputs = [p for p in os.environ.get("DYNAMIC_BUILD_INPUTS", "").split(" ") if p]
    try:
        extra_env = json.loads(os.environ.get("DYNAMIC_EXTRA_ENV", "") or "{}")
    except json.JSONDecodeError as exc:
        fail(f"invalid DYNAMIC_EXTRA_ENV JSON: {exc}")
    if not isinstance(extra_env, dict) or not all(
        isinstance(k, str) and isinstance(v, str) for k, v in extra_env.items()
    ):
        fail("DYNAMIC_EXTRA_ENV must be a JSON object of string -> string")
    do_check = os.environ.get("DYNAMIC_DO_CHECK", "") == "1"
    check_phase = os.environ.get("DYNAMIC_CHECK_PHASE", "")
    install_phase = os.environ.get("DYNAMIC_INSTALL_PHASE", "")

    if not pname or not src or not nixpkgs or not cmake:
        fail("missing required DYNAMIC_* environment configuration")

    discovered = load_discovery_log(os.environ.get("DYNAMIC_DISCOVERY_LOG", ""))
    lock_deps = load_lock(os.environ.get("DYNAMIC_LOCK_FILE", ""))

    lock_by_lower = {name.lower(): name for name in lock_deps}
    missing = []
    discovered_names = set()
    for entry in discovered:
        key = lock_by_lower.get(entry["name"].lower())
        if key is None:
            missing.append(entry["name"])
        else:
            discovered_names.add(key)
    if missing:
        fail(
            "discovered dependencies missing from lock file: "
            + ", ".join(sorted(set(missing)))
            + ". Update cmake-lock.json (see docs/DYNAMIC-DERIVATIONS.md)."
        )

    for name in sorted(set(lock_deps) - discovered_names):
        print(
            f"nix-cmake dynamic: note: lock dependency '{name}' was not seen "
            "during discovery; including it anyway (CPM/FetchContent_Populate "
            "dependencies may not appear in the discovery log)",
            file=sys.stderr,
        )

    print(
        f"nix-cmake dynamic: discovered {len(discovered)} dependencies, "
        f"lock provides {len(lock_deps)}",
        file=sys.stderr,
    )

    lines = []
    lines.append("# Generated by nix-cmake (dynamic derivations). Do not edit.")
    lines.append("let")
    lines.append(f"  pkgs = import {nixpkgs} {{ }};")
    lines.append("in")
    lines.append("pkgs.stdenv.mkDerivation {")
    lines.append(f"  pname = {nix_string(pname)};")
    lines.append(f"  version = {nix_string(version)};")
    lines.append(f"  src = builtins.storePath {nix_string(src)};")
    lines.append("  nativeBuildInputs = [")
    lines.append(f"    (builtins.storePath {nix_string(cmake)})")
    lines.append("    pkgs.ninja")
    if hook:
        lines.append(f"    (builtins.storePath {nix_string(hook)})")
    for path in native_inputs:
        lines.append(f"    (builtins.storePath {nix_string(path)})")
    lines.append("  ];")
    if build_inputs:
        lines.append("  buildInputs = [")
        for path in build_inputs:
            lines.append(f"    (builtins.storePath {nix_string(path)})")
        lines.append("  ];")
    all_flags = ["-GNinja"] + cmake_flags
    lines.append(
        "  cmakeFlags = [ " + " ".join(nix_string(f) for f in all_flags) + " ];"
    )
    for name in sorted(lock_deps):
        env_name = "FETCHCONTENT_SOURCE_DIR_" + name.upper()
        lines.append(f"  {nix_string(env_name)} = {render_fetcher(name, lock_deps[name])};")
    for key in sorted(extra_env):
        lines.append(f"  {nix_key(key)} = {nix_string(extra_env[key])};")
    if do_check:
        lines.append("  doCheck = true;")
    if check_phase:
        lines.append(f"  checkPhase = {nix_string(check_phase)};")
    if install_phase:
        lines.append(f"  installPhase = {nix_string(install_phase)};")
    lines.append("}")
    lines.append("")

    with open(output, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    print(f"nix-cmake dynamic: wrote {output}", file=sys.stderr)


if __name__ == "__main__":
    main()
