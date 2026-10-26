# Install GENIE with pixi (Linux x86_64)

A self-contained, no-root, no-system-packages way to build the
[GENIE](http://www.genie-mc.org) neutrino event generator from the official
[GENIE-MC/Generator](https://github.com/GENIE-MC/Generator) `master` branch.
Every dependency (ROOT, Pythia8, LHAPDF, log4cpp, libxml2, GSL, the C++ compiler)
comes from [conda-forge](https://conda-forge.org) through [pixi](https://pixi.sh),
pinned in a lock file, so the same recipe gives the same environment on any
x86_64 Linux machine: laptop, desktop, cluster login node, or container.

Three commands do everything:

```bash
pixi install          # dependencies into ./.pixi  (~2.6 GB)
pixi run build-genie  # clone GENIE master, configure, build in-tree (~10 min on 16 cores)
pixi run smoke        # gmkspl -> gevgen -> gntpc, plus a Pythia8 check
```

Then `pixi shell` gives you a shell where `gevgen`, `gmkspl`, `gntpc`, `root` and
`python` (with PyROOT) all work.

**What you get:** GENIE `master`, Pythia8-only (Pythia6 is no longer supported by the
stock GENIE configurations since v3.8), LHAPDF6, the default `rw-2018` INTRANUKE
reweighting hooks, no INCL++, no Geant4, no Reweight package, no boosted dark matter
(see [Enabling extra GENIE options](#enabling-extra-genie-options)). The INCL++
intranuclear cascade is an optional add-on with its own section,
[GENIE with the INCL++ cascade](#optional-genie-with-the-incl-cascade).

**Last tested:** 2026-10-26 (see [Tested configuration](#tested-configuration) for the
exact versions). `master` moves every week; the smoke test at the end is your
acceptance check.

---

## 1. Prerequisites

- Linux, x86_64. (Other platforms would need their own conda-forge builds; not covered.)
- About 5 GB of free disk: 2.6 GB environment, 0.7 GB GENIE source + build, plus the
  splines and events you generate.
- Internet access to `conda.anaconda.org` and `github.com`.
- `curl`, `bash`, `git` is **not** needed on the host (pixi installs one).
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
cd genie-install
```

Everything below runs from inside this directory. The layout:

```
pixi.toml               dependencies, activation script, tasks
pixi.lock               exact package versions (commit it; `pixi install` honours it)
scripts/genie-env.sh    the environment contract (GENIE, XSECSPLINEDIR, PYTHIA8DATA, PATH, LD_LIBRARY_PATH)
scripts/build_genie.sh  clone + configure + build
scripts/smoke_test.sh   end-to-end check
scripts/build_inclxx.sh, scripts/smoke_test_incl.sh   optional INCL++ build and check (see below)
Generator/              GENIE checkout + in-tree build   (created by build-genie, git-ignored)
data/                   your cross-section splines       (= $XSECSPLINEDIR, git-ignored)
work/                   smoke-test output                (git-ignored)
```

## 3. Install the dependencies

```bash
pixi install
```

This resolves `pixi.toml` against the committed `pixi.lock` and unpacks the packages
into `./.pixi/envs/default`: about 190 packages, 2.7 GB of downloads, of which ROOT is
250 MB. That took 13 s on a data-centre link; expect a few minutes at home. Nothing is activated in your shell:
pixi activates the environment only for `pixi run …` and `pixi shell`.

What is in there and why:

| package | role |
|---|---|
| `root_base 6.40.*` | ROOT (C++ libraries, `root`, `rootcling`, PyROOT). `root_base` is ROOT without the jupyter/numba extras of the `root` meta-package. |
| `pythia8 8.312.*` | hadronization and decays; mandatory for GENIE ≥ 3.8 |
| `lhapdf 6.5.*` | parton densities (GENIE's LHAPDF5 interface is disabled) |
| `log4cpp 1.1.*`, `libnsl` | GENIE's message logger. `libnsl` is a run-time dependency the conda-forge `log4cpp` package forgets to declare. |
| `libxml2-devel` | XML parser; the headers live in the `-devel` split package |
| `gsl` | GNU Scientific Library |
| `cxx-compiler`, `binutils`, `make`, `git`, `perl` | toolchain. `cxx-compiler` brings the conda gcc/g++ that matches the libstdc++ ROOT was built with; `perl` runs GENIE's `./configure`. |

## 4. Build GENIE

```bash
pixi run build-genie                       # uses `nproc` parallel jobs
GENIE_NJOBS=8 pixi run build-genie         # or choose the job count yourself
pixi run build-genie > build.log 2>&1      # the build prints ~2500 lines; keep them
```

`scripts/build_genie.sh` does, in order:

1. **Preflight** – checks that `root-config`, `gsl-config`, `g++`, `perl`, the Pythia8 /
   LHAPDF / log4cpp / libxml2 headers and `libpythia8.so` are all in the environment,
   and prints their versions.
2. **Clone** – `git clone --depth 1 --branch master https://github.com/GENIE-MC/Generator.git Generator`
   if `Generator/configure` does not exist yet, and writes the commit it is building
   into `GENIE_COMMIT`. Set `GENIE_GIT_REF=R-3_08_00` (any tag or branch) to build
   something else; `GENIE_GIT_URL` points at a fork.
3. **Clean** – removes `lib/`, `bin/`, objects, dictionaries. Every run is a clean build.
4. **Configure** –
   ```
   ./configure --enable-pythia8 --disable-pythia6 \
               --with-pythia8-inc=$CONDA_PREFIX/include --with-pythia8-lib=$CONDA_PREFIX/lib \
               --disable-lhapdf5 --enable-lhapdf6 \
               --with-lhapdf6-inc=$CONDA_PREFIX/include --with-lhapdf6-lib=$CONDA_PREFIX/lib \
               --with-log4cpp-inc=$CONDA_PREFIX/include --with-log4cpp-lib=$CONDA_PREFIX/lib \
               --with-libxml2-inc=$CONDA_PREFIX/include/libxml2 --with-libxml2-lib=$CONDA_PREFIX/lib
   ```
   and asserts `GOPT_ENABLE_PYTHIA8=YES` in the generated `src/make/Make.config`.
5. **Build** – the four preparatory targets serially (they generate `GBuild.h`, which
   every library depends on), then each library group of the top-level Makefile with
   `make -j$GENIE_NJOBS`, then the apps, then GENIE's helper scripts, then one final
   serial `make` that must find nothing left to compile. A plain top-level `make -jN`
   is **not** used: GENIE's Makefile lets the header generation race the compiles.
6. **Checks** – `bin/gmkspl`, `bin/gevgen`, `bin/gntpc` exist; `lib/libGPhDcy.so` is
   linked against `libpythia8.so`; `ldd bin/gevgen` resolves every library. Creates
   `data/`.

The last line is `=== BUILD_OK in N min -- GENIE Generator master <sha> <date>`.
The install is **in-tree**: `$GENIE = ./Generator`, binaries in `Generator/bin`,
libraries in `Generator/lib`, configuration in `Generator/config`. There is no
`make install` step and nothing is copied anywhere else.

## 5. Verify

```bash
pixi run smoke
```

`scripts/smoke_test.sh` runs the standard chain in `work/smoke-<timestamp>/`:

| step | command | checks |
|---|---|---|
| 1 | `gmkspl -p 14 -t 1000060120 -n 30 -e 5 --event-generator-list CCQE --tune G18_02a_00_000` | the XML contains at least one `<spline>` |
| 2 | `gevgen -n 100 -p 14 -t 1000060120 -e 3 --cross-sections … --tune G18_02a_00_000 --event-generator-list CCQE` | `gntp.1.ghep.root` written |
| 3 | `gntpc -i gntp.1.ghep.root -f gst` | the `gst` tree has 100 entries (counted with ROOT) |
| 4 | `gmkspl -p 14 -t 1000010010 -n 30 -e 10 --event-generator-list CCDIS …` | DIS splines on a free proton |
| 5 | `gevgen -n 20 -p 14 -t 1000010010 -e 5 … --event-generator-list CCDIS` | the `This is PYTHIA version 8.312` banner appears, i.e. hadronization really runs through Pythia8 |

Steps 1–3 took 1 minute on the test machine; steps 4–5 took 8 minutes, because
`gmkspl` computes at least 30 knots per spline whatever `-n` says and DIS has seven of them. Skip them with `GENIE_SMOKE_DIS=0
pixi run smoke` if you only need the quick check. The last line is `=== SMOKE_OK`.

## 6. Use it

Interactive work:

```bash
pixi shell                 # a sub-shell with GENIE, ROOT, Pythia8 … on PATH/LD_LIBRARY_PATH
gevgen --help
root -l
python -c "import ROOT"    # PyROOT for the environment's Python
exit                       # leave the environment
```

One-off commands without entering the shell:

```bash
pixi run gmkspl -p 14 -t 1000180400 -n 100 -e 10 --tune G18_10a_02_11b -o data/numu_Ar40.xml
pixi run gevgen -n 1000 -p 14 -t 1000180400 -e 2.5 --cross-sections data/numu_Ar40.xml --tune G18_10a_02_11b
pixi run gntpc -i gntp.0.ghep.root -f gst
```

The environment contract set by `scripts/genie-env.sh` on every activation
(`pixi run genie-env` prints it):

| variable | value |
|---|---|
| `GENIE` | `<repo>/Generator` |
| `XSECSPLINEDIR` | `<repo>/data` |
| `ROOTSYS` | the pixi environment |
| `PYTHIA8DATA` | `$CONDA_PREFIX/share/Pythia8/xmldoc` |
| `PATH` | `$GENIE/bin` prepended |
| `LD_LIBRARY_PATH` | `$GENIE/lib:$CONDA_PREFIX/lib` prepended — required: GENIE links with `-Wl,--no-undefined` and no rpath, and `libGPhDcy.so` needs `libpythia8.so` |

Start from a clean shell. If another ROOT or conda environment is already activated
(thisroot.sh, a `conda activate`, an LCG view), its `LD_LIBRARY_PATH` entries sit
behind ours but can still confuse `rootcling`; deactivate it first.

## 7. Update or rebuild

```bash
git -C Generator pull          # move to the current master
pixi run build-genie           # always a clean rebuild
```

To switch to a release instead of `master`, remove the checkout and set the ref:

```bash
rm -rf Generator
GENIE_GIT_REF=R-3_08_00 pixi run build-genie
```

Dependencies are pinned by `pixi.lock`. `pixi update` re-resolves them to the newest
conda-forge builds; rebuild GENIE afterwards, since ROOT's C++ standard and the
compiler can change.

### Enabling extra GENIE options

`GENIE_CONFIGURE_EXTRA` appends to the `./configure` line, e.g.

```bash
GENIE_CONFIGURE_EXTRA="--enable-boosted-dark-matter" pixi run build-genie
GENIE_CONFIGURE_EXTRA="--enable-nucleon-decay --enable-atmo" pixi run build-genie
```

`./configure --help` inside `Generator/` lists them all. Options that need software
outside this environment (`--enable-incl`, `--enable-geant4`, `--enable-apfel`) are
not covered here. The GENIE Reweight package is a separate repository and is not built.

## Troubleshooting

- **The build uses one core.** `nproc` returns 1 in some containers and batch pods
  (`OMP_NUM_THREADS=1`). Pass `GENIE_NJOBS=<n>`.
- **`libnsl.so.3 => not found`** in the final `ldd` check (or at run time). Your
  environment predates the `libnsl` line in `pixi.toml`: `git pull && pixi install`.
- **`sh: line 1: quota: command not found`** during the "snapshot of the build
  environment" step is GENIE's own script probing disk quotas. Harmless.
- **`ld: warning: libpythia8.so, needed by …/libGPhDcy.so, not found`** followed by
  undefined `Pythia8::` references means the apps were linked outside the pixi
  activation. Always build through `pixi run build-genie`, never by sourcing things
  by hand.
- **`gmkspl` wrote an XML with no `<spline>`** — you asked for a channel that does
  not exist on that target, e.g. CCQE on a free proton (`-t 1000010010`, no bound
  neutron). The exit code is still 0. The smoke test uses carbon for that reason.
- **`gevgen` runs forever printing "Could not select interaction"** — you are
  generating at exactly the maximum energy of the spline (`-e 5` against a spline made
  with `-e 5`). Generate strictly inside the spline range.
- **`PYTHIA Error in Settings::mode: value is out of range`** — GENIE forwards
  `--seed` to Pythia8, which accepts at most 900000000.
- **`master` does not compile today.** It happens. Build the last commit this page was
  tested with (`GENIE_GIT_REF=<sha from the table below>` after `rm -rf Generator`), or a
  release tag, and open an issue in GENIE-MC/Generator.
- **Disk.** `.pixi/` 2.6 GB, `Generator/` 0.7 GB after the build. `pixi clean cache`
  drops the package cache once the environment exists.

## Tested configuration

Measured on 2026-10-26 on an AlmaLinux 9.8 x86_64 node (glibc 2.34) with
`GENIE_NJOBS=16`:

| item | value |
|---|---|
| GENIE Generator | `master` @ `795ebd0a5915ba042814336a692f2ead2ad18d1c` (2026-10-21) |
| pixi | 0.78.0 |
| compiler | conda-forge gcc/g++ 15.3.0 (`cxx-compiler 2.0.0`), libstdc++ 16.2 |
| ROOT | 6.40.04, conda-forge `cxx20` build → GENIE is compiled with `-std=c++20` |
| Pythia8 | 8.312 |
| LHAPDF | 6.5.6 |
| log4cpp | 1.1.4 (+ libnsl 2.0.1) |
| libxml2 | 2.15.4 |
| GSL | 2.8 |
| build | 10 min wall (`pixi run build-genie`, clean), 96 libraries, 21 apps, 0 errors |
| smoke steps 1–3 | 1 min (1 CCQE spline on C12, 100 events, 100 gst entries) |
| smoke steps 4–5 | 8 min (7 CCDIS splines on H1, 20 events, Pythia 8.312 banner, 0 Pythia errors) |

Notes for people who build GENIE by hand elsewhere:

- GENIE's `Make.include` hardcodes `CXX = g++` and assigns `CXXFLAGS`/`LDFLAGS` itself,
  so conda's exported `CXXFLAGS`/`LDFLAGS` are ignored; the only compiler input that
  matters is `root-config --cflags`, which is where `-std=c++20` comes from.
- The conda-forge `cxx-compiler` 2.x scheme installs a plain `g++` in the environment's
  `bin/` and exports no `CXX`/`CC` variables, so nothing has to be passed to `make`.
- `libxml2` headers are under `$CONDA_PREFIX/include/libxml2`, not `include/`.
- Pythia8 and LHAPDF from conda-forge are built with Python bindings; that is why a
  Python interpreter ends up in the environment.
- Outputs of this build are not bit-identical to a build with other dependency versions
  (e.g. Pythia 8.317 on the Fermilab spack stack): physics is the same, random sequences
  through Pythia8 are not.

## Optional: GENIE with the INCL++ cascade

GENIE can hand its final-state interactions (and, with the `INCL26_*` tunes, the
quasi-elastic vertex itself) to the [INCL++](https://irfu.cea.fr/dphn/Spallation/incl.html)
intranuclear cascade. This needs two extra things, both handled by the `incl`
environment of this repository:

- **INCL++ itself**, built from the GENIE-interface fork of INCL++ 6.34. INCL++ is
  developed by CEA-Irfu and the University of Liège, is available **on request from its
  authors** for non-commercial use, and **may not be redistributed** (see its
  `LICENSE.pdf`), so this repository contains no INCL++ code and the fork
  `git@github.com:LiangLiu212/inclxx.git` is private. Once you are authorised, point
  `INCLXX_GIT_URL` at the fork or at your own copy of the source tree.
- **GENIE with the INCL interface.** Official GENIE `master`/v3.8 ships only the old
  `HINCLCascadeIntranuke` interface. The full interface (INCL nuclear model, INCL QE
  vertex, INCL cascade, `INCL26_07a`/`INCL26_09a` tunes) lives on the branch
  `feature/incl-v3_8` of `https://github.com/LiangLiu212/Generator`, which is the
  production branch `feature/for_Anna` rebased onto the v3.8.0 release (R-3_08_00).

```bash
pixi install -e incl                        # default env + cmake + Boost (headers and libraries)
pixi run -e incl build-inclxx               # INCL++ -> ./inclxx           (about half a minute on 16 cores)
rm -rf Generator                            # if you built plain GENIE before
GENIE_GIT_URL=https://github.com/LiangLiu212/Generator.git GENIE_GIT_REF=feature/incl-v3_8 \
  pixi run -e incl build-genie              # GENIE v3.8 + INCL interface   (11 min on 16 cores)
pixi run -e incl smoke-incl                 # INCL26_09a: gmkspl -> gevgen -> gntpc on Ar40 (9 min)
pixi shell -e incl                          # work in it
```

`build-genie` enables `--enable-incl` automatically when `./inclxx/lib/libINCL_Physics.so`
exists (`GENIE_ENABLE_INCL=0` forces it off, `=1` makes a missing INCL++ an error). Always
use the `incl` environment for an INCL build: GENIE's INCL interface includes Boost headers.

The environment contract gains, when `./inclxx` exists:

| variable | value |
|---|---|
| `INCLXX_DIR` | `<repo>/inclxx` |
| `INCLXX_DATA_DIR` | `<repo>/inclxx/share` (INCL, ABLA07, ABLA++, GEMINI++ tables; `NucleusGenINCL.xml` reads it) |
| `PATH`, `LD_LIBRARY_PATH` | `inclxx/bin` and `inclxx/lib` prepended |

Knobs of `scripts/build_inclxx.sh`: `INCLXX_GIT_URL`, `INCLXX_GIT_REF` (default: the commit
SBND production uses), `INCLXX_NJOBS`, `INCLXX_BUILD_TYPE` (default `RelWithDebInfo`). The
CMake options are the ones of the validated SBND/DUNE installations (ABLA07, ABLA++, GEMINI++,
SMM and Fermi break-up de-excitation, ROOT I/O, no HDF5/protobuf).

Using it: tune ids are `INCL26_07a_00_000` (SF-Unified QE, LQCD z-expansion) and
`INCL26_09a_00_000` (Nieves QE, z-expansion, no RPA); both put the INCL cascade on every
channel. They need their own cross-section splines (`gmkspl … --tune INCL26_09a_00_000`).

Tested configuration (2026-10-26, same node as above, 16 jobs):

| item | value |
|---|---|
| INCL++ | 6.34, GENIE-interface fork @ `8a6c1cf17e99dacca026e0a4268de35e7843cb1a`, build 34 s, 9 libraries |
| GENIE | `feature/incl-v3_8` @ `df9e336d9a020f76b6467adda0e14c6e477a8c90` (R-3_08_00 + 22 commits), build 11 min, 96 libraries, 21 apps |
| Boost / CMake | 1.92.0 / 4.4.4 (conda-forge), the rest as in the table above |
| smoke | 20 "Default"-list numu Ar40 events at 1 GeV from a full INCL26_09a spline set: 26 s, exit 0, no FATAL; `gmkspl` numu Ar40 CCQE with the INCL26_09a nuclear model: 545 s; 50 CCQE events through the INCL cascade: 4 s, 50 gst entries, final-state hadrons in every event |

Notes:
- Boost ≥ 1.69 has no `libboost_system` (header-only). The branch's `Make.include` links
  only the Boost libraries that exist; upstream's hard-coded `-lboost_system` fails on
  modern Boost.
- The INCL++ libraries carry no rpath and reference each other; `inclxx/lib` must be on
  `LD_LIBRARY_PATH` (the activation script does it).
- The rebased branch also fixes a double delete of the INCL nucleus between events
  (`INCLNucleus::reset`) that older glibc never reported but glibc ≥ 2.29 aborts on
  (`free(): double free detected in tcache 2` at the second event).
- The INCL++ licence lets you build and run it; the resulting `inclxx/` directory and any
  container image containing it must not be passed on either.

## Other ways to install GENIE

This page covers the pixi route only. Companion pages for a spack-based build on the
Fermilab GPVMs and for a container image (Dockerfile + Apptainer definition that reuse
`scripts/build_genie.sh`) are planned in this repository.

## License

MIT, see `LICENSE`, for the files in this repository. GENIE itself is Copyright (c)
2003-2026 The GENIE Collaboration and distributed under its own license, see
<http://copyright.genie-mc.org>.
