# setup_genie_incl.sh -- the GENIE + INCL++ environment of this workspace. Source it in every new
# shell (bash):
#     source /path/to/genie-install/build-genie-incl-spack/setup_genie_incl.sh
# It sources spack-env.sh, written once by `bash scripts/setup_deps.sh` (the only step that runs
# spack): the DUNE CVMFS packages (ROOT, Pythia8, LHAPDF, log4cpp, GSL, CMake, gcc 12.5) and the
# local Boost, with PATH-like variables prepended. On top it sets the GENIE contract:
# GENIE, XSECSPLINEDIR, PYTHIA8DATA, INCLXX_DIR, INCLXX_DATA_DIR, PATH, LD_LIBRARY_PATH.
# `bash setup_genie_incl.sh --print` prints the result. Needs /cvmfs/dune.opensciencegrid.org.
_gi_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$_gi_root/spack-env.sh" ]; then
  echo "setup_genie_incl.sh: $_gi_root/spack-env.sh is missing -- run once: bash $_gi_root/scripts/setup_deps.sh" >&2
  return 1 2>/dev/null || exit 1
fi
# the spack part only once per shell (re-sourcing after a rebuild must not stack PATH entries)
if [ "${GI_ENV_FILE:-}" != "$_gi_root/spack-env.sh" ]; then . "$_gi_root/spack-env.sh"; fi
[ -d "$GI_PREFIX_ROOT" ] || echo "setup_genie_incl.sh: WARNING: $GI_PREFIX_ROOT not found (is /cvmfs/dune.opensciencegrid.org mounted?)" >&2

export GENIE="$_gi_root/Generator"          # GENIE source + in-tree install (bin/, lib/, config/)
export XSECSPLINEDIR="$_gi_root/data"      # where GENIE looks for cross-section splines
export PYTHIA8DATA="$GI_PREFIX_PYTHIA8/share/Pythia8/xmldoc"
# _gi_prepend VAR DIR: put DIR in front of the colon-separated list VAR unless it is already in it
_gi_prepend() {
  eval "_gi_cur=\${$1:-}"
  case ":$_gi_cur:" in *":$2:"*) ;; *) eval "export $1=\"$2\${$1:+:\$$1}\"" ;; esac
}
_gi_prepend PATH "$GENIE/bin"
# GENIE's apps are linked with -Wl,--no-undefined and no rpath: the loader finds libGPhDcy.so,
# libpythia8.so, libstdc++.so.6 of gcc 12.5, ... only through LD_LIBRARY_PATH (spack-env.sh
# already holds the dependency and gcc-runtime directories).
_gi_prepend LD_LIBRARY_PATH "$GENIE/lib"
# INCL++ (built by `bash scripts/build_inclxx.sh` into ./inclxx): GENIE's INCL interface reads
# INCLXX_DIR / INCLXX_DATA_DIR at run time; the INCL++ libraries carry no rpath and reference each other.
if [ -f "$_gi_root/inclxx/lib/libINCL_Physics.so" ]; then
  export INCLXX_DIR="$_gi_root/inclxx"
  export INCLXX_DATA_DIR="$INCLXX_DIR/share"
  _gi_prepend PATH "$INCLXX_DIR/bin"
  _gi_prepend LD_LIBRARY_PATH "$INCLXX_DIR/lib"
fi
if [ "${1:-}" = "--print" ]; then
  for v in GENIE XSECSPLINEDIR ROOTSYS PYTHIA8DATA INCLXX_DIR INCLXX_DATA_DIR CC CXX FC GI_DUNE_SPACK \
           GI_PREFIX_GCC GI_PREFIX_GCC_RUNTIME GI_PREFIX_CMAKE GI_PREFIX_ROOT GI_PREFIX_PYTHIA8 GI_PREFIX_LHAPDF \
           GI_PREFIX_LOG4CPP GI_PREFIX_GSL GI_PREFIX_LIBXML2 GI_PREFIX_BOOST PATH LD_LIBRARY_PATH; do
    eval "printf '%s=%s\n' \"$v\" \"\${$v:-}\""
  done
fi
unset _gi_root _gi_cur; unset -f _gi_prepend
