#!/usr/bin/env bash
# build_inclxx.sh -- clone (if needed), configure, build and install INCL++ (the GENIE-interface
# fork of the INCL++ intranuclear cascade) into ./inclxx, using the pixi `incl` environment.
# Run it as:  pixi run -e incl build-inclxx
#
# Knobs (environment variables, all optional):
#   INCLXX_GIT_URL     repository                 default git@github.com:LiangLiu212/inclxx.git (access required)
#   INCLXX_GIT_REF     commit / branch / tag      default 8a6c1cf17e99dacca026e0a4268de35e7843cb1a (v6.34, branch sbnd/v6_34_sbn0)
#   INCLXX_NJOBS       parallel make jobs         default `nproc`
#   INCLXX_BUILD_TYPE  CMAKE_BUILD_TYPE           default RelWithDebInfo
#
# Layout after a successful run:  inclxx/bin (inclxx-config, thisinclxx.sh), inclxx/lib (9 shared
# libraries), inclxx/include, inclxx/share (INCL, ABLA07, ABLA++, GEMINI++ data tables).
set -euo pipefail
log() { printf '\n=== %s  [%s]\n' "$*" "$(date '+%F %T')"; }
die() { printf 'build_inclxx.sh: ERROR: %s\n' "$*" >&2; exit 1; }

: "${CONDA_PREFIX:?not inside the pixi environment -- run: pixi run -e incl build-inclxx}"
ROOT_DIR="${PIXI_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC="$ROOT_DIR/inclxx-src"
BLD="$ROOT_DIR/inclxx-build"
PREFIX="$ROOT_DIR/inclxx"
GIT_URL="${INCLXX_GIT_URL:-git@github.com:LiangLiu212/inclxx.git}"
GIT_REF="${INCLXX_GIT_REF:-8a6c1cf17e99dacca026e0a4268de35e7843cb1a}"
NJOBS="${INCLXX_NJOBS:-$(nproc)}"
BUILD_TYPE="${INCLXX_BUILD_TYPE:-RelWithDebInfo}"
T0=$(date +%s)

log "preflight"
for tool in cmake make g++ git root-config; do command -v "$tool" >/dev/null || die "$tool not found (pixi install -e incl?)"; done
[[ -f "$CONDA_PREFIX/include/boost/version.hpp" ]] || die "Boost headers missing in $CONDA_PREFIX (libboost-devel)"
[[ -f "$CONDA_PREFIX/cmake/ROOTConfig.cmake" || -f "$CONDA_PREFIX/lib/cmake/ROOT/ROOTConfig.cmake" ]] || die "ROOTConfig.cmake not found under $CONDA_PREFIX"
printf 'cmake %s | g++ %s | ROOT %s | Boost %s | jobs %s\n' "$(cmake --version | head -1 | awk '{print $3}')" "$(g++ -dumpfullversion)" \
       "$(root-config --version)" "$(sed -n 's/#define BOOST_LIB_VERSION "\(.*\)"/\1/p' "$CONDA_PREFIX/include/boost/version.hpp")" "$NJOBS"

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
  -DCMAKE_PREFIX_PATH="$CONDA_PREFIX"
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
log "INCLXX_OK in $(( ($(date +%s) - T0) / 60 )) min -- $(cat "$ROOT_DIR/INCLXX_COMMIT")"
