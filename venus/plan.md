# LFRic-Venus: a modular development plan

*Drafted 2026-08-23. Companion to `feasibility-assessment.md` (same directory), which
holds the detailed resource survey and risk register. Resources: `~/repos/lfric_core`,
`~/repos/lfric_apps`, VPCM (`/mnt/c/.../repos/VPCM` + audit in `~/repos/VPCM_refactors`),
`~/repos/VULCAN-Venus`, SOCRATES `um13.0_planets` (currently in `lfric_core/SOCRATES`).*

---

## 0. Status

*Last updated 2026-08-28.*

**WP0 is under way; the build stack is proven and the model runs.** The C16 Earth
example completes on native x86-64 (podman, cluster) with XIOS diagnostics written.
This required rebuilding the container with parallel HDF5/NetCDF: serial NetCDF makes
XIOS fall back to `multiple_file`, unimplemented in its UGRID writer. A separate
aarch64-only XIOS stack overflow remains, so the container still targets **x86-64** on
both laptop (QEMU) and cluster (podman). Details and ruled-out hypotheses are in the
bug log at `~/repos/lfric_venus_scoping/bug-log.md` (BUG-001, BUG-004, BUG-005);
defect detail is deliberately kept out of this repo.

Done: fork set up with pristine `main` + `venus` branch, purely additive footprint;
container recipe (`venus/container/`); SOCRATES relocated to `~/repos/socrates_venus`;
Earth example running end to end.

Next: Venus namelists (WP0 step 2) — a `rose-app-venus.conf` following the
hot-Jupiter precedent below.

**Testing precedent found.** `rose-stem/app/gungho_model/opt/` already contains
`rose-app-deep-hot-jupiter.conf`, `rose-app-shallow-hot-jupiter.conf` and
`rose-app-tidally-locked-earth.conf` — planet-specific regression configs that set
`planet_radius`, `domain_height`, `surface_pressure`, `theta_forcing`, `shallow`
and an initial temperature profile as a Rose optional-config overlay. `rose-app-venus.conf`
follows that template directly; the non-Earth machinery is already exercised in
upstream CI. LFRic also ships 258 pFUnit unit tests in core and 315 in apps,
Python-driven integration tests, and KGO/lint/config checks in rose-stem — so
LFRic-Venus starts with the test infrastructure VPCM never had, and PSyKAl's
side-effect-free kernel rule structurally prevents the `SAVE`-state problem that
made VPCM physics untestable.

## 1. What each resource is for

| Resource | Role in LFRic-Venus | Used how |
|---|---|---|
| **lfric_core** | Substrate: fields, meshes, MPI, IO, PSyclone build | Consumed unmodified via `dependencies.yaml` |
| **lfric_apps** | Dycore (GungHo), transport (FFSL/MoL/SL + monotone limiters), planetary forcing options, SOCRATES interface, physics schemes library | **Forked**; hosts the new model |
| **VPCM** | Physical *specification* and validation counterpart; initial states for spin-up | Reference implementation — read, never ported verbatim |
| **VPCM_refactors audit** | The only written description of what Venus physics should do, plus a known-defect list (tickets 5–10) | Spec + "do not reproduce these bugs" list |
| **VULCAN-Venus** | Chemical network as *data* (438 reactions, 62 species); 1-D chemistry benchmark | Network source + validation target |
| **SOCRATES um13.0_planets** | Radiation engine, Venus SW spectral file, 2022–24 validation campaign, reference atmospheres | Plugged in via `dependencies.yaml` `socrates:` override |

### Findings that anchor the plan (verified in the local clones)

- `lfric_apps` planet constants are **runtime namelists** (`planet=cp,gravity,omega,rd,p_zero`;
  `extrusion=planet_radius`; orbital elements incl. obliquity/eccentricity). A dry
  Venus-parameter GungHo requires **no code change**.
- `external_forcing` already implements Held-Suarez, tidally-locked Earth, and shallow/deep
  hot-Jupiter thermal relaxation, plus a generic `theta_relaxation` (Newtonian relaxation to a
  user-supplied profile with user-supplied timescale). **The exoplanet machinery is in the
  repo** — the planetary-port precedent is confirmed, and the Venus spin-up vehicle exists.
