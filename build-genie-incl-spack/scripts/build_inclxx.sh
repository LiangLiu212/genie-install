#!/usr/bin/env bash
# build_inclxx.sh -- clone (if needed), configure, build and install INCL++ (the GENIE-interface
# fork of the INCL++ intranuclear cascade) into ./inclxx, against ROOT and the compiler from the
# DUNE CVMFS Spack and the local Boost. Run it after `source setup_genie_incl.sh`:
#   bash scripts/build_inclxx.sh
#
# Knobs (environment variables, all optional):
#   INCLXX_GIT_URL     repository                 default git@github.com:LiangLiu212/inclxx.git (access required)
#   INCLXX_GIT_REF     commit / branch / tag      default 8a6c1cf17e99dacca026e0a4268de35e7843cb1a (v6.34, branch sbnd/v6_34_sbn0)
#   INCLXX_NJOBS       parallel make jobs         default: the cgroup CPU quota, else nproc
#   INCLXX_BUILD_TYPE  CMAKE_BUILD_TYPE           default RelWithDebInfo
#
# Layout after a successful run:  inclxx/bin (inclxx-config, thisinclxx.sh), inclxx/lib (9 shared
# libraries), inclxx/include, inclxx/share (INCL, ABLA07, ABLA++, GEMINI++ data tables).
set -euo pipefail
log() { printf '\n=== %s  [%s]\n' "$*" "$(date '+%F %T')"; }
die() { printf 'build_inclxx.sh: ERROR: %s\n' "$*" >&2; exit 1; }
default_jobs() {  # `nproc` honours OMP_NUM_THREADS (1 on the Fermilab EAF); the cgroup quota is the truth
  local q p
  if read -r q p < /sys/fs/cgroup/cpu.max 2>/dev/null && [[ "$q" != max ]]; then echo $(( (q + p - 1) / p )); else env -u OMP_NUM_THREADS nproc; fi
}

: "${GI_PREFIX_ROOT:?GI_PREFIX_ROOT is not set -- first: source setup_genie_incl.sh}"
: "${GI_PREFIX_BOOST:?GI_PREFIX_BOOST is not set -- first: source setup_genie_incl.sh}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT_DIR/inclxx-src"
BLD="$ROOT_DIR/inclxx-build"
PREFIX="$ROOT_DIR/inclxx"
GIT_URL="${INCLXX_GIT_URL:-git@github.com:LiangLiu212/inclxx.git}"
GIT_REF="${INCLXX_GIT_REF:-8a6c1cf17e99dacca026e0a4268de35e7843cb1a}"
NJOBS="${INCLXX_NJOBS:-$(default_jobs)}"
BUILD_TYPE="${INCLXX_BUILD_TYPE:-RelWithDebInfo}"
T0=$(date +%s)

