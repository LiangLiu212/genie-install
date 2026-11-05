#!/usr/bin/env bash
# smoke_test_incl.sh -- end-to-end check of a GENIE build with the INCL++ interface.
# Run it inside `pixi shell`:
#   bash scripts/smoke_test_incl.sh   (non-interactive equivalent: pixi run smoke-incl)
# Every step prints the exact command it runs and "done!" when it passed, in green on a
# terminal (GENIE_SMOKE_COLOR=1 forces colour, e.g. into a log; =0 disables it).
#   1. gmkspl   numu + Ar40, CCQE, tune INCL26_09a_00_000     (the INCL QE vertex + INCL nuclear model)
#   2. gevgen   50 CCQE events at 1 GeV from that spline       (QELEventGeneratorINCL -> INCL cascade FSI)
#   3. gntpc    GHEP -> gst, entry count checked with PyROOT; INCL run-time data must have been read
#   0. optional, first: GENIE_SMOKE_INCL_XSEC=<xml> runs 20 "Default"-list numu Ar40 events at 1 GeV
#      from a full spline set (the SBND production validation), when such a file is available.
# Output goes to work/smoke-incl-<timestamp>/.
set -euo pipefail
if [[ "${GENIE_SMOKE_COLOR:-}" == 1 || ( -z "${GENIE_SMOKE_COLOR:-}" && -t 1 ) ]]; then
  GREEN=$'\e[32m'; RESET=$'\e[0m'
else
  GREEN=''; RESET=''
fi
log() { printf '\n=== %s  [%s]\n' "$*" "$(date '+%F %T')"; }
die() { printf 'smoke_test_incl.sh: FAILED: %s\n' "$*" >&2; exit 1; }
ok()  { printf '%sdone!%s\n' "$GREEN" "$RESET"; }
# run <logfile> <command...>: print the full command line (green), then run it with
# stdout and stderr in <logfile>; returns the command's exit status.
run() {
  local logfile=$1; shift
  printf '%s$ %s > %s 2>&1%s\n' "$GREEN" "$*" "$logfile" "$RESET"
  "$@" > "$logfile" 2>&1
}
: "${GENIE:?GENIE is not set -- run this inside pixi shell (or after: source genie-setup.sh)}"
: "${INCLXX_DIR:?INCLXX_DIR is not set -- is ./inclxx built? (bash scripts/build_inclxx.sh)}"
for b in gmkspl gevgen gntpc gevdump root; do command -v "$b" >/dev/null || die "$b not on PATH"; done
grep -q '__GENIE_INCL_ENABLED__' "$GENIE/src/Framework/Conventions/GBuild.h" || die "this GENIE build has no INCL interface (GBuild.h)"
[[ -f "$INCLXX_DATA_DIR/de-excitation/ablaxx/upstream/data/G4ABLA3.0/frldm.dat" ]] || die "INCL data tables not found under INCLXX_DATA_DIR=$INCLXX_DATA_DIR"

TUNE="${GENIE_SMOKE_INCL_TUNE:-INCL26_09a_00_000}"
SEED="${GENIE_SMOKE_SEED:-20261026}"
WORK="${GENIE_SMOKE_DIR:-$(dirname "$GENIE")/work/smoke-incl-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$WORK" && cd "$WORK"
printf 'work dir %s\ntune     %s\nINCLXX_DIR %s\n' "$WORK" "$TUNE" "$INCLXX_DIR"
T0=$(date +%s)
# TTree entry counts via ROOT's C++ interpreter (`root -q -e` returns 255 even on success, hence
# the masking). In PyROOT the TFile must be kept alive while the TTree is used.
rootq() { { root -l -b -q -e "$1" 2>/dev/null; true; } | tail -1; }
entries() { rootq "TFile f(\"$1\"); TTree* t=(TTree*)f.Get(\"$2\"); std::cout << (t ? t->GetEntries() : -1) << std::endl;"; }
check_log() {  # check_log <gevgen log>: no FATAL, no INCL exit, INCL really ran
  local n_fatal; n_fatal=$(grep -c "FATAL" "$1" || true)
  [[ "$n_fatal" == 0 ]] || { grep -m3 FATAL "$1"; die "$n_fatal FATAL line(s) in $1"; }
  grep -qiE "INCL" "$1" || die "no INCL output at all in $1"
}