- `interfaces/socrates_interface` is a self-contained sub-project; `dependencies.yaml` pins
  `socrates:` as a git source that can point at a local clone. The Venus SOCRATES swaps in at
  a designed seam.
- SOCRATES-Venus has a mature 280-band SW file + heating-rate/flux campaign against three
  reference atmospheres (incl. LMD's), **but no Venus LW spectral file** — the greenhouse
  half must be built (feasibility doc §4.4).
- `applications/lfric2lfric` and `lfricinputs` exist — relevant to regridding a VPCM state
  onto the cubed sphere for initialisation.
- `science/physics_schemes/source/boundary_layer` exists — candidate for reuse rather than
  re-implementing VPCM's BL.

## 2. Architecture

**LFRic-Venus = a fork of `lfric_apps` containing a new application, built from GungHo plus
a Venus physics package, using the repo's own extension seams.**

```
lfric_apps (fork)
├── applications/venus_model        ← NEW: starts as a copy of gungho_model
├── science/gungho                  ← dycore + transport, shared, minimal diffs
├── science/venus_physics           ← NEW: radiation control, clouds, chemistry, surface
│                                     (mirrors science/physics_schemes conventions)
├── interfaces/socrates_interface   ← extended for Venus gases/geometry
└── dependencies.yaml               ← socrates: → local um13.0_planets Venus build
                                      lfric_core: → pinned upstream revision
```

Principles:

1. **Start from `gungho_model`, not `lfric_atm`.** `gungho_model` is dynamics + idealised
   forcing with no Earth physics baggage (JULES, UKCA, CASIM). `lfric_atm` is the *pattern*
   for full-physics assembly, copied later, scheme by scheme.
2. **VPCM is a specification, not a source.** Its 614 unprotected `SAVE` variables are
   structurally incompatible with PSyKAl kernels (side-effect-free, thread-safe); the audit's
   severity-A defects are live in the code. Every Venus scheme is re-implemented against the
   papers + VPCM-as-reference, with audit tickets 5–10 as the defect exclusion list.
3. **Every work package has a standalone deliverable** — publishable or usable even if the
   full model never assembles.
4. **Keep the fork rebaseable**: one branch per work package, surgical diffs, rebase on each
   upstream `lfric_apps` release — the same discipline already documented for the VPCM
   monthly SVN port.

## 3. Work packages

### WP0 — Foundation: dry Venus dynamics *(months 0–9, ~1 FTE)* — **the decision gate**

1. Build `gungho_model` locally; reproduce an Earth Held-Suarez baseline (C24/C48).
2. Venus namelist: radius 6.052e6 m, g 8.87, Rd 191.8, p_zero 9.2e6 Pa, cp ~900 (see R1),
   Ω for the 243-day **retrograde** rotation — *verify the sign convention in GungHo's
   Coriolis setup; a namelist may never have received a negative/near-zero Ω*.
3. Extrusion to ~95 km with 70–90 levels (match VPCM's `z2sig` 78/90-level grids for
   comparability). C48 (~13.8k columns) ≈ VPCM's 96×96 resolution.
4. Venus temperature relaxation via `theta_relaxation`: profile from VIRA / VPCM
   temperatures, height-dependent timescale. If the generic mechanism is insufficient, add a
   `venus` option to `external_forcing` beside `deep_hot_jupiter` — that is the precedented
   extension point.
5. **Angular-momentum budget diagnostic** built in from the start (port the analysis from
   `venuslab/angular_momentum_budget.py` to run on LFRic output).
6. Add `rose-stem/app/gungho_model/opt/rose-app-venus.conf` plus a KGO, modelled on
   the existing hot-Jupiter configs, from the first working run — not retrofitted.
7. Run to gate **G1**: multi-Venus-year stability; AM drift quantified; superrotation
   spin-up qualitatively consistent with published relaxation-forced Venus GCMs; and a
   **green rose-stem Venus test with KGO** — testing is part of the gate, not a
   follow-on task.

*Standalone deliverable: "GungHo in the Venus regime" — publishable regardless of outcome.*
*If G1 fails on AM conservation, the project stops here at a cost of ~1 FTE-year, and the
VPCM modernisation track continues unaffected.*

### WP1 — Radiation *(months ~6–24, spectroscopist + 1 RSE)* — **the critical path**

- **1a. Build the Venus LW spectral file** (does not exist): correlated-k for 92-bar CO2,
  sub-Lorentzian far wings, CO2–CO2 CIA, H2SO4 cloud optics, 735→180 K. Specialist
  spectroscopy; the person behind `sp_sw_280_je_venus` ("je") is the natural owner. The Mars
  pair in `data/spectra/mars` (17 LW / 42 SW bands) is the template for the deliverable.
- **1b. Reduce the 280-band SW file to GCM cost** (~40 bands). Acceptance test: reproduce
  the existing `examples/venus` heating-rate campaign (`LMD/`, `Frandsen/`, `Krasnopolsky/`
  `.hrts` baselines).
- **1c. Extend `socrates_interface` for Venus**: gas list (13 absorbers incl. OSSO isomers),
  solar constant 2601 W m⁻², solar-zenith geometry for a 117-Earth-day solar day (thermal
  tides matter on Venus — no diurnal averaging), remove Earth-only assumptions.
- **1d. Offline column harness first**: run the coupled interface on VPCM reference columns
  and compare against both the SOCRATES campaign and VPCM's NER fluxes *before* any 3-D run.
- Gate **G2**: 1-D radiative(–convective) equilibrium temperature profile within agreed
  tolerance of VIRA / VPCM, at GCM-affordable cost (measure cost per column explicitly).

### WP2 — Clouds & aerosol *(months ~12–30, ~1 FTE)*

- **Milestone first: prescribed clouds.** Haus-type cloud profiles (`haus2.mxr` is already
  in `examples/venus`) as static input to radiation → a "physical Venus climate" model
  without microphysics risk. This is the configuration for the first full-radiation 3-D runs.
- Then interactive H2SO4 condensation cloud: re-implement VPCM's simple scheme
  (`cl_scheme=1`) as PSyKAl column kernels, with tickets 5/10 as the defect list; modal
  aerosol; couple to SOCRATES's sulphuric-acid aerosol type.
- The moment-based scheme (`cl_scheme=2`) is **out of scope for v1** (16 audit findings, 5
  severity-A).

### WP3 — Chemistry *(months ~18–36+, ~1 FTE, fully parallel)*

- **3a. Network as data** *(can start any time, few weeks)*: extract VPCM's hardcoded
  network (`indice` + `krates`, ~4,700 lines of longhand Fortran with load-bearing
  ordering) into a machine-readable table; diff against VULCAN-Venus's 438-reaction
  network. *Standalone science deliverable: where do the two Venus chemistries disagree?*
- **3b. Kernel generator**: emit PSyKAl-clean column kernels (no saved state, explicit
  arguments, analytic or index-assembled Jacobian) from the network table — following
  VULCAN's `make_chem_funs.py` generator pattern, targeting the VPCM-style per-level
  implicit solve. Regenerable when the network changes.
- **3c. Tracer transport**: ~30–55 species through FFSL with monotone limiting; cost and
  memory assessment at C48; tracer registration via the inventory component.
- Validation: 1-D column vs VULCAN-Venus steady state and VPCM `rcm1d`.
- **Thermosphere/ionosphere chemistry excluded from v1** (feasibility doc §4.7).

### WP4 — Surface & boundary layer *(months ~12–18, small)*

- Evaluate reusing `science/physics_schemes/source/boundary_layer` before re-implementing
  VPCM's; Venus needs stable-BL behaviour under weak insolation at 92 bar.
- Simple surface energy balance + soil; VPCM's `soil.F` is the spec *minus* its
  `intent(OUT)` read bug (ticket 7 A1).

### WP5 — Assembly, spin-up & validation *(months ~24–48, ~1.5 FTE)*

- Assemble `venus_model` incrementally: dry+relaxation (WP0) → prescribed clouds + radiation
  (WP1+WP2 milestone) → interactive clouds → chemistry.
- **Spin-up strategy** (the compute wall): long relaxation-forced spin-up to a superrotating
  state → handover to full radiation; initialise from a regridded VPCM state
  (`lfric2lfric` / `lfricinputs` as the starting point for lat-lon → cubed-sphere state
  regridding); reduced radiation call frequency.
- Validation ladder: idealised (G1 cases) → 1-D columns (G2, VULCAN, `rcm1d`) → 3-D
  intercomparison with VPCM (not as truth) → observations (VIRA, VEx/VIRTIS — existing
  expertise + `VIRTIS_code` — and Akatsuki).
- rose-stem suite + KGO tests from the first assembled configuration, not retrofitted.

### WP6 — Infrastructure *(continuous, low-level)*

- Fork/branch strategy and upstream rebase cadence; container images for the build stack
  (PSyclone, XIOS, YAXT — the LFRic dependency list); CI on the fork; documentation.
- Housekeeping now: move `SOCRATES/` + tarball out of the `lfric_core` clone (2.5 GB + 2.4 GB,
  currently untracked inside a git repo).

## 4. Sequencing

```
      0     6     12    18    24    30    36    42    48 months
WP0   ████████──G1
WP1         ████████████████──G2──────┐
WP2               ██████████████████──┤ (prescribed-cloud milestone at ~18)
WP3               ██████████████████████████──┐   (3a anytime)
WP4               ████████                    │
WP5                        ██████████████████████████████
WP6   ────────────────────────────────────────────────────
```

Two hard gates: **G1** (month ~9: AM-conserving superrotating dry Venus) and **G2**
(month ~18–24: affordable, validated Venus radiation column). Everything after G2 is
engineering and science, not existential risk.

**Milestones with standalone value:** M1 dry superrotating Venus on the cubed sphere (G1);
M2 validated SOCRATES Venus column, SW+LW (G2); M3 prescribed-cloud radiative Venus GCM
(~month 24–30 — already a publishable, usable model); M4 interactive clouds (~36);
M5 chemistry-coupled (~48).

## 5. Open risks (register lives in the feasibility doc)

| # | Risk | Handling |
|---|---|---|
| R1 | **Variable cp** — Venus cp varies ~2× with height; GungHo's `planet=cp` is a scalar and constant-cp Exner thermodynamics is baked into the semi-implicit solver | Raise with the GungHo team in **month 1**; quantify the error of constant-cp in WP0; options: accept+quantify / T-dependent κ / generalised θ à la LMD |
| R2 | AM conservation in the superrotating regime | WP0 gate G1; diagnostic first, dynamics second |
| R3 | No Venus LW spectral file; spectroscopy expertise is the scarce resource | WP1a; identify the owner before committing the phase |
| R4 | Spin-up compute (decadal radiative timescales) | Relaxation-forced spin-up + VPCM-state initialisation + call-frequency reduction, designed in from WP0/WP5 |
| R5 | Retrograde/slow rotation sign conventions and untested parameter corners | Explicit WP0 checklist item |
| R6 | Solo capacity — the plan needs ~2–3 FTE from ~month 12 | Phase 0 is deliberately 1-FTE; G1 output is the funding/collaboration case |
| R7 | Fork drift against `lfric_apps` releases | WP6 rebase discipline (proven pattern from VPCM work) |

## 6. First five concrete actions

1. ~~Build `gungho_model` from the local clones~~ (done) — run its example (Earth,
   C16) on the x86-64 image.
2. Ask the GungHo team the variable-cp question (R1) — their answer shapes WP0.
3. Establish provenance/ownership of `sp_sw_280_je_venus` and availability for WP1a.
4. Write the Venus namelist set + VIRA relaxation profile; attempt the first dry Venus run.
5. ~~Move SOCRATES out of the `lfric_core` clone into `~/repos/socrates_venus`.~~ (done)