log "preflight"
for tool in cmake make g++ gfortran git root-config; do command -v "$tool" >/dev/null || die "$tool not found on PATH (source setup_genie_incl.sh)"; done
case "$(command -v g++)" in "$GI_PREFIX_GCC"/*) ;; *) die "g++ on PATH is $(command -v g++), not the spack gcc 12.5 under $GI_PREFIX_GCC" ;; esac
[[ -f "$GI_PREFIX_BOOST/include/boost/version.hpp" ]] || die "Boost headers missing under $GI_PREFIX_BOOST"
for l in timer date_time program_options system; do [[ -f "$GI_PREFIX_BOOST/lib/libboost_$l.so" ]] || die "$GI_PREFIX_BOOST/lib/libboost_$l.so missing (bash scripts/setup_deps.sh)"; done
# spack's ROOT 6.28 keeps ROOTConfig.cmake in share/root/cmake, where cmake's search does not look: pass ROOT_DIR
rootcmake=""
for c in "$GI_PREFIX_ROOT/share/root/cmake/ROOTConfig.cmake" "$GI_PREFIX_ROOT/cmake/ROOTConfig.cmake" "$GI_PREFIX_ROOT/lib/cmake/ROOT/ROOTConfig.cmake" "$(root-config --libdir)/cmake/ROOTConfig.cmake"; do [[ -f "$c" ]] && { rootcmake=$c; break; }; done
[[ -n "$rootcmake" ]] || die "ROOTConfig.cmake not found under $GI_PREFIX_ROOT"
ROOT_CMAKE_DIR="$(dirname "$rootcmake")"
printf 'cmake %s | g++ %s | gfortran %s | ROOT %s (%s) | Boost %s (%s) | jobs %s\n' "$(cmake --version | head -1 | awk '{print $3}')" "$(g++ -dumpfullversion)" "$(gfortran -dumpfullversion)" \
       "$(root-config --version)" "$ROOT_CMAKE_DIR" "$(sed -n 's/#define BOOST_LIB_VERSION "\(.*\)"/\1/p' "$GI_PREFIX_BOOST/include/boost/version.hpp")" "$GI_PREFIX_BOOST" "$NJOBS"

if [[ ! -f "$SRC/CMakeLists.txt" ]]; then
  log "clone $GIT_URL -> $SRC"
  git clone -q "$GIT_URL" "$SRC"
fi
git -C "$SRC" checkout -q "$GIT_REF" || die "cannot check out $GIT_REF in $SRC"
printf 'INCL++ %s %s %s\n' "$GIT_REF" "$(git -C "$SRC" rev-parse HEAD)" "$(git -C "$SRC" log -1 --format=%cI)" > "$ROOT_DIR/INCLXX_COMMIT"
cat "$ROOT_DIR/INCLXX_COMMIT"

log "configure (clean build dir, install prefix $PREFIX)"
rm -rf "$BLD" "$PREFIX"; mkdir -p "$BLD"
# Same options as the validated SBND/DUNE installs (inclxx_external/build_inclxx_external.sh).
CMAKE_OPTS=(
  -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_PREFIX_PATH="$GI_PREFIX_ROOT;$GI_PREFIX_BOOST"
  -DROOT_DIR="$ROOT_CMAKE_DIR"
  -DCMAKE_C_COMPILER="${CC:-gcc}" -DCMAKE_CXX_COMPILER="${CXX:-g++}" -DCMAKE_Fortran_COMPILER="${FC:-gfortran}"
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
  -DBUILD_SHARED_LIBRARY=ON
  -DUSE_INSTALL_PATH=ON
  -DINCL_ROOT_USE=ON
  -DINCL_DEBUG_LOG=ON
  -DINCL_SIGNAL_HANDLING=ON
  -DINCL_USE_ALLOCATION_POOL=ON
  -DINCL_PEDANTIC_COMPILER=ON
  -DINCL_DEFINE_EMPTY_G4THREADLOCAL=ON
  -DINCL_AVATAR_SEARCH=MinElement
  -DINCL_CACHING_CLUSTERING_MODEL_INTERCOMPARISON=Set
  -DINCL_DEEXCITATION_USE=ON
  -DINCL_DEEXCITATION_ABLA07=ON
  -DINCL_DEEXCITATION_ABLA07_USER_RNG=ON
  -DINCL_DEEXCITATION_ABLAXX=ON
  -DINCL_DEEXCITATION_ABLAXX_USER_RNG=ON
  -DINCL_DEEXCITATION_FERMI_BREAKUP=ON
  -DINCL_DEEXCITATION_GEMINIXX=ON
  -DINCL_DEEXCITATION_GEMINIXX_USER_RNG=ON
  -DINCL_DEEXCITATION_SMM=ON
  -DINCL_DEEXCITATION_SMM_USER_RNG=ON
  -DINCL_ASCII_USE=OFF
  -DINCL_HDF5_USE=OFF
  -DINCL_PROTOBUF_USE=OFF
  -DINCL_COUNT_RND_CALLS=OFF
  -DINCL_REGENERATE_AVATARS=OFF
  -DINCL_TREEADD=OFF
  -DINCL_TREECONVERTER=OFF
)
( cd "$BLD" && cmake "${CMAKE_OPTS[@]}" "$SRC" )
grep -q "^Boost_DIR:PATH=$GI_PREFIX_BOOST" "$BLD/CMakeCache.txt" || grep -q "^Boost_INCLUDE_DIR:PATH=$GI_PREFIX_BOOST" "$BLD/CMakeCache.txt" \
  || die "cmake did not pick the local Boost (see $BLD/CMakeCache.txt)"

log "make -j$NJOBS"
make -C "$BLD" -j"$NJOBS"
log "make install"
make -C "$BLD" install >/dev/null

log "post-install fixes"
# G4INCLVersion.hh is generated at build time, after cmake globbed the headers to install.
[[ -f "$PREFIX/include/G4INCLVersion.hh" ]] || cp -p "$SRC/utils/include/G4INCLVersion.hh" "$PREFIX/include/" || die "G4INCLVersion.hh not generated"
# GENIE (NucleusGenINCL.xml) expects the ABLA++ tables under de-excitation/ablaxx/upstream/data/G4ABLA3.0/;
# INCL++ installs them with its own tables in share/data.
mkdir -p "$PREFIX/share/de-excitation/ablaxx/upstream/data"
[[ -e "$PREFIX/share/de-excitation/ablaxx/upstream/data/G4ABLA3.0" ]] || ln -s ../../../../data "$PREFIX/share/de-excitation/ablaxx/upstream/data/G4ABLA3.0"
[[ -f "$PREFIX/share/de-excitation/ablaxx/upstream/data/G4ABLA3.0/frldm.dat" ]] || die "ABLA++ tables not reachable"
[[ -d "$PREFIX/share/de-excitation/abla07/upstream/tables" ]] || die "ABLA07 tables missing"
[[ -d "$PREFIX/share/de-excitation/geminixx/upstream/tbl" ]] || die "GEMINI++ tables missing"

log "checks"
[[ -x "$PREFIX/bin/inclxx-config" ]] || die "bin/inclxx-config missing"
[[ -f "$PREFIX/include/G4INCLCascade.hh" ]] || die "include/G4INCLCascade.hh missing"
[[ -f "$PREFIX/lib/libINCL_Physics.so" ]] || die "lib/libINCL_Physics.so missing"
nlib=$(ls "$PREFIX"/lib/*.so | wc -l); printf 'shared libraries: %s\n' "$nlib"
printf 'inclxx-config --libs: %s\n' "$("$PREFIX/bin/inclxx-config" --libs)"
# the INCL++ libraries carry no rpath and reference each other: resolve them through their own lib dir
if LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}" ldd "$PREFIX/lib/libINCL_Physics.so" | grep -q 'not found'; then
  LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}" ldd "$PREFIX/lib/libINCL_Physics.so" | grep 'not found'; die "unresolved libraries"
fi
# libstdc++/libgfortran must be gcc 12.5's: the spack gcc stamps an RPATH to its own lib64 into everything it
# links (so this holds even without LD_LIBRARY_PATH); the gcc-runtime copy is the same library.
for l in libstdc++.so.6 libgfortran.so.5; do
  p=$(LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}" ldd "$PREFIX"/lib/libINCL_*.so 2>/dev/null | awk -v l="$l" '$1==l && !f {print $3; f=1}')
  case "$p" in ""|"$GI_PREFIX_GCC"/*|"$GI_PREFIX_GCC_RUNTIME"/*) ;; *) die "$l resolves to $p instead of the gcc 12.5 one under $GI_PREFIX_GCC or $GI_PREFIX_GCC_RUNTIME" ;; esac
done
printf 'libstdc++.so.6 -> %s\n' "$(LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}" ldd "$PREFIX/lib/libINCL_Physics.so" | awk '$1=="libstdc++.so.6" {print $3}')"
log "INCLXX_OK in $(( ($(date +%s) - T0) / 60 )) min -- $(cat "$ROOT_DIR/INCLXX_COMMIT") -- re-source setup_genie_incl.sh to export INCLXX_DIR"
