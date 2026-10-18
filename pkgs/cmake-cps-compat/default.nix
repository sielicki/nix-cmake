{ lib, runCommand }:

# CPS descriptions for packages CMake provides only as Find modules.
# Generated .cps files for ordinary libraries routinely require
# "Threads:Threads", but no Threads.cps exists anywhere, which makes
# such CPS packages unusable. This package fills that gap (and can
# grow descriptions for other module-only packages over time).
runCommand "cmake-cps-compat-0.1.0"
{
  meta = {
    description = "CPS descriptions for module-only CMake packages (Threads)";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
} ''
  mkdir -p $out/share/cps/Threads
  cp ${./Threads.cps} $out/share/cps/Threads/Threads.cps
''
