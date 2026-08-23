# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **fork of [MetOffice/lfric_apps](https://github.com/MetOffice/lfric_apps)**
hosting **LFRic-Venus**: a Venus climate model built on LFRic. Upstream is the Met
Office's LFRic applications repository (GungHo dynamical core, transport, physics
schemes, SOCRATES radiation interface).

Read `venus/plan.md` first for the development plan — work packages, gates and
milestones. `venus/feasibility-assessment.md` has the underlying resource survey.

## Current status (2026-08-23)

WP0 of the plan. The build stack is proven — `gungho_model` compiles and links in the
container against local `lfric_core`. The model does **not** yet run: it segfaults on
the first XIOS diagnostic write (BUG-001, aarch64-only; hence the x86-64 requirement
below). Next step is running the C16 Earth example on the x86-64 image, then Venus
namelists. No Venus source code exists yet — `applications/venus_model/` and
`science/venus_physics/` are still to be created.

## Planning documents and bug log — mostly OUTSIDE this repo

| What | Where |
|---|---|
| Development plan, feasibility assessment | `venus/` (in this repo) |
| **Bug log** | `~/repos/lfric_venus_scoping/bug-log.md` |
| Planning archive | `~/repos/lfric_venus_scoping/` |

**Record defects in the bug log, not in this repo.** Bug detail is deliberately kept
out of the fork to stop churn flooding it. Code and README comments may *reference* a
bug ID (`BUG-001`) but must not restate the diagnosis. Check the bug log before
investigating any build or runtime failure — it may already be recorded, with the
experiments already ruled out.

## Fork conventions — the footprint must stay additive

- **`main` is pristine.** It tracks `upstream` (MetOffice/lfric_apps) and never
  receives Venus commits.
- **`venus` is the integration branch**, rebased onto `main` after each upstream sync.
  Work-package branches (`venus/wp0-dynamics`, ...) fork off it.
- **Never modify an upstream-owned file.** Every such edit is recurring rebase cost.
  `git diff --stat main..venus` should show additions under `venus/` (later also
  `applications/venus_model/`, `science/venus_physics/`) and nothing else. Where
  upstream behaviour must change, do it from outside the file — e.g. `dependencies.yaml`
  keeps its `git@github.com:` URLs and the container rewrites them to HTTPS via
  `git config --system url.…insteadOf`.
- Local-only ignores go in `.git/info/exclude`, not `.gitignore`.
- New Venus physics is **re-implemented** against published equations with VPCM as a
  reference, never copied: VPCM's ~614 unprotected `SAVE` variables are incompatible
  with PSyKAl kernels, which must be side-effect-free and thread-safe.

## Build and run — always x86-64, always in the container

The stack (MPICH, NetCDF, PSyclone, rose_picker, YAXT, pFUnit, XIOS) lives in the
`lfric_dev` image; the code is bind-mounted. Recipe and details: `venus/container/`.

```bash
cd venus/container && docker build --platform linux/amd64 -t lfric_dev:amd64 .
```

**Build x86-64 on both laptop and cluster** — emulated under QEMU on the laptop,
native under podman on the cluster. An aarch64 image builds but cannot run the model
(BUG-001); do not "fix" this by dropping `--platform`.

```bash
docker run -it --rm --ulimit stack=-1 \
  -v ~/repos/lfric_core:/lfric/core \
  -v ~/repos/lfric_apps:/lfric/apps \
  lfric_dev:amd64

# inside (login shell sets FC/FPP/LDMPI/FFLAGS/LDFLAGS):
cd /lfric/apps/applications/gungho_model
make -j4 build CORE_ROOT_DIR=/lfric/core APPS_ROOT_DIR=/lfric/apps
```

`lfric_core` is a **sibling clone at `~/repos/lfric_core`**, not a submodule; it is
consumed unmodified. `dependencies.yaml` pins the revision upstream expects — the
local clone may sit ahead of it.

### Running a model

Canonical launch, from `rose-stem/app/gungho_model/rose-app.conf`: 1 model rank + 1
XIOS server rank, `XIOS_SERVER_MODE=True`. Run `$CORE_ROOT_DIR/bin/tweak_iodef` first
— it resolves the `$METADATA` paths in `iodef.xml`, and `iodef.xml` also contains
relative includes (`../../lfric_atm/metadata`), so a run directory must sit at the
right depth or those includes break.

```bash
mpiexec -n 1 ../bin/gungho_model configuration.nml : -n 1 /opt/xios/bin/xios_server.exe
```

Run with `--ulimit stack=-1`; LFRic and XIOS both use large automatic arrays.

## Testing

LFRic ships the infrastructure VPCM lacked: **pFUnit** unit tests (`<project>/unit-test/`
mirroring `source/`; 258 in core, 315 in apps), Python-driven integration tests, and a
Cylc/Rose `rose-stem` suite with KGO, lint and config checks. Run one unit test with
`make unit-tests UNIT_TEST_FILTER=<name>`.

For a new planet, follow the existing precedent rather than inventing a pattern:
`rose-stem/app/gungho_model/opt/rose-app-{deep,shallow}-hot-jupiter.conf` and
`rose-app-tidally-locked-earth.conf` are Rose optional-config overlays setting
`planet_radius`, `domain_height`, `surface_pressure`, `theta_forcing`, `shallow` and an
initial temperature profile. `rose-app-venus.conf` should look like these. A green
Venus rose-stem test with KGO is part of the WP0 gate, not a follow-on task.

Keep kernel unit tests free of infrastructure objects — use the canned-data helpers in
`unit-test/support`, per LFRic's own testing guidance.

## Related repositories on this machine

| Repo | Role |
|---|---|
| `~/repos/lfric_core` | LFRic infrastructure — consumed unmodified |
| `~/repos/socrates_venus` | SOCRATES `um13.0_planets`; Venus SW spectral file exists, **no LW file** |
| `/mnt/c/Users/mc5526/Documents/repos/VPCM` | LMD Venus PCM — physics specification, never a source to copy |
| `~/repos/VPCM_refactors` | VPCM audit: the written spec for Venus physics + its known defects |
| `~/repos/VULCAN-Venus` | 1-D photochemistry; chemical network as data (62 species, 838 reactions) |
