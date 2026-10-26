#!/usr/bin/env bash
# smoke_test.sh -- end-to-end check of a GENIE build. Run it as `pixi run smoke`.
#   1. gmkspl   numu + C12, CCQE, G18_02a_00_000          (cross-section spline)
#   2. gevgen   100 events at 3 GeV from that spline
#   3. gntpc    GHEP -> gst summary ntuple, entry count checked with ROOT
#   4. gmkspl   numu + free proton, CCDIS                   (exercises Pythia8; skip with GENIE_SMOKE_DIS=0)
#   5. gevgen   20 DIS events at 5 GeV; the Pythia8 banner must appear in the log
# Output goes to work/smoke-<timestamp>/ next to the Generator checkout.
set -euo pipefail
log() { printf '\n=== %s  [%s]\n' "$*" "$(date '+%F %T')"; }
die() { printf 'smoke_test.sh: FAILED: %s\n' "$*" >&2; exit 1; }
: "${GENIE:?GENIE is not set -- run: pixi run smoke}"
for b in gmkspl gevgen gntpc python; do command -v "$b" >/dev/null || die "$b not on PATH (pixi run build-genie first?)"; done

TUNE="${GENIE_SMOKE_TUNE:-G18_02a_00_000}"
SEED="${GENIE_SMOKE_SEED:-20261026}"
WORK="${GENIE_SMOKE_DIR:-$(dirname "$GENIE")/work/smoke-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$WORK" && cd "$WORK"
printf 'work dir %s\ntune     %s\n' "$WORK" "$TUNE"
T0=$(date +%s)
# entry count of a TTree via PyROOT (`root -q -e` exits 255 even on success)
entries() { python -c 'import sys, ROOT; f = ROOT.TFile.Open(sys.argv[1]); t = f.Get(sys.argv[2]); print(t.GetEntries() if t else -1)' "$1" "$2" 2>/dev/null || echo -1; }

log "1/5 gmkspl numu + C12 CCQE  (gmkspl computes >= 30 knots whatever -n says; a few minutes)"
gmkspl -p 14 -t 1000060120 -n 30 -e 5 --event-generator-list CCQE --tune "$TUNE" \
       -o xsec_numu_C12_CCQE.xml > gmkspl_numu_C12.log 2>&1 || die "gmkspl failed, see $WORK/gmkspl_numu_C12.log"
nspl=$(grep -c '<spline ' xsec_numu_C12_CCQE.xml || true)
[[ "$nspl" -gt 0 ]] || die "spline file has no <spline> entries"
printf 'splines: %s\n' "$nspl"

log "2/5 gevgen 100 numu C12 CCQE events at 3 GeV (strictly inside the spline range)"
gevgen -n 100 -p 14 -t 1000060120 -e 3 -r 1 --seed "$SEED" --cross-sections xsec_numu_C12_CCQE.xml \
       --tune "$TUNE" --event-generator-list CCQE > gevgen_numu_C12.log 2>&1 || die "gevgen failed, see $WORK/gevgen_numu_C12.log"
[[ -s gntp.1.ghep.root ]] || die "gntp.1.ghep.root missing"

log "3/5 gntpc -> gst"
gntpc -i gntp.1.ghep.root -f gst -o numu_C12_CCQE.gst.root > gntpc_numu_C12.log 2>&1 || die "gntpc failed, see $WORK/gntpc_numu_C12.log"
n=$(entries numu_C12_CCQE.gst.root gst)
[[ "$n" == 100 ]] || die "expected 100 gst entries, got '$n'"
printf 'gst entries: %s\n' "$n"

if [[ "${GENIE_SMOKE_DIS:-1}" == 1 ]]; then
  log "4/5 gmkspl numu + H1 CCDIS  (7 splines, ~8 min on 1 core)"
  gmkspl -p 14 -t 1000010010 -n 30 -e 10 --event-generator-list CCDIS --tune "$TUNE" \
         -o xsec_numu_H1_CCDIS.xml > gmkspl_numu_H1.log 2>&1 || die "gmkspl (DIS) failed, see $WORK/gmkspl_numu_H1.log"
  printf 'splines: %s\n' "$(grep -c '<spline ' xsec_numu_H1_CCDIS.xml || true)"

  log "5/5 gevgen 20 numu H1 CCDIS events at 5 GeV (Pythia8 hadronization)"
  gevgen -n 20 -p 14 -t 1000010010 -e 5 -r 2 --seed "$SEED" --cross-sections xsec_numu_H1_CCDIS.xml \
         --tune "$TUNE" --event-generator-list CCDIS > gevgen_numu_H1.log 2>&1 || die "gevgen (DIS) failed, see $WORK/gevgen_numu_H1.log"
  grep -m1 -E 'PYTHIA (version|Version|Release) 8' gevgen_numu_H1.log || die "no Pythia8 banner in gevgen_numu_H1.log"
  gntpc -i gntp.2.ghep.root -f gst -o numu_H1_CCDIS.gst.root > gntpc_numu_H1.log 2>&1
  printf 'DIS gst entries: %s\n' "$(entries numu_H1_CCDIS.gst.root gst)"
else
  log "4/5, 5/5 skipped (GENIE_SMOKE_DIS=0)"
fi

log "SMOKE_OK in $(( ($(date +%s) - T0) / 60 )) min -- outputs in $WORK"
