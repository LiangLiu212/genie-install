# Install GENIE with pixi (Linux x86_64)

A self-contained, no-root, no-system-packages way to build the
[GENIE](http://www.genie-mc.org) neutrino event generator from the official
[GENIE-MC/Generator](https://github.com/GENIE-MC/Generator) `master` branch.
Every dependency (ROOT, Pythia8, LHAPDF, log4cpp, libxml2, GSL, the C++ compiler)
comes from [conda-forge](https://conda-forge.org) through [pixi](https://pixi.sh),
pinned in a lock file, so the same recipe gives the same environment on any
x86_64 Linux machine: laptop, desktop, cluster login node, or container.

The whole route, from a bare machine:

```bash
curl -fsSL https://pixi.sh/install.sh | sh     # pixi itself, once per machine; then open a new shell
git clone https://github.com/LiangLiu212/genie-install.git
cd genie-install/build-genie-pixi
pixi install                   # the dependencies listed in pixi.toml, pinned by pixi.lock, into ./.pixi  (~2.6 GB)
pixi shell                     # sub-shell with ROOT, Pythia8, … on PATH and the GENIE variables set
bash scripts/build_genie.sh    # clone GENIE master, configure, build in-tree (~12 min on 16 cores)
bash scripts/smoke_test.sh     # gmkspl -> gevgen -> gntpc, plus a Pythia8 check
gevgen --help                  # ready; `exit` leaves the sub-shell
```

pixi is used for two commands only: `pixi install` once, and `pixi shell` whenever you
open a new terminal. Everything inside that sub-shell is plain bash: the two scripts,
then `gevgen`, `gmkspl`, `gntpc`, `root` and `python` (with PyROOT). A batch job or a
shell rc can even skip `pixi shell`, see [Without pixi at all](#without-pixi-at-all).

**What you get:** GENIE `master`, Pythia8-only (Pythia6 is no longer supported by the
stock GENIE configurations since v3.8), LHAPDF6, the default `rw-2018` INTRANUKE
reweighting hooks, no INCL++, no Geant4, no Reweight package, no boosted dark matter
(see [Enabling extra GENIE options](#enabling-extra-genie-options)). GENIE with the
INCL++ intranuclear cascade is a separate workspace of this repository,
`../build-genie-incl-pixi`.

**Last tested:** 2026-11-02 (see [Tested configuration](#tested-configuration) for the
exact versions). `master` moves every week; the smoke test at the end is your
acceptance check.

---

## 1. Prerequisites

- Linux, x86_64. (Other platforms would need their own conda-forge builds; not covered.)
- About 5 GB of free disk: 2.6 GB environment, 0.6 GB GENIE source + build, plus the
  splines and events you generate.
- Internet access to `conda.anaconda.org` and `github.com`.
- `curl`, `bash`. `git` is **not** needed on the host (pixi installs one).
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
cd genie-install/build-genie-pixi
```

Everything below runs from inside this directory: pixi uses the `pixi.toml` of the
directory you are in (or the nearest parent that has one), and this one is a complete
workspace on its own. The layout:

```
pixi.toml               dependencies, activation script, tasks
pixi.lock               exact package versions (commit it; `pixi install` honours it)
scripts/genie-env.sh    the environment contract (GENIE, XSECSPLINEDIR, PYTHIA8DATA, PATH, LD_LIBRARY_PATH)
scripts/build_genie.sh  clone + configure + build
scripts/smoke_test.sh   end-to-end check
Generator/              GENIE checkout + in-tree build   (created by build_genie.sh, git-ignored)
data/                   your cross-section splines       (= $XSECSPLINEDIR, git-ignored)
work/                   smoke-test output                (git-ignored)
genie-setup.sh          optional `pixi shell-hook` output to `source` without pixi (git-ignored)
```

## 3. Install the dependencies

```bash
pixi install
```

This resolves `pixi.toml` against the committed `pixi.lock` and unpacks the packages
into `./.pixi/envs/default`: 187 packages, 2.6 GB on disk, of which ROOT is 244 MB.
The first install downloads about 2.7 GB (a few minutes at home, seconds on a
data-centre link); later installs on the same machine come from pixi's package cache
(20 s here). Nothing is activated in your current shell: the environment comes alive
only inside `pixi shell` (next section) or, for one command, `pixi run …`.

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

## 4. Enter the environment and build GENIE

```bash
pixi shell                                      # the prompt gains "(build-genie-pixi)"
bash scripts/build_genie.sh                     # uses `nproc` parallel jobs
GENIE_NJOBS=8 bash scripts/build_genie.sh       # or choose the job count yourself
bash scripts/build_genie.sh > build.log 2>&1    # the build prints ~2900 lines; keep them
```

`pixi shell` starts a sub-shell with `.pixi/envs/default/bin` on `PATH`, `CONDA_PREFIX`
pointing at the environment, and `scripts/genie-env.sh` sourced (the `[activation]`
entry of `pixi.toml`), which sets `GENIE`, `XSECSPLINEDIR`, `PYTHIA8DATA` and
`LD_LIBRARY_PATH`. The build script needs all of that, so run it inside the sub-shell,
not from a plain shell. (`pixi run build-genie` is the non-interactive equivalent for a
container recipe or CI; the tasks in `pixi.toml` just call the same scripts.)

The script does, in order:

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
bash scripts/smoke_test.sh                      # still inside the pixi shell
```

It runs the standard chain in `work/smoke-<timestamp>/`:

| step | command | checks |
|---|---|---|
| 1 | `gmkspl -p 14 -t 1000060120 -n 30 -e 5 --event-generator-list CCQE --tune G18_02a_00_000` | the XML contains at least one `<spline>` |
| 2 | `gevgen -n 100 -p 14 -t 1000060120 -e 3 --cross-sections … --tune G18_02a_00_000 --event-generator-list CCQE` | `gntp.1.ghep.root` written |
| 3 | `gntpc -i gntp.1.ghep.root -f gst` | the `gst` tree has 100 entries (counted with ROOT) |
| 4 | `gmkspl -p 14 -t 1000010010 -n 30 -e 10 --event-generator-list CCDIS …` | DIS splines on a free proton |
| 5 | `gevgen -n 20 -p 14 -t 1000010010 -e 5 … --event-generator-list CCDIS` | the `This is PYTHIA version 8.312` banner appears, i.e. hadronization really runs through Pythia8 |

Steps 1–3 took 1 minute on the test machine; steps 4–5 took 8 minutes in the 2026-10-26 test on the same node (not re-timed on 2026-11-02), because
`gmkspl` computes at least 30 knots per spline whatever `-n` says and DIS has seven of them. Skip them with `GENIE_SMOKE_DIS=0
bash scripts/smoke_test.sh` if you only need the quick check. The last line is `=== SMOKE_OK`.

## 6. Use it

Every new terminal:

```bash
cd genie-install/build-genie-pixi
pixi shell                 # the only pixi command you need from now on
gevgen --help
root -l
python -c "import ROOT"    # PyROOT for the environment's Python
exit                       # leave the environment
```

A typical session inside the sub-shell:

```bash
gmkspl -p 14 -t 1000180400 -n 100 -e 10 --tune G18_10a_02_11b -o data/numu_Ar40.xml
gevgen -n 1000 -p 14 -t 1000180400 -e 2.5 --cross-sections data/numu_Ar40.xml --tune G18_10a_02_11b
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
| `PATH` | `$GENIE/bin` prepended |
| `LD_LIBRARY_PATH` | `$GENIE/lib:$CONDA_PREFIX/lib` prepended — required: GENIE links with `-Wl,--no-undefined` and no rpath, and `libGPhDcy.so` needs `libpythia8.so` |

Start from a clean shell. If another ROOT or conda environment is already activated
(thisroot.sh, a `conda activate`, an LCG view), its `LD_LIBRARY_PATH` entries sit
behind ours but can still confuse `rootcling`; deactivate it first.

### Without pixi at all

`pixi shell` is nothing more than a bash sub-shell that has sourced an activation
script. pixi can print that script, so a batch job, a cron entry or your `~/.bashrc`
can source it directly and never run pixi:

```bash
pixi shell-hook -s bash > genie-setup.sh        # once, after `pixi install` (inside build-genie-pixi/)
source /path/to/build-genie-pixi/genie-setup.sh # in any later bash: GENIE, ROOT, Pythia8 … are set
```

The file is a plain list of `export` and `. …` lines with this machine's absolute paths
(it includes `scripts/genie-env.sh`), so it is tied to this checkout and this machine.
Regenerate it after `pixi update`. It is git-ignored.

## 7. Update or rebuild

Inside the pixi shell:

```bash
git -C Generator pull          # move to the current master
bash scripts/build_genie.sh    # always a clean rebuild
```

To switch to a release instead of `master`, remove the checkout and set the ref:

```bash
rm -rf Generator
GENIE_GIT_REF=R-3_08_00 bash scripts/build_genie.sh
```

Dependencies are pinned by `pixi.lock`. `pixi update` re-resolves them to the newest
conda-forge builds; afterwards leave the sub-shell (`exit`), run `pixi shell` again so
it picks up the new environment, and rebuild GENIE, since ROOT's C++ standard and the
compiler can change.

### Enabling extra GENIE options

`GENIE_CONFIGURE_EXTRA` appends to the `./configure` line, e.g.

```bash
GENIE_CONFIGURE_EXTRA="--enable-boosted-dark-matter" bash scripts/build_genie.sh
GENIE_CONFIGURE_EXTRA="--enable-nucleon-decay --enable-atmo" bash scripts/build_genie.sh
```

`./configure --help` inside `Generator/` lists them all. Options that need software
outside this environment (`--enable-geant4`, `--enable-apfel`) are not covered here;
`--enable-incl` is what the sibling workspace `../build-genie-incl-pixi` is for. The
GENIE Reweight package is a separate repository and is not built.

## Troubleshooting

- **`bash scripts/build_genie.sh` stops at once with `CONDA_PREFIX: not inside the pixi
  environment`** (or `smoke_test.sh` with `GENIE is not set`). You ran it from a plain
  shell: `pixi shell` first, or `source genie-setup.sh`.
- **`pixi shell` activates the wrong thing, or `pixi install` complains about the
  manifest.** You are not inside `build-genie-pixi/`; pixi uses the `pixi.toml` of the
  current directory or the nearest parent. `cd` here, or pass
  `--manifest-path /path/to/build-genie-pixi/pixi.toml`.
- **`WARN Using local manifest … rather than … from environment variable PIXI_PROJECT_MANIFEST`**
  means your site exports a global `PIXI_PROJECT_MANIFEST`; pixi correctly prefers the
  workspace you are in. Harmless.
- **The build uses one core.** `nproc` returns 1 in some containers and batch pods
  (`OMP_NUM_THREADS=1`). Pass `GENIE_NJOBS=<n>`.
- **`libnsl.so.3 => not found`** in the final `ldd` check (or at run time). Your
  environment predates the `libnsl` line in `pixi.toml`: `git pull && pixi install`.
- **`sh: line 1: quota: command not found`** during the "snapshot of the build
  environment" step is GENIE's own script probing disk quotas. Harmless.
- **`ld: warning: libpythia8.so, needed by …/libGPhDcy.so, not found`** followed by
  undefined `Pythia8::` references means the apps were linked without the environment
  active (no `LD_LIBRARY_PATH` to `$CONDA_PREFIX/lib`). Build inside `pixi shell` or
  after `source genie-setup.sh`, never by pointing a plain shell at `.pixi/` by hand.
- **`gmkspl` wrote an XML with no `<spline>`** — you asked for a channel that does
  not exist on that target, e.g. CCQE on a free proton (`-t 1000010010`, no bound
  neutron). The exit code is still 0. The smoke test uses carbon for that reason.
- **`gevgen` runs forever printing "Could not select interaction"** — you are
  generating at exactly the maximum energy of the spline (`-e 5` against a spline made
  with `-e 5`). Generate strictly inside the spline range.
- **`PYTHIA Error in Settings::mode: value is out of range`** — GENIE forwards
  `--seed` to Pythia8, which accepts at most 900000000.
- **`master` does not compile today.** It happens. Build the last commit this page was
  tested with (`rm -rf Generator; GENIE_GIT_REF=<sha from the table below> bash scripts/build_genie.sh`), or a
  release tag, and open an issue in GENIE-MC/Generator.
- **Disk.** `.pixi/` 2.6 GB, `Generator/` 0.6 GB after the build. `pixi clean cache`
  drops the package cache once the environment exists.

## Tested configuration

Measured on 2026-11-02 on an AlmaLinux 9.8 x86_64 node (glibc 2.34) with
`GENIE_NJOBS=16`:

| item | value |
|---|---|
| GENIE Generator | `master` @ `e2e04f19e96d395ac646cf3382841646b60fa1b4` (2026-10-27) |
| pixi | 0.78.0 |
| compiler | conda-forge gcc/g++ 15.3.0 (`cxx-compiler 2.0.0`), libstdc++ 16.2 |
| ROOT | 6.40.04, conda-forge `cxx20` build → GENIE is compiled with `-std=c++20` |
| Pythia8 | 8.312 |
| LHAPDF | 6.5.6 |
| log4cpp | 1.1.4 (+ libnsl 2.0.1) |
| libxml2 | 2.15.4 |
| GSL | 2.8 |
| build | 12 min wall (`scripts/build_genie.sh`, clean), 96 libraries, 21 apps, 0 errors |
| smoke steps 1–3 | 1 min (1 CCQE spline on C12, 100 events, 100 gst entries) |
| smoke steps 4–5 | 8 min, measured 2026-10-26 on the same node and dependency versions (GENIE master 795ebd0a); not re-timed on 2026-11-02 (7 CCDIS splines on H1, 20 events, Pythia 8.312 banner) |

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

## Other ways to install GENIE

This workspace covers the plain pixi route only. Its sibling `../build-genie-incl-pixi`
adds the INCL++ intranuclear cascade. Pages for a spack-based build on the Fermilab
GPVMs and for a container image (Dockerfile + Apptainer definition that reuse
`scripts/build_genie.sh`) are planned in this repository.

## License

MIT, see `../LICENSE`, for the files in this repository. GENIE itself is Copyright (c)
2003-2026 The GENIE Collaboration and distributed under its own license, see
<http://copyright.genie-mc.org>.
