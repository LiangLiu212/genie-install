#!/usr/bin/env bash
# build_genie.sh -- clone (if needed), configure and build GENIE Generator against the DUNE CVMFS
# Spack packages (ROOT, Pythia8, LHAPDF6, log4cpp, GSL, the system libxml2) and, when ./inclxx
# exists, the INCL++ interface with the local Boost. Run it after `source setup_genie_incl.sh`:
#   bash scripts/build_genie.sh
#
# Knobs (environment variables, all optional):
#   GENIE_GIT_URL          repository to clone            default https://github.com/LiangLiu212/Generator.git
#   GENIE_GIT_REF          branch or tag to clone         default feature/incl-v3_8 (GENIE master + the INCL interface)
#   GENIE_NJOBS            parallel jobs per make target  default: the cgroup CPU quota, else nproc
#   GENIE_CONFIGURE_EXTRA  extra ./configure flags, e.g. "--enable-boosted-dark-matter"
#   GENIE_ENABLE_INCL      1 = build the INCL++ interface against ./inclxx (default: 1 if ./inclxx
#                          exists, built by `bash scripts/build_inclxx.sh`; 0 = never)
#   GENIE_POST_CLEAN=1     delete object files and .git after a successful build
#
# Build pattern: GENIE's top-level `make -jN` races the generated headers (GBuild.h)
# against the compiles, so the prep targets run serially, each library group gets its
# own -jN make, and a final serial `make` proves nothing is left to build.
set -euo pipefail
log() { printf '\n=== %s  [%s]\n' "$*" "$(date '+%F %T')"; }
die() { printf 'build_genie.sh: ERROR: %s\n' "$*" >&2; exit 1; }
default_jobs() {  # `nproc` honours OMP_NUM_THREADS (1 on the Fermilab EAF); the cgroup quota is the truth
  local q p
  if read -r q p < /sys/fs/cgroup/cpu.max 2>/dev/null && [[ "$q" != max ]]; then echo $(( (q + p - 1) / p )); else env -u OMP_NUM_THREADS nproc; fi
}
libdir() { if ls "$1"/lib64/*.so* >/dev/null 2>&1; then echo "$1/lib64"; else echo "$1/lib"; fi; }  # spack: lib; the system libxml2: lib64

: "${GENIE:?GENIE is not set -- first: source setup_genie_incl.sh}"
for v in GI_PREFIX_GCC GI_PREFIX_GCC_RUNTIME GI_PREFIX_ROOT GI_PREFIX_PYTHIA8 GI_PREFIX_LHAPDF GI_PREFIX_LOG4CPP GI_PREFIX_LIBXML2 GI_PREFIX_BOOST PYTHIA8DATA; do
  [[ -n "${!v:-}" ]] || die "$v is not set -- first: source setup_genie_incl.sh"
done
SRC="$GENIE"
ROOT_DIR="$(cd "$(dirname "$SRC")" && pwd)"
GIT_URL="${GENIE_GIT_URL:-https://github.com/LiangLiu212/Generator.git}"
GIT_REF="${GENIE_GIT_REF:-feature/incl-v3_8}"
NJOBS="${GENIE_NJOBS:-$(default_jobs)}"
INCL_PREFIX="$ROOT_DIR/inclxx"
if [[ -z "${GENIE_ENABLE_INCL:-}" ]]; then
  if [[ -f "$INCL_PREFIX/lib/libINCL_Physics.so" ]]; then GENIE_ENABLE_INCL=1; else GENIE_ENABLE_INCL=0; fi
fi
T0=$(date +%s)

log "preflight"
for tool in root-config gsl-config g++ gcc make git perl readelf; do
  command -v "$tool" >/dev/null || die "$tool not found on PATH (source setup_genie_incl.sh)"
done
case "$(command -v g++)" in "$GI_PREFIX_GCC"/*) ;; *) die "g++ on PATH is $(command -v g++), not the spack gcc 12.5 under $GI_PREFIX_GCC" ;; esac
[[ "$(root-config --has-mathmore)" == yes ]] || die "ROOT was built without MathMore"
P8_LIB=$(libdir "$GI_PREFIX_PYTHIA8"); LHAPDF_LIB=$(libdir "$GI_PREFIX_LHAPDF"); LOG4CPP_LIB=$(libdir "$GI_PREFIX_LOG4CPP"); XML_LIB=$(libdir "$GI_PREFIX_LIBXML2")
for f in "$GI_PREFIX_PYTHIA8/include/Pythia8/Pythia.h" "$P8_LIB/libpythia8.so" "$GI_PREFIX_LHAPDF/include/LHAPDF/LHAPDF.h" "$LHAPDF_LIB/libLHAPDF.so" \
         "$GI_PREFIX_LOG4CPP/include/log4cpp/Category.hh" "$LOG4CPP_LIB/liblog4cpp.so" "$GI_PREFIX_LIBXML2/include/libxml2/libxml/parser.h" "$XML_LIB/libxml2.so" \
         "$PYTHIA8DATA/Version.xml"; do
  [[ -e "$f" ]] || die "missing $f"
done
p8ver=$(sed -n 's/.*name="Pythia:versionNumber".*default="\([0-9.]*\)".*/\1/p' "$PYTHIA8DATA/Version.xml" | head -1)
printf 'g++      %s  (%s)\n' "$(g++ -dumpfullversion)" "$(command -v g++)"
printf 'ROOT     %s   cflags: %s\n' "$(root-config --version)" "$(root-config --cflags)"
printf 'Pythia8  %s   %s\n' "${p8ver:-?}" "$GI_PREFIX_PYTHIA8"
printf 'LHAPDF   %s   %s\n' "$(lhapdf-config --version 2>/dev/null || echo '?')" "$GI_PREFIX_LHAPDF"
printf 'log4cpp  %s   %s\n' "$(log4cpp-config --version 2>/dev/null || echo '?')" "$GI_PREFIX_LOG4CPP"
printf 'libxml2  %s   %s (system)\n' "$(xml2-config --version 2>/dev/null || echo '?')" "$GI_PREFIX_LIBXML2"
printf 'gsl      %s   %s\n' "$(gsl-config --version)" "$(gsl-config --prefix)"
printf 'jobs     %s\n' "$NJOBS"
INCL_FLAGS=()
if [[ "$GENIE_ENABLE_INCL" == 1 ]]; then
  for f in lib/libINCL_Physics.so include/G4INCLCascade.hh bin/inclxx-config; do
    [[ -e "$INCL_PREFIX/$f" ]] || die "INCL requested but $INCL_PREFIX/$f is missing (run: bash scripts/build_inclxx.sh)"
  done
  [[ -f "$GI_PREFIX_BOOST/include/boost/version.hpp" && -f "$GI_PREFIX_BOOST/lib/libboost_timer.so" ]] || die "Boost with libboost_timer missing under $GI_PREFIX_BOOST (bash scripts/setup_deps.sh)"
  INCL_FLAGS=( --enable-incl --with-incl-inc="$INCL_PREFIX/include" --with-incl-lib="$INCL_PREFIX/lib"
               --with-boost-inc="$GI_PREFIX_BOOST/include" --with-boost-lib="$GI_PREFIX_BOOST/lib" )
  printf 'INCL++   %s\n' "$(cat "$ROOT_DIR/INCLXX_COMMIT" 2>/dev/null || echo "$INCL_PREFIX")"
  printf 'Boost    %s   %s\n' "$(sed -n 's/#define BOOST_LIB_VERSION "\(.*\)"/\1/p' "$GI_PREFIX_BOOST/include/boost/version.hpp")" "$GI_PREFIX_BOOST"
else
  printf 'INCL++   off\n'
fi

if [[ ! -f "$SRC/configure" ]]; then
  log "clone $GIT_URL ($GIT_REF) -> $SRC"
  git clone --depth 1 --branch "$GIT_REF" "$GIT_URL" "$SRC"
fi
if [[ -d "$SRC/.git" ]]; then
  printf 'GENIE Generator %s %s %s\n' "$GIT_REF" "$(git -C "$SRC" rev-parse HEAD)" \
         "$(git -C "$SRC" log -1 --format=%cI)" > "$ROOT_DIR/GENIE_COMMIT"
fi
cat "$ROOT_DIR/GENIE_COMMIT" 2>/dev/null || true
cd "$SRC"

log "clean"
# `make clean` needs a Make.config (i.e. a previous configure) and leaves stragglers;
# the explicit rm covers everything the build generates.
if [[ -f src/make/Make.config ]]; then make clean >/dev/null 2>&1 || true; fi
rm -rf lib bin
find src \( -name '*.o' -o -name '*_ROOT_DICT.*' -o -name '*_rdict.pcm' -o -name '*.rootmap' \) -delete

log "configure"
# shellcheck disable=SC2086
perl ./configure \
  --enable-pythia8 --disable-pythia6 \
  --with-pythia8-inc="$GI_PREFIX_PYTHIA8/include" --with-pythia8-lib="$P8_LIB" \
  --disable-lhapdf5 --enable-lhapdf6 \
  --with-lhapdf6-inc="$GI_PREFIX_LHAPDF/include" --with-lhapdf6-lib="$LHAPDF_LIB" \
  --with-log4cpp-inc="$GI_PREFIX_LOG4CPP/include" --with-log4cpp-lib="$LOG4CPP_LIB" \
  --with-libxml2-inc="$GI_PREFIX_LIBXML2/include/libxml2" --with-libxml2-lib="$XML_LIB" \
  "${INCL_FLAGS[@]}" ${GENIE_CONFIGURE_EXTRA:-}
grep -q '^GOPT_ENABLE_PYTHIA8=YES' src/make/Make.config || die "configure did not enable Pythia8"
if [[ "$GENIE_ENABLE_INCL" == 1 ]]; then grep -q '^GOPT_ENABLE_INCL=YES' src/make/Make.config || die "configure did not enable INCL"; fi
grep -E '^GOPT_(ENABLE_PYTHIA8|ENABLE_PYTHIA6|ENABLE_LHAPDF5|ENABLE_LHAPDF6|ENABLE_RW_2018|ENABLE_BOOSTED_DARK_MATTER|ENABLE_INCL)=' src/make/Make.config || true

log "prep targets (serial)"
make print-make-info make-bin-lib-dir save-build-env autogenerated-headers
grep -q '__GENIE_PYTHIA8_ENABLED__' src/Framework/Conventions/GBuild.h || die "GBuild.h lacks __GENIE_PYTHIA8_ENABLED__"
if [[ "$GENIE_ENABLE_INCL" == 1 ]]; then grep -q '__GENIE_INCL_ENABLED__' src/Framework/Conventions/GBuild.h || die "GBuild.h lacks __GENIE_INCL_ENABLED__"; fi

# Library groups = INITIAL_BUILD_TARGETS of the top-level Makefile minus the four prep
# targets, in Makefile order. Read from make's database so a new group upstream is picked up.
targets=$(make -pn print-make-info 2>/dev/null | sed -n 's/^INITIAL_BUILD_TARGETS = //p' | head -1)
[[ -n "$targets" ]] || die "could not read INITIAL_BUILD_TARGETS from the Makefile"
for t in $targets; do
  case "$t" in print-make-info|make-bin-lib-dir|save-build-env|autogenerated-headers) continue ;; esac
  log "make -j$NJOBS $t"
  make -j"$NJOBS" "$t"
