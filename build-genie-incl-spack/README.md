# Install GENIE with the INCL++ cascade using the DUNE CVMFS Spack (Fermilab, AlmaLinux 9 x86_64)

## Quick start

```bash
git clone https://github.com/LiangLiu212/genie-install.git
cd genie-install/build-genie-incl-spack
bash scripts/setup_deps.sh       # once: pin the DUNE CVMFS Spack packages, build Boost (+timer), write spack-env.sh  (~4 min)
source setup_genie_incl.sh       # every new shell: ROOT, Pythia8, LHAPDF, ..., gcc 12.5 and the GENIE / INCL variables
bash scripts/build_inclxx.sh     # INCL++ 6.34 (GENIE-interface fork, access required) -> ./inclxx   (~1 min)
bash scripts/build_genie.sh      # GENIE feature/incl-v3_8 with the INCL interface -> ./Generator  (~9 min on 32 cores)
source setup_genie_incl.sh       # again, so that INCLXX_DIR is exported now that ./inclxx exists
bash scripts/smoke_test_incl.sh  # tune INCL26_09a: gmkspl -> gevgen -> gntpc on Ar40                (~22 min, one core)
gevgen --help                    # ready
```

From then on, every fresh login needs one line:

```bash
source /path/to/genie-install/build-genie-incl-spack/setup_genie_incl.sh
```

No spack command is ever typed: `setup_deps.sh` runs spack once and writes `spack-env.sh`,
a plain list of `export` lines; `setup_genie_incl.sh` sources it (fast, no python) and adds
the GENIE variables.

## What this is

The third workspace of this repository. [`../build-genie-pixi`](../build-genie-pixi) builds
plain GENIE `master` and [`../build-genie-incl-pixi`](../build-genie-incl-pixi) GENIE with
INCL++, both with every dependency from conda-forge through pixi, so they run anywhere. This
one builds the same GENIE + INCL++ but takes the dependencies from the
**DUNE Spack instance on CVMFS** (`/cvmfs/dune.opensciencegrid.org/spack`), the software stack
DUNE production uses: no download of ROOT, no conda, the exact ROOT / Pythia8 / LHAPDF / gcc
that DUNE's own `genie` package is built against. It is for Fermilab machines (GPVMs, the EAF,
batch nodes) and any host that mounts the DUNE CVMFS repository.

Same two ingredients as the pixi INCL workspace:

- **INCL++ 6.34**, built from its GENIE-interface fork. INCL++ is developed by CEA-Irfu and
  the University of Liège, is available **on request from its authors** for non-commercial
  use, and **may not be redistributed** (`LICENSE.pdf` in its source tree). This repository
  therefore contains no INCL++ code, and the fork `git@github.com:LiangLiu212/inclxx.git`
  is private. Once you are authorised, point `INCLXX_GIT_URL` at the fork or at your own
  copy of the source tree.
