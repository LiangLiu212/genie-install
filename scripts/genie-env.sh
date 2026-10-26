# GENIE environment contract for the pixi env. Sourced automatically by pixi
# ([activation] scripts in pixi.toml) for every `pixi run` and `pixi shell`;
# `bash scripts/genie-env.sh --print` prints the resulting variables.
#
# Everything is derived from two roots:
#   PIXI_PROJECT_ROOT  this checkout (set by pixi during activation)
#   CONDA_PREFIX       the pixi environment holding ROOT, Pythia8, LHAPDF, ...
_gi_root="${PIXI_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"

export GENIE="${_gi_root}/Generator"          # GENIE source + in-tree install (bin/, lib/, config/)
export XSECSPLINEDIR="${_gi_root}/data"      # where GENIE looks for cross-section splines
export ROOTSYS="${CONDA_PREFIX}"
export PYTHIA8DATA="${CONDA_PREFIX}/share/Pythia8/xmldoc"

case ":${PATH}:" in *":${GENIE}/bin:"*) ;; *) export PATH="${GENIE}/bin:${PATH}" ;; esac
# GENIE's apps are linked with -Wl,--no-undefined and no rpath, and libGPhDcy.so
# needs libpythia8.so: both ld (at build time) and the loader (at run time) find
# the conda libraries only through LD_LIBRARY_PATH.
_gi_ld="${GENIE}/lib:${CONDA_PREFIX}/lib"
case ":${LD_LIBRARY_PATH:-}:" in *":${_gi_ld}:"*) ;; *) export LD_LIBRARY_PATH="${_gi_ld}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" ;; esac
unset _gi_root _gi_ld

if [ "${1:-}" = "--print" ]; then
  for v in GENIE XSECSPLINEDIR ROOTSYS PYTHIA8DATA CONDA_PREFIX PATH LD_LIBRARY_PATH CXX CC; do
    printf '%s=%s\n' "$v" "$(eval "printf '%s' \"\${$v:-}\"")"
  done
fi