if [[ -n "${GENIE_SMOKE_INCL_XSEC:-}" ]]; then
  log "0/3 gevgen 20 numu Ar40 'Default'-list events at 1 GeV from $GENIE_SMOKE_INCL_XSEC (the SBND production check)"
  [[ -f "$GENIE_SMOKE_INCL_XSEC" ]] || die "GENIE_SMOKE_INCL_XSEC file not found"
  run gevgen_numu_Ar40_Default.log \
      gevgen -n 20 -p 14 -t 1000180400 -e 1 -r 2 --seed "$SEED" --cross-sections "$GENIE_SMOKE_INCL_XSEC" \
             --tune "$TUNE" --event-generator-list Default \
    || die "gevgen (Default list) failed, see $WORK/gevgen_numu_Ar40_Default.log"
  check_log gevgen_numu_Ar40_Default.log
  run gntpc_numu_Ar40_Default.log gntpc -i gntp.2.ghep.root -f gst -o numu_Ar40_Default.gst.root || die "gntpc (Default) failed"
  printf 'Default-list gst entries: %s\n' "$(entries numu_Ar40_Default.gst.root gst)"
  ok
else
  log "0/3 skipped (set GENIE_SMOKE_INCL_XSEC=<full spline xml> to run the Default-list check)"
fi

log "1/3 gmkspl numu + Ar40 CCQE, tune $TUNE  (INCL nuclear model; several minutes)"
run gmkspl_numu_Ar40.log \
    gmkspl -p 14 -t 1000180400 -n 30 -e 5 --event-generator-list CCQE --tune "$TUNE" -o xsec_numu_Ar40_CCQE.xml \
  || die "gmkspl failed, see $WORK/gmkspl_numu_Ar40.log"
nspl=$(grep -c '<spline ' xsec_numu_Ar40_CCQE.xml || true); [[ "$nspl" -gt 0 ]] || die "no splines produced"
printf 'splines: %s  (%s s)\n' "$nspl" "$(( $(date +%s) - T0 ))"
ok

log "2/3 gevgen 50 numu Ar40 CCQE events at 1 GeV (INCL cascade FSI)"
run gevgen_numu_Ar40_CCQE.log \
    gevgen -n 50 -p 14 -t 1000180400 -e 1 -r 1 --seed "$SEED" --cross-sections xsec_numu_Ar40_CCQE.xml \
           --tune "$TUNE" --event-generator-list CCQE \
  || die "gevgen failed, see $WORK/gevgen_numu_Ar40_CCQE.log"
check_log gevgen_numu_Ar40_CCQE.log
ok

log "3/3 gntpc -> gst + event-record sanity"
run gntpc_numu_Ar40_CCQE.log gntpc -i gntp.1.ghep.root -f gst -o numu_Ar40_CCQE.gst.root || die "gntpc failed"
n=$(entries numu_Ar40_CCQE.gst.root gst); [[ "$n" == 50 ]] || die "expected 50 gst entries, got '$n'"
summary=$(rootq "TFile f(\"numu_Ar40_CCQE.gst.root\"); TTree* t=(TTree*)f.Get(\"gst\"); std::cout << t->GetEntries() << \" \" << t->GetEntries(\"nf>0\") << \" \" << t->GetMaximum(\"nf\") << \" \" << t->GetEntries(\"nfp>0\") << \" \" << t->GetEntries(\"nfn>0\") << std::endl;")
read -r s_n s_had s_nfmax s_pro s_neu <<< "$summary"
printf 'gst entries %s | events with final-state hadrons %s (max nf %s) | with protons %s, with neutrons %s\n' "$s_n" "$s_had" "$s_nfmax" "$s_pro" "$s_neu"
[[ "$s_n" == 50 && "${s_had:-0}" -gt 0 ]] || die "gst sanity check failed (entries=$s_n, with hadrons=$s_had)"
gevdump -f gntp.1.ghep.root -n 0 2>/dev/null | grep -E "^ \|" > event0.dump || true
printf 'event 0 record lines: %s  (status 17 = excited remnant, 18 = spectator: %s lines)\n' \
       "$(wc -l < event0.dump)" "$(grep -cE "\|\s+1[78]\s+\|" event0.dump || true)"
ok

log "SMOKE_INCL_OK in $(( ($(date +%s) - T0) / 60 )) min -- outputs in $WORK"
