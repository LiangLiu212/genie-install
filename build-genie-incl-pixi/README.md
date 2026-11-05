# Install GENIE with the INCL++ cascade using pixi (Linux x86_64)

## Quick start

```bash
curl -fsSL https://pixi.sh/install.sh | sh       # pixi itself, once per machine; then open a new shell
git clone https://github.com/LiangLiu212/genie-install.git
cd genie-install/build-genie-incl-pixi
pixi install                     # ROOT, Pythia8, LHAPDF, …, CMake, Boost, gfortran into ./.pixi  (~2.9 GB)
pixi shell                       # sub-shell with everything on PATH and the GENIE / INCL variables set
bash scripts/build_inclxx.sh     # INCL++ 6.34 (GENIE-interface fork, access required) -> ./inclxx   (~1 min)
bash scripts/build_genie.sh      # GENIE feature/incl-v3_8 with the INCL interface -> ./Generator  (~12 min on 16 cores)
bash scripts/smoke_test_incl.sh  # tune INCL26_09a: gmkspl -> gevgen -> gntpc on Ar40
gevgen --help                    # ready; `exit` leaves the sub-shell
```

pixi is used for two commands only: `pixi install` once, and `pixi shell` whenever you
open a new terminal. Everything inside that sub-shell is plain bash. A batch job or a
shell rc can even skip `pixi shell`, see [Without pixi at all](#without-pixi-at-all).

## What this is

The sibling workspace [`../build-genie-pixi`](../build-genie-pixi) builds plain GENIE
`master`. This one builds GENIE with the [INCL++](https://irfu.cea.fr/dphn/Spallation/incl.html)
intranuclear cascade: INCL++ handles the final-state interactions and, with the `INCL26_*`
tunes, the quasi-elastic vertex and the nuclear model itself. Two extra ingredients:

- **INCL++ 6.34**, built from its GENIE-interface fork. INCL++ is developed by CEA-Irfu and
  the University of Liège, is available **on request from its authors** for non-commercial
  use, and **may not be redistributed** (`LICENSE.pdf` in its source tree). This repository
  therefore contains no INCL++ code, and the fork `git@github.com:LiangLiu212/inclxx.git`
  is private. Once you are authorised, point `INCLXX_GIT_URL` at the fork or at your own
  copy of the source tree.
- **GENIE with the INCL interface**: branch
  [`feature/incl-v3_8`](https://github.com/LiangLiu212/Generator/tree/feature/incl-v3_8)
  of `LiangLiu212/Generator`. It is the SBND production branch `feature/genie-incl634-sbnd`
  rebased onto official GENIE `master`, see [How the branch was made](#how-the-featureincl-v3_8-branch-was-made).
  Official GENIE ships only the old `HINCLCascadeIntranuke` interface; the branch adds the
  INCL nuclear model, the INCL quasi-elastic vertex, the cascade and the tunes
  `INCL26_07a` / `INCL26_09a`.

**What you get:** everything of the plain workspace (GENIE `master`, Pythia8-only, LHAPDF6)
plus the INCL interface compiled in (`--enable-incl`) and INCL++ under `./inclxx`.

**Last tested:** 2026-11-02 (see [Tested configuration](#tested-configuration)).

---

## 1. Prerequisites

- Linux, x86_64, about 6 GB of free disk (2.9 GB environment, 0.6 GB GENIE, 0.3 GB INCL++
  source + build + install), internet access to `conda.anaconda.org` and `github.com`.
- `curl`, `bash`. `git`, CMake and a compiler are **not** needed on the host; pixi installs them.
- Read access to an INCL++ source tree (see above). Clone access to the private fork is
  over SSH, so an SSH key registered with GitHub, or set `INCLXX_GIT_URL` to a local path.
- No `sudo`. Nothing is written outside this directory except pixi's package cache
  (`~/.cache/rattler` by default; move it with `PIXI_CACHE_DIR=/some/path`).

Install pixi (one static binary into `~/.pixi/bin`, adds itself to your shell rc):

```bash
curl -fsSL https://pixi.sh/install.sh | sh
exec $SHELL            # or open a new terminal
pixi --version         # 0.78.0 was used for the tests below
```

## 2. Get this repository

```bash
git clone https://github.com/LiangLiu212/genie-install.git
cd genie-install/build-genie-incl-pixi
```

Everything below runs from inside this directory; it is a complete pixi workspace on its own.
The layout:

```
pixi.toml                     dependencies, activation script, tasks
pixi.lock                     exact package versions (commit it; `pixi install` honours it)
scripts/genie-env.sh          the environment contract (GENIE, XSECSPLINEDIR, PYTHIA8DATA, INCLXX_DIR, INCLXX_DATA_DIR, PATH, LD_LIBRARY_PATH)
scripts/build_inclxx.sh       clone + cmake + build + install INCL++
scripts/build_genie.sh        clone + configure (--enable-incl) + build GENIE
scripts/smoke_test_incl.sh    end-to-end check with the INCL26_09a tune
scripts/smoke_test.sh         the plain G18_02a check of the sibling workspace (also works here)
inclxx-src/, inclxx-build/    INCL++ source clone and build tree   (created by build_inclxx.sh, git-ignored)
inclxx/                       INCL++ install: bin, lib, include, share (= $INCLXX_DIR, git-ignored)
Generator/                    GENIE checkout + in-tree build        (created by build_genie.sh, git-ignored)
data/                         your cross-section splines            (= $XSECSPLINEDIR, git-ignored)
work/                         smoke-test output                     (git-ignored)
genie-setup.sh                optional `pixi shell-hook` output to `source` without pixi (git-ignored)
```

## 3. Install the dependencies

```bash
pixi install
```

This resolves `pixi.toml` against the committed `pixi.lock` and unpacks the packages into
`./.pixi/envs/default`: 196 packages, 2.9 GB on disk. The packages are those of the plain
workspace (see its README for the table) plus:

| package | role |
|---|---|
| `cmake` | INCL++ is a CMake project |
| `libboost-devel` | Boost headers and libraries: INCL++ uses date_time, program_options and timer, and GENIE's INCL interface includes Boost headers |
| `fortran-compiler` | conda gfortran: INCL++'s ABLA07 de-excitation code is Fortran |

Nothing is activated in your current shell: the environment comes alive only inside
`pixi shell` (next section) or, for one command, `pixi run …`.

## 4. Enter the environment and build INCL++

```bash
pixi shell                                        # the prompt gains "(build-genie-incl-pixi)"
bash scripts/build_inclxx.sh                      # ~1 min on 16 cores
INCLXX_GIT_URL=/path/to/inclxx bash scripts/build_inclxx.sh   # from your own copy of the source
```

`pixi shell` starts a sub-shell with the environment on `PATH`, `CONDA_PREFIX` set and
`scripts/genie-env.sh` sourced (the `[activation]` entry of `pixi.toml`). The script clones
the INCL++ source into `inclxx-src/` (if `inclxx-src/CMakeLists.txt` is missing), checks out
`INCLXX_GIT_REF`, configures a clean build in `inclxx-build/` with the CMake options of the
validated SBND/DUNE installations (ABLA07, ABLA++, GEMINI++, SMM and Fermi break-up
de-excitation, ROOT I/O, no HDF5/protobuf), builds, installs into `inclxx/`, applies two
post-install fixes GENIE needs (`G4INCLVersion.hh`, the ABLA++ `G4ABLA3.0` data path), and
checks that the nine shared libraries resolve. The last line is `=== INCLXX_OK`.

Knobs: `INCLXX_GIT_URL`, `INCLXX_GIT_REF` (default: the commit SBND production uses),
`INCLXX_NJOBS`, `INCLXX_BUILD_TYPE` (default `RelWithDebInfo`).

`exit` and `pixi shell` again after this step: the activation script exports `INCLXX_DIR`
and puts `inclxx/lib` on `LD_LIBRARY_PATH` only when `inclxx/lib/libINCL_Physics.so` exists.

## 5. Build GENIE

```bash
bash scripts/build_genie.sh                     # uses `nproc` parallel jobs
GENIE_NJOBS=8 bash scripts/build_genie.sh       # or choose the job count yourself
bash scripts/build_genie.sh > build.log 2>&1    # the build prints ~3100 lines; keep them
```

Same script as the plain workspace, with two differences: it clones
`https://github.com/LiangLiu212/Generator.git` at `feature/incl-v3_8` by default
(`GENIE_GIT_URL` / `GENIE_GIT_REF` override), and it adds

```
--enable-incl --with-incl-inc=$INCLXX_DIR/include --with-incl-lib=$INCLXX_DIR/lib \
--with-boost-inc=$CONDA_PREFIX/include --with-boost-lib=$CONDA_PREFIX/lib
```

to `./configure` whenever `./inclxx/lib/libINCL_Physics.so` exists (`GENIE_ENABLE_INCL=0`
forces it off, `=1` makes a missing INCL++ an error). It asserts `GOPT_ENABLE_INCL=YES`
and `__GENIE_INCL_ENABLED__` after configure, and after the build that
`lib/libGPhHadTransp.so` is linked against `libINCL_Physics.so`. Build pattern, checks
and knobs are otherwise those described in the plain workspace's README. The last line is
`=== BUILD_OK in N min -- GENIE Generator feature/incl-v3_8 <sha> <date>`.

## 6. Verify

```bash
bash scripts/smoke_test_incl.sh                 # still inside the pixi shell
```

It runs in `work/smoke-incl-<timestamp>/`, printing each command it runs and `done!` after
every passed step (green on a terminal):

| step | command | checks |
|---|---|---|
| 1 | `gmkspl -p 14 -t 1000180400 -n 30 -e 5 --event-generator-list CCQE --tune INCL26_09a_00_000` | a spline is produced with the INCL nuclear model |
| 2 | `gevgen -n 50 -p 14 -t 1000180400 -e 1 --cross-sections … --tune INCL26_09a_00_000 --event-generator-list CCQE` | no `FATAL`, INCL output present in the log |
| 3 | `gntpc -i gntp.1.ghep.root -f gst` | 50 gst entries, final-state hadrons in the events, event 0 dumped |

Step 1 is the slow one, 9 minutes on the test machine (517 s); steps 2 and 3 take seconds. Optionally, `GENIE_SMOKE_INCL_XSEC=<xml>`
with a full INCL26_09a spline set first runs 20 `Default`-list events at 1 GeV, the SBND
production validation. `bash scripts/smoke_test.sh` (the plain G18_02a check) also works in
this build. The last line is `=== SMOKE_INCL_OK`.

## 7. Use it

Every new terminal:

```bash
cd genie-install/build-genie-incl-pixi
pixi shell                 # the only pixi command you need from now on
gevgen --help
exit
```

Tune ids are `INCL26_07a_00_000` (SF-Unified QE, LQCD z-expansion) and `INCL26_09a_00_000`
(Nieves QE, z-expansion, no RPA); both put the INCL cascade on every channel and need
their own cross-section splines:

```bash
gmkspl -p 14 -t 1000180400 -n 100 -e 10 --tune INCL26_09a_00_000 -o data/numu_Ar40_INCL26_09a.xml
gevgen -n 1000 -p 14 -t 1000180400 -e 2.5 --cross-sections data/numu_Ar40_INCL26_09a.xml --tune INCL26_09a_00_000
gntpc -i gntp.0.ghep.root -f gst
```

The environment contract set by `scripts/genie-env.sh` on every activation
(`bash scripts/genie-env.sh --print` shows it):

| variable | value |
|---|---|
| `GENIE` | `<this directory>/Generator` |
| `XSECSPLINEDIR` | `<this directory>/data` |
| `ROOTSYS` | the pixi environment |
| `PYTHIA8DATA` | `$CONDA_PREFIX/share/Pythia8/xmldoc` |
| `INCLXX_DIR` | `<this directory>/inclxx` (when built) |
| `INCLXX_DATA_DIR` | `$INCLXX_DIR/share` (INCL, ABLA07, ABLA++, GEMINI++ tables; `NucleusGenINCL.xml` reads it) |
| `PATH` | `$GENIE/bin` and `$INCLXX_DIR/bin` prepended |
| `LD_LIBRARY_PATH` | `$GENIE/lib:$INCLXX_DIR/lib:$CONDA_PREFIX/lib` prepended — required: GENIE links with `-Wl,--no-undefined` and no rpath, and the INCL++ libraries carry no rpath and reference each other |

### Without pixi at all

```bash
pixi shell-hook -s bash > genie-setup.sh        # once, after `pixi install` and the two builds
source /path/to/build-genie-incl-pixi/genie-setup.sh
```

The file is a plain list of `export` and `. …` lines with this machine's absolute paths,
tied to this checkout; regenerate it after `pixi update`. It is git-ignored.

## 8. Update or rebuild

Inside the pixi shell:

```bash
git -C Generator pull                 # move to the current feature/incl-v3_8
bash scripts/build_genie.sh           # always a clean rebuild
```

`bash scripts/build_inclxx.sh` likewise rebuilds INCL++ from scratch; rebuild GENIE
afterwards. After `pixi update`, leave the sub-shell, `pixi shell` again, and rebuild both.

## Troubleshooting

All entries of the plain workspace's README apply. In addition:

- **`git clone git@github.com:LiangLiu212/inclxx.git` is refused.** You are not authorised
  for the private fork. Get the INCL++ source from its authors and point `INCLXX_GIT_URL`
  at your copy (a local path works).
- **`No CMAKE_Fortran_COMPILER could be found` from `build_inclxx.sh`.** Your environment predates
  the `fortran-compiler` line in `pixi.toml` (ABLA07 is Fortran, and the host has no `gfortran`):
  `git pull && pixi install`, then `exit` and `pixi shell` again.
- **`ld: cannot find -lboost_system`.** Boost ≥ 1.69 has no `libboost_system` (header-only),
  and conda-forge's Boost 1.92 does not ship one. `feature/incl-v3_8` links only
  `program_options`, `timer` and `date_time`; official GENIE's `Make.include` still names
  `boost_system`, so this is what you get when building another branch with `--enable-incl`.
- **`libINCL_Physics.so: cannot open shared object file`** at run time: `inclxx/lib` is not
  on `LD_LIBRARY_PATH`. You built INCL++ after entering the shell; `exit` and `pixi shell`
  again (or `source genie-setup.sh` regenerated after the build).
- **`free(): double free detected in tcache 2` at the second event.** You are running an
  INCL branch without the `INCLNucleus::reset` fix of `feature/incl-v3_8`: INCL++'s propagation
  model deletes the nucleus it owns, and the old code deleted it once more. Older glibc never
  reported it, glibc ≥ 2.29 aborts. Not an INCL++ problem; update GENIE.
- **The INCL++ install must not leave this machine.** The `inclxx/` directory and any
  container image containing it fall under the INCL++ licence: build and run, do not pass on.

## Tested configuration

Measured on 2026-11-02 on an AlmaLinux 9.8 x86_64 node (glibc 2.34) with 16 jobs:

| item | value |
|---|---|
| GENIE Generator | `feature/incl-v3_8` @ `1ce9c9312` = GENIE `master` `e2e04f19` (2026-10-27) + 27 commits |
| INCL++ | 6.34, GENIE-interface fork @ `8a6c1cf17e99dacca026e0a4268de35e7843cb1a`, build 1 min, 9 libraries |
| pixi | 0.78.0 |
| compiler | conda-forge gcc/g++ 15.3.0 (`cxx-compiler 2.0.0`), libstdc++ 16.2 |
| ROOT | 6.40.04, conda-forge `cxx20` build → GENIE is compiled with `-std=c++20` |
| Pythia8 / LHAPDF / log4cpp / libxml2 / GSL | 8.312 / 6.5.6 / 1.1.4 (+ libnsl 2.0.1) / 2.15.4 / 2.8 |
| Boost / CMake | 1.92.0 / 4.4.4 |
| GENIE build | 12 min wall (`scripts/build_genie.sh`, clean, `--enable-incl`), 96 libraries, 21 apps, 0 errors |
| smoke (INCL26_09a) | 8 min: 1 CCQE spline on Ar40 with the INCL nuclear model (517 s), 50 events at 1 GeV, 50 gst entries all with final-state hadrons (max 14 per event), 0 FATAL |

## How the `feature/incl-v3_8` branch was made

`feature/genie-incl634-sbnd` (tip `6f99d2bd`, 2026-10-06) had branched from a commit of
2026-05-07; GENIE `master` moved 799 commits since. The branch was rebased onto `master`
(`e2e04f19`, 2026-10-27) on 2026-11-02:

- Of its 54 commits, 21 were already on `master` with identical patches (the martini2p2h
  work merged upstream) and were dropped by git; 3 early martini2p2h commits superseded by
  upstream's final version and the `RandomGen` Pythia8-seeding port (upstream already has
  it) were dropped by hand. 23 commits remain, individually, with their original authors,
  plus follow-up commits that restore `config/HAIntranuke2018.xml`,
  `config/KellyELFormFactorsModel.xml` and `config/LwlynSmithFFCC.xml` to master's version
  (the branch had re-added sets master already has) and fix a double free in
  `INCLNucleus::reset` that the SBND branch never received (glibc ≥ 2.29 aborted at the second
  event of every INCL run).
- The INCL++ binary external (`inclxx_external/inclxx`, 346 files, 77 MB) was removed from
  the commit that added it, because INCL++ may not be redistributed; the SBND build recipe
  (`inclxx_external/sbnd`, README, `build_inclxx_external.sh`) stays.
- Conflicts were resolved with one rule: `master` wins for everything unrelated to INCL
  (Pythia8 hadronizer and decayer defaults, the current z-expansion and Nieves parameter
  sets, the final martini2p2h code), the INCL changes are re-applied on top. Three fixes
  were folded into the commits that needed them: `Make.include` links no `boost_system`,
  a duplicate old-format `lqcd` z-expansion set and a leftover `Pythia6Decayer2023` entry
  were removed.
- Result versus `master`: 117 files differ, almost all under `src/Physics` (the INCL
  interface, nuclear models and generators), `config/INCL26_07a`, `config/INCL26_09a` and
  the spectral-function data; the martini2p2h, `RandomGen` and application sources are
  identical to `master`.
- The branch also builds without INCL++ (`GENIE_ENABLE_INCL=0`, or the plain workspace with
  `GENIE_GIT_REF=feature/incl-v3_8`): verified 2026-11-02, 12 min with 16 jobs, 96 libraries,
  21 apps, 0 errors. The INCL interface is compiled only under `__GENIE_INCL_ENABLED__`.

## License

MIT, see `../LICENSE`, for the files in this repository. GENIE itself is Copyright (c)
2003-2026 The GENIE Collaboration and distributed under its own license, see
<http://copyright.genie-mc.org>. INCL++ is distributed under its own rules of use; it is
not part of this repository.