- **GENIE with the INCL interface**: branch
  [`feature/incl-v3_8`](https://github.com/LiangLiu212/Generator/tree/feature/incl-v3_8)
  of `LiangLiu212/Generator`, the SBND production branch rebased onto official GENIE
  `master` (see the pixi INCL README for how it was made).

**Where the dependencies come from.** `spack-config/deps.txt` pins nine packages by Spack
hash. They are exactly the packages that DUNE's `genie@3.06.02` of the
`dunesw-10_26_00d05-justin-01_06_05` environment was built against (its `spack.lock`):
gcc 12.5.0, ROOT 6.28.12 (C++17), Pythia8 8.317, LHAPDF 6.5.5, log4cpp 1.1.3, GSL 2.8,
CMake 3.31.11, and the system libxml2 2.9.13 that the instance declares as an external.
One compiler, one C++ standard, no mixing.

**The one thing CVMFS lacks.** INCL++ requires Boost `timer` (and GENIE's INCL interface links
`-lboost_timer`), and every Boost on the DUNE CVMFS is built `~timer`. `setup_deps.sh` therefore
runs one `spack install` of `boost@1.82.0 +timer +chrono +system +date_time +program_options
cxxstd=17 %gcc@12.5.0` (same version and compiler as the CVMFS Boost) into a **local install
tree** `./spack-packages`, chained to the read-only CVMFS trees through
`spack-config/upstreams.yaml`. Nothing is written to CVMFS, `$HOME/.spack` or `/tmp` beyond
spack's bootstrap cache. About 3 minutes on 32 cores; 160 MB installed, plus 130 MB of stage
and caches under `spack-stage/` that can be deleted afterwards.

**What you get:** GENIE `feature/incl-v3_8`, Pythia8-only, LHAPDF6, the INCL interface compiled
in (`--enable-incl`) and INCL++ under `./inclxx`; everything built with gcc 12.5 and `-std=c++17`
(ROOT 6.28's standard; the pixi workspaces use ROOT 6.40 and C++20).

**Last tested:** 2026-11-05 on the Fermilab EAF (see [Tested configuration](#tested-configuration)).

---

## 1. Prerequisites

- A host with `/cvmfs/dune.opensciencegrid.org` mounted, AlmaLinux 9 (the CVMFS packages are
  built for `almalinux9`, glibc 2.34) on an x86_64 CPU with AVX2 (the packages are
  `x86_64_v3` builds: an older CPU dies with `Illegal instruction`). Fermilab's GPVMs, the EAF
  and the batch nodes qualify.
- The system packages `libxml2-devel` (the Spack instance declares libxml2 as the system one)
  and `python3` (3.9; it runs spack), plus `git`, `make`, `perl`: all present on the
  Fermilab images.
- About 2 GB of free disk: 0.3 GB the local Boost and its stage, 0.7 GB GENIE, 0.4 GB
  INCL++ source + build + install, plus your splines and events. The dependencies themselves
  stay on CVMFS.
- Read access to an INCL++ source tree (see above). Clone access to the private fork is
  over SSH, so an SSH key registered with GitHub, or set `INCLXX_GIT_URL` to a local path.
- Internet access to `github.com` (the two clones) and, once, to the Boost source mirror
  (`spack install` fetches `boost_1_82_0.tar.bz2`; Fermilab's Spack mirrors are consulted first).
- No `sudo`. Nothing is written outside this directory except spack's bootstrap/user cache
  under `${TMPDIR:-/tmp}/$USER` (set by the instance's `setup-env.sh`).

## 2. Get this repository

```bash
git clone https://github.com/LiangLiu212/genie-install.git
cd genie-install/build-genie-incl-spack
```

Everything below runs from inside this directory. The layout:

```
setup_genie_incl.sh           source this in every shell: spack-env.sh + GENIE, XSECSPLINEDIR, PYTHIA8DATA, INCLXX_DIR, INCLXX_DATA_DIR, PATH, LD_LIBRARY_PATH
spack-config/deps.txt         the nine pinned CVMFS packages (name, spec/hash)
spack-config/upstreams.yaml   chains the read-only CVMFS install trees to the local one
spack-config/config.yaml      generated: local install tree, stage and caches (absolute paths; git-ignored)
scripts/setup_deps.sh         the only spack step: verify the pins, build Boost locally, write spack-env.sh
scripts/build_inclxx.sh       clone + cmake + build + install INCL++
scripts/build_genie.sh        clone + configure (--enable-incl) + build GENIE
scripts/smoke_test_incl.sh    end-to-end check with the INCL26_09a tune
scripts/smoke_test.sh         the plain G18_02a check (also works here)
spack-env.sh                  generated by setup_deps.sh: `spack load --sh` rewritten to prepend, + GI_PREFIX_* (git-ignored)
spack-packages/, spack-stage/ the local Boost install tree, build stage and caches (git-ignored)
inclxx-src/, inclxx-build/    INCL++ source clone and build tree   (created by build_inclxx.sh, git-ignored)
inclxx/                       INCL++ install: bin, lib, include, share (= $INCLXX_DIR, git-ignored)
Generator/                    GENIE checkout + in-tree build        (created by build_genie.sh, git-ignored)
data/                         your cross-section splines            (= $XSECSPLINEDIR, git-ignored)
work/                         smoke-test output                     (git-ignored)
```

## 3. Set up the dependencies (once)

```bash
bash scripts/setup_deps.sh                       # ~4 min, almost all of it the Boost build
bash scripts/setup_deps.sh > setup-deps.log 2>&1 # or keep the log
```

What it does, in order (`=== step` headers in the output):

1. Sources `/cvmfs/dune.opensciencegrid.org/spack/v1.2.2/share/spack/setup-env.sh` with
   `SPACK_PYTHON=/usr/bin/python3`. The instance's concretizer (clingo) was bootstrapped for the
   system python 3.9; with another python first on `PATH` (the EAF image puts a python 3.11
   there) spack would try to bootstrap into the read-only CVMFS tree and fail.
2. Writes `spack-config/config.yaml`: install tree `./spack-packages`, build stage and caches
   under `./spack-stage`. Every spack call below gets `-C spack-config`, which adds this scope
   and `upstreams.yaml` on top of the instance's own configuration; the CVMFS trees stay what
   they are, read-only upstreams.
3. Reads `spack-config/deps.txt`, runs `spack find -p` on the nine hashes and prints their
   install prefixes. A missing hash is an error: the CVMFS instance was changed, see
   [Update or rebuild](#8-update-or-rebuild).
4. `spack install -j N boost@1.82.0 +timer …` unless a Boost with `+timer` is already in the
   local tree. Only Boost itself is compiled; its compiler, gcc 12.5.0, comes from CVMFS
   (spack also drops a 9 MB `gcc-runtime` copy next to it).
5. Writes `spack-env.sh` from `spack load --sh <the eight loadable pins> <the Boost>`.
   `spack load --sh` prints absolute values that embed the caller's `PATH`; the script runs it
   in a minimal environment and rewrites every list variable to
   `export X="<spack dirs>${X:+:$X}"` (duplicates removed: spack lists each directory twice),
   so the file prepends in any shell. It adds `GI_PREFIX_<name>` for each package (the build
   scripts configure against them) and one more `LD_LIBRARY_PATH` line with the `lib`
   directories of Boost, Pythia8, LHAPDF, log4cpp, GSL, ROOT and the gcc 12.5 runtime:
   `spack load` sets `LD_LIBRARY_PATH` only for packages that ask for it (TBB here), because
   spack's own binaries use rpath, while GENIE and INCL++ do not. `CC`/`CXX`/`FC`/`F77` come
   from the gcc load.
6. Checks, in a fresh shell that sources the file: `g++` is the spack 12.5.0, `root-config`,
   `gsl-config`, `lhapdf-config`, `log4cpp-config` and `cmake` resolve, ROOT has MathMore,
   and a C++17 test program compiles and runs. The last line is `=== SETUP_DEPS_OK`.

Knobs: `GI_DUNE_SPACK` (another instance), `GI_SPACK_PYTHON`, `GI_DEPS_FILE`, `GI_BOOST_SPEC`,
`GI_NJOBS`. The job count defaults to the cgroup CPU quota (`/sys/fs/cgroup/cpu.max`) because
`nproc` honours `OMP_NUM_THREADS`, which the EAF sets to 1.

## 4. Enter the environment

```bash
source setup_genie_incl.sh
bash setup_genie_incl.sh --print        # shows the resulting variables
```

Bash only (it uses `BASH_SOURCE`). It refuses with a one-line hint if `spack-env.sh` does not
exist yet, sources it once per shell (a second `source` after a rebuild does not stack `PATH`
entries), then exports:

| variable | value |
|---|---|
| `GENIE` | `<this directory>/Generator` |
| `XSECSPLINEDIR` | `<this directory>/data` |
| `ROOTSYS` | the CVMFS ROOT prefix (from `spack load`) |
| `PYTHIA8DATA` | `$GI_PREFIX_PYTHIA8/share/Pythia8/xmldoc` |
| `INCLXX_DIR` | `<this directory>/inclxx` (only when `inclxx/lib/libINCL_Physics.so` exists) |
| `INCLXX_DATA_DIR` | `$INCLXX_DIR/share` (INCL, ABLA07, ABLA++, GEMINI++ tables; `NucleusGenINCL.xml` reads it) |
| `CC`, `CXX`, `FC` | the spack gcc 12.5.0 `gcc`, `g++`, `gfortran` |
| `GI_PREFIX_ROOT`, `GI_PREFIX_PYTHIA8`, … `GI_PREFIX_BOOST` | the install prefixes the build scripts configure against |
| `PATH` | `$GENIE/bin`, `$INCLXX_DIR/bin`, then the spack `bin` directories (gcc, cmake, ROOT, Pythia8, LHAPDF, …) prepended |
| `LD_LIBRARY_PATH` | `$GENIE/lib:$INCLXX_DIR/lib`, then the `lib` directories of Boost, Pythia8, LHAPDF, log4cpp, GSL, ROOT and the gcc 12.5 runtime (listed explicitly in `spack-env.sh`) prepended — required: GENIE links with `-Wl,--no-undefined` and no rpath to its dependencies, and the INCL++ libraries reference each other without rpath. (gcc 12.5's own `libstdc++.so.6`, GLIBCXX_3.4.30, newer than the AlmaLinux 9 one, is found even without it: the spack gcc stamps an RPATH to its `lib64` into everything it links.) |

`spack load` also loads the run-time dependencies of the pinned packages, so `python` becomes
the spack python 3.11 that ROOT was built against (PyROOT works) and `PYTHONPATH`,
`CMAKE_PREFIX_PATH`, `PKG_CONFIG_PATH`, `MANPATH` gain the corresponding entries.

## 5. Build INCL++

```bash
bash scripts/build_inclxx.sh                                   # ~1 min on 32 cores
INCLXX_GIT_URL=/path/to/inclxx bash scripts/build_inclxx.sh    # from your own copy of the source
```

Identical to the pixi INCL workspace's script except for where things come from: ROOT through
`ROOT_DIR` (spack's ROOT 6.28 keeps `ROOTConfig.cmake` in `share/root/cmake`, outside cmake's
search), the local Boost through `CMAKE_PREFIX_PATH`, the compilers through `CC`/`CXX`/`FC`. It clones the fork into `inclxx-src/` (if missing), checks out `INCLXX_GIT_REF`,
configures a clean build in `inclxx-build/` with the CMake options of the validated SBND/DUNE
installations, builds, installs into `inclxx/`, applies the two post-install fixes GENIE needs
(`G4INCLVersion.hh`, the ABLA++ `G4ABLA3.0` data path), asserts that cmake picked the local
Boost, that the nine shared libraries resolve, and that `libstdc++`/`libgfortran` resolve to
the gcc 12.5 runtime. The last line is `=== INCLXX_OK`.

Knobs: `INCLXX_GIT_URL`, `INCLXX_GIT_REF`, `INCLXX_NJOBS`, `INCLXX_BUILD_TYPE`.

`source setup_genie_incl.sh` again after this step: it exports `INCLXX_DIR` and puts
`inclxx/lib` on `LD_LIBRARY_PATH` only when `inclxx/lib/libINCL_Physics.so` exists.

## 6. Build GENIE

```bash
bash scripts/build_genie.sh                     # cgroup CPU quota parallel jobs
GENIE_NJOBS=8 bash scripts/build_genie.sh       # or choose the job count yourself
bash scripts/build_genie.sh > build.log 2>&1    # the build prints ~3100 lines; keep them
```

Same build pattern and checks as the pixi scripts (serial prep targets, one `-jN` make per
library group, a final serial `make`), with the `./configure` paths taken from the
`GI_PREFIX_*` variables:

```
--enable-pythia8 --disable-pythia6 --with-pythia8-inc=$GI_PREFIX_PYTHIA8/include --with-pythia8-lib=$GI_PREFIX_PYTHIA8/lib
--disable-lhapdf5 --enable-lhapdf6 --with-lhapdf6-inc=$GI_PREFIX_LHAPDF/include --with-lhapdf6-lib=$GI_PREFIX_LHAPDF/lib
--with-log4cpp-inc=$GI_PREFIX_LOG4CPP/include --with-log4cpp-lib=$GI_PREFIX_LOG4CPP/lib
--with-libxml2-inc=/usr/include/libxml2 --with-libxml2-lib=/usr/lib64
--enable-incl --with-incl-inc=$INCLXX_DIR/include --with-incl-lib=$INCLXX_DIR/lib --with-boost-inc=$GI_PREFIX_BOOST/include --with-boost-lib=$GI_PREFIX_BOOST/lib
```

The INCL line is added whenever `./inclxx/lib/libINCL_Physics.so` exists (`GENIE_ENABLE_INCL=0`
forces it off, `=1` makes a missing INCL++ an error). After the build it checks that
`gevgen` has no unresolved library and that its `libstdc++.so.6` is the gcc 12.5 one. The
last line is `=== BUILD_OK in N min -- GENIE Generator feature/incl-v3_8 <sha> <date>`.

Knobs: `GENIE_GIT_URL`, `GENIE_GIT_REF`, `GENIE_NJOBS`, `GENIE_CONFIGURE_EXTRA`,
`GENIE_ENABLE_INCL`, `GENIE_POST_CLEAN`.

## 7. Verify

```bash
source setup_genie_incl.sh                      # if not done since build_inclxx.sh
bash scripts/smoke_test_incl.sh
```

It runs in `work/smoke-incl-<timestamp>/`, printing each command and `done!` after every
passed step:

| step | command | checks |
|---|---|---|
| 1 | `gmkspl -p 14 -t 1000180400 -n 30 -e 5 --event-generator-list CCQE --tune INCL26_09a_00_000` | a spline is produced with the INCL nuclear model |
| 2 | `gevgen -n 50 -p 14 -t 1000180400 -e 1 --cross-sections … --tune INCL26_09a_00_000 --event-generator-list CCQE` | no `FATAL`, INCL output present in the log |
| 3 | `gntpc -i gntp.1.ghep.root -f gst` | 50 gst entries, final-state hadrons in the events, event 0 dumped |

Step 1 is the slow one: 22 minutes on the test machine (1327 s, single-threaded; the same
spline took 517 s in the pixi workspace with ROOT 6.40 / gcc 15 / C++20, a difference this
recipe does not try to explain); steps 2 and 3 take seconds.
The last line is `=== SMOKE_INCL_OK`. `bash scripts/smoke_test.sh`, the plain G18_02a check
with a Pythia8 DIS step, also passes in this build (19 minutes, see the table below).

## 8. Use it

Every new terminal:

```bash
source /path/to/genie-install/build-genie-incl-spack/setup_genie_incl.sh
gevgen --help
```

Tune ids are `INCL26_07a_00_000` (SF-Unified QE, LQCD z-expansion) and `INCL26_09a_00_000`
(Nieves QE, z-expansion, no RPA); both put the INCL cascade on every channel and need their
own cross-section splines:

```bash
gmkspl -p 14 -t 1000180400 -n 100 -e 10 --tune INCL26_09a_00_000 -o data/numu_Ar40_INCL26_09a.xml
gevgen -n 1000 -p 14 -t 1000180400 -e 2.5 --cross-sections data/numu_Ar40_INCL26_09a.xml --tune INCL26_09a_00_000
gntpc -i gntp.0.ghep.root -f gst
```

In a batch job or a `.bashrc`, the same `source` line works as long as the node mounts
`/cvmfs/dune.opensciencegrid.org` and can see this directory (e.g. `/exp/dune/app` or
`/exp/dune/data` on the Fermilab side). `spack-env.sh` carries absolute paths to this checkout
and to CVMFS; copying the directory elsewhere means running `setup_deps.sh` again there.

### Update or rebuild

```bash
git -C Generator pull && bash scripts/build_genie.sh      # move to the current feature/incl-v3_8 (always a clean rebuild)
bash scripts/build_inclxx.sh && bash scripts/build_genie.sh   # rebuild INCL++ from scratch, then GENIE
```

To move to other CVMFS packages (a newer `dunesw` set, a different ROOT), edit
`spack-config/deps.txt`, keeping one compiler and one `cxxstd` across the set; the hashes of a
consistent set are easiest to read off a `dunesw-*` environment's `spack.lock` under
`/cvmfs/dune.opensciencegrid.org/spack/environments/`. Then

```bash
rm -rf spack-packages spack-stage spack-env.sh   # if the compiler changed, so that Boost is rebuilt with it (adjust GI_BOOST_SPEC)
bash scripts/setup_deps.sh && source setup_genie_incl.sh
bash scripts/build_inclxx.sh && bash scripts/build_genie.sh && bash scripts/smoke_test_incl.sh
```

`spack find -lv root`, with the instance sourced (`SPACK_PYTHON=/usr/bin/python3 source
/cvmfs/dune.opensciencegrid.org/spack/v1.2.2/share/spack/setup-env.sh`), lists what is on offer;
the first call reads the whole CVMFS database and takes a few minutes, later ones seconds.

## Troubleshooting

- **`no Spack at /cvmfs/dune.opensciencegrid.org/spack/v1.2.2`.** The DUNE CVMFS repository is
  not mounted (`ls /cvmfs/dune.opensciencegrid.org`); on your own machine install cvmfs and
  add `dune.opensciencegrid.org` to its configuration, or use the pixi workspaces instead.
- **`cannot bootstrap the "clingo" Python module … Read-only file system`** from spack. Spack
  ran with a python other than `/usr/bin/python3`: `setup_deps.sh` sets `SPACK_PYTHON`, but if
  you source the instance by hand do the same. (The warnings `Ignoring write error on readonly
  …/bootstraps/…` and `Spack is trying attach a Python dependency` are the instance's own and harmless.)
- **`Read-only file system: /cvmfs/…/var/spack/cache/_source-cache`** during `spack install`.
  Spack did not get our `-C spack-config` scope (which redirects `source_cache` and the stage);
  run it as `setup_deps.sh` does: `spack -C /path/to/spack-config install …`.
- **`a pinned package is missing`** from `spack find`. The DUNE instance was updated and a
  hash in `deps.txt` is gone: pick the current set as in [Update or rebuild](#update-or-rebuild).
- **`error while loading shared libraries: libpythia8.so`** (or `libLHAPDF`, `liblog4cpp`,
  `libCore`, `libINCL_Physics`) when running `gevgen`. `LD_LIBRARY_PATH` lost the dependency
  directories in this shell: `source setup_genie_incl.sh` (`bash setup_genie_incl.sh --print`
  shows them). A `.bashrc` that assigns `LD_LIBRARY_PATH` after the source line, or a UPS
  `setup` of another ROOT, breaks it. `version 'GLIBCXX_3.4.30' not found` means a system
  `libstdc++` was put *in front* of the gcc 12.5 one.
- **`Illegal instruction`** from anything on CVMFS. The CPU lacks AVX2 (`x86_64_v3`); use
  another node.
- **`git clone git@github.com:LiangLiu212/inclxx.git` is refused.** You are not authorised
  for the private fork. Get the INCL++ source from its authors and point `INCLXX_GIT_URL`
  at your copy (a local path works).
- **`ld: cannot find -lboost_timer`** or cmake `Could NOT find Boost (missing: timer)`. The
  build is looking at the CVMFS Boost: `GI_PREFIX_BOOST` must point into `./spack-packages`
  (`setup_deps.sh` writes it; re-run it after `rm -rf spack-packages`).
- **`free(): double free detected in tcache 2` at the second event.** You are running an INCL
  branch without the `INCLNucleus::reset` fix of `feature/incl-v3_8`; update GENIE.
- **Everything builds with `-j1` and takes hours.** `nproc` returned 1 (`OMP_NUM_THREADS=1` on the
  EAF); the scripts read the cgroup quota instead, but `GENIE_NJOBS`/`INCLXX_NJOBS`/`GI_NJOBS`
  override it if your host reports neither.
- **The INCL++ install must not leave this machine.** The `inclxx/` directory and any copy of
  it fall under the INCL++ licence: build and run, do not pass on.

## Tested configuration

Measured on 2026-11-05 on a Fermilab EAF session (AlmaLinux 9.8, glibc 2.34, AMD EPYC 7542,
cgroup quota 32 CPUs / 64 GB) with 32 jobs:

| item | value |
|---|---|
| Spack instance | `/cvmfs/dune.opensciencegrid.org/spack/v1.2.2` (Spack 1.2.2) with upstream `v1.1.1`; the pins are the `dunesw-10_26_00d05-justin-01_06_05-prototype` set |
| compiler | spack gcc 12.5.0 (`/wrkusgq` on `PATH`; `gcc-runtime` 12.5.0 `/xbf4ipj`) |
| ROOT | 6.28.12 `/2rxgsmi`, `cxxstd=17` → GENIE is compiled with `-std=c++17` |
| Pythia8 / LHAPDF / log4cpp / libxml2 / GSL / CMake | 8.317 `/7lu7p2p` / 6.5.5 `/aadi2eq` / 1.1.3 `/e7abosg` / 2.9.13 (system) / 2.8 `/zgt5ddy` / 3.31.11 `/vavaqin` |
| Boost | 1.82.0 `+timer+chrono+system+date_time+program_options cxxstd=17 %gcc@12.5.0`, built locally in 3 min (`/bflrbak`, 160 MB) |
| setup_deps.sh | 4 min end to end (first run; seconds once the Boost exists) |
| INCL++ | 6.34, GENIE-interface fork @ `8a6c1cf17e99dacca026e0a4268de35e7843cb1a`, build 40 s, 9 libraries |
| GENIE Generator | `feature/incl-v3_8` @ `e60ed3b0` (2026-11-02) |
| GENIE build | 9 min wall (`scripts/build_genie.sh`, clean, `--enable-incl`, 32 jobs), 96 libraries, 21 apps, 0 errors |
| smoke (INCL26_09a) | 22 min: 1 CCQE spline on Ar40 with the INCL nuclear model (1327 s), 50 events at 1 GeV, 50 gst entries all with final-state hadrons (max 14 per event), 0 FATAL |
| smoke (G18_02a) | 19 min: C12 CCQE spline (2 min) + 100 events, H1 CCDIS 7 splines (17 min) + 20 events with the Pythia8 8.317 banner, 100 + 20 gst entries |

## License

MIT, see `../LICENSE`, for the files in this repository. GENIE itself is Copyright (c)
2003-2026 The GENIE Collaboration and distributed under its own license, see
`Generator/LICENSE` after the clone. INCL++ is distributed by its authors under the
rules in `inclxx-src/LICENSE.pdf` (non-commercial use, no redistribution). The CVMFS
packages carry their own licenses.