done

log "apps (-j$NJOBS)"
make -C src/Apps -j"$NJOBS" all
log "install scripts"
make -C src/scripts install
log "final serial make (must only relink apps)"
make

log "checks"
for b in gmkspl gevgen gntpc; do [[ -x "bin/$b" ]] || die "bin/$b was not built"; done
readelf -d lib/libGPhDcy.so | grep -q 'NEEDED.*libpythia8' || die "lib/libGPhDcy.so is not linked against libpythia8"
if [[ "$GENIE_ENABLE_INCL" == 1 ]]; then
  readelf -d lib/libGPhHadTransp.so | grep -q 'NEEDED.*libINCL_Physics' || die "lib/libGPhHadTransp.so is not linked against libINCL_Physics"
fi
# the loader must find everything through LD_LIBRARY_PATH (set by setup_genie_incl.sh / spack-env.sh)
if ldd bin/gevgen | grep -q 'not found'; then ldd bin/gevgen | grep 'not found'; die "gevgen has unresolved shared libraries"; fi
# gcc 12.5's libstdc++ (the spack gcc stamps an RPATH to its lib64 into what it links; the gcc-runtime copy is the same library)
p=$(ldd bin/gevgen | awk '$1=="libstdc++.so.6" {print $3}')
case "$p" in "$GI_PREFIX_GCC"/*|"$GI_PREFIX_GCC_RUNTIME"/*) printf 'libstdc++.so.6 -> %s\n' "$p" ;;
  *) die "gevgen resolves libstdc++.so.6 to $p instead of the gcc 12.5 one ($GI_PREFIX_GCC_RUNTIME/lib must precede /usr/lib64 in LD_LIBRARY_PATH)" ;; esac
mkdir -p "$ROOT_DIR/data"
printf 'libs %s  apps %s\n' "$(ls lib/*.so | wc -l)" "$(ls bin | wc -l)"

if [[ "${GENIE_POST_CLEAN:-0}" == 1 ]]; then
  log "post-clean (objects + .git)"
  find src -name '*.o' -delete
  rm -rf .git
fi

log "BUILD_OK in $(( ($(date +%s) - T0) / 60 )) min -- $(cat "$ROOT_DIR/GENIE_COMMIT" 2>/dev/null)"
