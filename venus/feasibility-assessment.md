# LFRic-Venus: resource overview and feasibility assessment

*Drafted 2026-08-23. Sources surveyed: `lfric_core` @ `a117080c7` (2026-08-21);
VPCM @ `/mnt/c/Users/mc5526/Documents/repos/VPCM` (SVN 4343 per the existing audit);
`~/repos/VULCAN-Venus`; `~/repos/VPCM_refactors` (notes + tickets).
SOCRATES-Venus was **not on disk** and could not be inspected.*

---

## 1. Resource inventory

### 1.1 LFRic Core — the substrate, not a model

| Area | LOC | What it gives you |
|---|---:|---|
| `infrastructure/source` | 55,464 | Fields, function spaces, meshes, extrusion, MPI partition + halos (YAXT), NetCDF/UGRID IO, config |
| `components/science` | 40,250 | FEM operators, mass matrices, projections, solvers, geometry kernels |
| `mesh_tools` | 10,753 | Cubed-sphere / unstructured mesh generation |
| `components/lfric-xios` | 7,045 | XIOS IO server API |
| `components/driver`, `inventory` | 8,955 | Top-level calling tree, field/tracer inventory |
| miniapps | ~6,700 | `skeleton`, `simple_diffusion`, `io_demo`, `lbc_demo`, `coupled` |
| **Total** | **147,172** | |

Also: PSyclone PSyKAl code generation, Rose-metadata-driven namelist generation,
pFUnit unit-test framework, Cylc/Rose test suite, BSD-3 licence, public GitHub,
actively developed.

**Critical structural fact.** LFRic Core contains **no dynamical core, no transport
scheme and no physics**. I grepped for hardwired Earth constants (radius, Ω, g, R_d,
c_p) across `infrastructure/`, `components/` and `mesh_tools/` — there are none; the
only `planet` namelist entries in `components/driver/rose-meta/.../vn3.2` are
`planet_radius` (extrusion) and a radius `scaling_factor`. That is good news
(the substrate is planet-agnostic) and bad news (it is a substrate).

The GungHo dynamical core, the transport scheme, the physics packages and the
SOCRATES coupling all live in **`lfric_apps`** — a separate repository, referenced
from `documentation/source/getting_started/installation/software_dependencies.rst`,
with its own `dependencies.yaml` pinning a specific `lfric_core` revision.

> **This is the #1 gating question of the whole project.** "Build a Venus model on
> LFRic Core" and "adapt LFRic-Atmosphere to Venus" are two projects separated by
> roughly a factor of ten in effort. Only the second is realistic.

*Precedent worth checking (from my background knowledge, not verified in-repo):*
LFRic-Atmosphere has already been configured for non-Earth planets by the
Exeter/Met Office exoplanet group — Sergeev, Mayne et al., *GMD* 2023, idealised
3-D flows on terrestrial planets including TRAPPIST-1e. If accurate, the
planetary-configurability machinery (rotation rate, radius, gravity, gas constants,
insolation) has already been exercised, and that group is the obvious first
collaborator. **Verify this before relying on it.**

### 1.2 VPCM (LMD Venus PCM, OU fork) — the science asset

`LMDZ.VENUS/libf/phyvenus`: **67,060 lines**, 135 files (69 fixed-form `.F`,
57 free-form `.F90`). Everything outside `phyvenus` is a symlink into
`LMDZ.COMMON`. Licence: **CeCILL v2**.

| Category | Lines |
|---|---:|
| Chemistry & photolysis (`photochemistry_venus.F90` alone = 7,684) | 16,910 |
| Thermosphere / NLTE / ionosphere | 15,798 |
| Radiative transfer | 9,172 |
| Cloud microphysics (`cloudvenus/`, two schemes) | 7,054 |
| Driver & infrastructure (`physiq_mod.F` = 2,356) | 6,966 |
| Boundary layer / turbulence / surface | 4,269 |
| Gravity-wave drag | 2,954 |
| Aerosol optical properties | 1,760 |
| Tracers & misc | 1,553 |
| 1-D driver (`dyn1d/rcm1d.F`) | 624 |

Radiation is heterogeneous: an NER-matrix longwave (`load_ksi.F`, `lw_venus_ve.F`),
several shortwave variants (`sw_venus_rh/ve/cl/dc.F`), a Newtonian-cooling option
(`radlwsw_NewtonCool.F`) **and** a correlated-k path (`sw_venus_corrk.F90`,
`lw_venus_corrk.F90`). The Newtonian-cooling and correlated-k paths both matter
below (§4.1, §3.4).

Tracers: 53–59 in the chemistry configurations (`deftank/traceur-chemistry*.def`),
positional format, load-bearing ordering.

**Known condition of this code, from your own audit** (`VPCM_refactors/notes/`):
614 unprotected `SAVE` variables, 169 bare `stop`s, 18 routines without
`implicit none`, 10 severity-A defects in roughly half-coverage reading, OpenMP
incomplete, and **no unit or regression tests anywhere**. Live-path examples: solar
heating multiplied by undocumented hardcoded factors ×3.5 and ×1.5
(`sw_venus_rh.F:315,318`); aerosol sedimentation silently zeroed
(`physiq_mod.F:1083`); a k_B inconsistency biasing chemistry number densities by
0.047 %; a full array passed where `ROSAS` expects a scalar.

### 1.3 VULCAN-Venus — chemistry network + a code generator

Python 3, ~18,000 lines, GPLv3, Dai et al. (2024). **62 species, 838 reactions**,
57 vertical layers, 1-D column, photolysis with Venus-specific top-of-atmosphere
solar flux and UV-absorber treatment.

The genuinely valuable piece is `make_chem_funs.py` (813 lines): it reads the
plain-text network (`thermo/Networks/Nominal.txt`, 438 entries) and *generates*
`chem_funs.py` (10,998 lines) containing rate expressions, production/loss terms
and an **analytic Jacobian**, via SymPy. That is a retargetable code generator, and
retargeting it to emit Fortran is one of the few substantial work packages that can
start immediately, with no LFRic access and no dependency on any other decision
(see §4.2).

### 1.4 SOCRATES-Venus — the planetary branch, shortwave only

*Surveyed 2026-08-23 (session 2), at `lfric_core/SOCRATES/um13.0_planets` — 2.5 GB
unpacked plus a 2.4 GB tarball. See housekeeping note at the end of this section.*

This is the Met Office **planetary** branch of SOCRATES (`um13.0_planets`),
**BSD-3 Crown copyright** — the same licence as LFRic Core, so no friction on this
component at all. 208,529 lines of Fortran across 698 files, plus `examples/` for
`mars_dsa`, `titan`, `trappist1` and `venus`. The presence of that example set
strongly corroborates the planetary-LFRic precedent flagged in §1.1.

Venus is integrated into the **source**, not bolted onto the data. In
`src/modules_gen/input_head_pcf.f90`: a `VOL-VENUS` mixing-ratio unit, cis-OSSO /
trans-OSSO / OSO-S as first-class gas types (indices 53–55, i.e. added beyond
HITRAN), and a "75% Sulphuric acid Aerosol" type. `src/nlte/` also exists
(including `sw_nlte_heating_mod.f90`), which partially relieves §4.7.

**What exists — a mature shortwave capability.** `examples/venus/sp_sw_280_je_venus`
(Oct 2024): 280 bands, 13 gaseous absorbers (H2O, CO2, SO2, N2, CO, OCS, H2S, HDO,
HCl, HF, cis-OSSO, trans-OSSO, OSO-S), CO2–CO2 and H2O–H2O generalised continua,
5 aerosol types including sulphuric acid; up to 55 k-terms per band; the companion
`_k` file is 119 MB.

Behind it sits a substantial validation and sensitivity campaign, 2022–2024:
heating rates (`.hrts`) and up/down/net/direct fluxes for three reference
atmospheres — `LMD/` (i.e. VPCM's), `Frandsen/`, `Krasnopolsky/` — each run for
OSSO-only, OSSO+clouds and all-absorbers; plus `IPSL_clouds*/` sweeping cloud
modes 1–5 at 0.1×–10× scalings, per-gas attribution runs (co, co2, h2s, hcl, hdo,
hf, continuum, cosso), and FeCl3 as an alternative UV absorber. This is
UV-absorber and solar-heating research, and it is well advanced.

**What does not exist — the longwave.** I searched the whole tree: there is **no
Venus longwave spectral file**. For Venus that is not a detail; it is the
greenhouse, the deep-atmosphere thermal structure and the reason the surface is
735 K. The half that exists is the easier half. See §4.4.

**Band counts, for scale.** The Venus SW file is a reference/benchmark
configuration, not a GCM one:

| Configuration | SW bands | LW bands | max k-terms |
|---|---:|---:|---:|
| Earth operational (`data/spectra/ga9`) | 6 | 9 | 12 / 17 |
| Mars GCM (`data/spectra/mars`, `*_dsa_mars_*`) | 42 | 17 | — |
| **Venus (`examples/venus`)** | **280** | **absent** | **55** |

Roughly 45× Earth operational in band count, with up to 17,534 spectral sub-bands
within a single band. Not runnable in a GCM as it stands.

The Mars entry is the useful precedent: `sp_lw_17_dsa_mars_so2` +
`sp_sw_42_dsa_mars_sun_so2` is exactly the deliverable Venus needs — a
purpose-built planetary **GCM** spectral-file pair, reduced from reference data.
It has been done before, in this same tree, for another planet.

*Housekeeping:* the 2.5 GB tree and 2.4 GB tarball are currently **untracked inside
the `lfric_core` git clone** and show up in `git status` there. Worth moving out
to its own directory before an accidental `git add .` — the LFRic docs warn about
exactly that.

## 2. (a) Is it feasible?

**Yes — as an adaptation of LFRic-Atmosphere, conditional on three things:**

1. Access to `lfric_apps` and a working relationship with the Met Office LFRic team.
2. A licensing route that lets CeCILL (VPCM) and GPLv3 (VULCAN) derived work coexist
   with the Met Office stack — see §4.1, this is a real blocker, not paperwork.
3. Passing an early dynamical-core gate: Venus-parameter GungHo spinning up and
   sustaining superrotation with acceptable angular-momentum conservation.

**No, if the intent is literally to build on `lfric_core`.** Writing a dynamical
core and transport scheme on the LFRic Core substrate is a 5–10-year, multi-team
undertaking, and it is what the Met Office already did to produce GungHo.

There is a real scientific argument for the project beyond modernisation. LMDZ's
latitude–longitude dycore requires polar filtering, which is a long-standing
awkwardness for Venus superrotation and angular-momentum budgets. A cubed-sphere
FEM dycore removes the polar problem by construction, is designed for conservation
properties, and scales. That is a defensible motivation for a new Venus model
rather than continued incremental work on VPCM.

---

## 3. (b) How long?

Assumes a funded effort. FTE figures are working scientists/RSEs, not headcount.

| Phase | Content | Duration | FTE |
|---|---|---|---|
| **0. Gate** | `lfric_apps` access; build LFRic-Atmosphere; reproduce an Earth case; configure Venus parameters (Ω, a, g, R, surface pressure, 78–90 levels to ~100 km); run **dry dynamics with Newtonian cooling**; instrument an angular-momentum budget | **6–12 months** | 1 |
| **1. Radiation** | SOCRATES-Venus into the LFRic radiation interface; cost/accuracy tuning; boundary layer, turbulence, surface | 12–18 months | 1.5–2 |
| **2a. Clouds** | H2SO4 cloud + aerosol (adapt `cloudvenus`, or re-implement); aerosol optical properties feeding SOCRATES | 12–18 months | 1 |
| **2b. Chemistry** | 60-species photochemistry as LFRic column kernels; tracer transport at scale | 18–24 months (parallel with 2a) | 1–1.5 |
| **3. Validation** | Spin-up campaigns, VEx/Akatsuki/VIRTIS comparison, VPCM intercomparison, documentation, release | 12+ months | 1.5 |

**Headline numbers:**

- **Phase 0 demonstrator alone: 6–12 months at 1 FTE.** Cheap relative to the
  decision it informs, and publishable in its own right.
- **Scientifically usable LFRic-Venus (dynamics + radiation + clouds): 3–5 years
  at ~2–3 FTE.**
- **Chemistry-climate parity with VPCM, including the thermosphere: 5–7 years.**

At 1 FTE with no additional resource, the honest reach is Phase 0 and part of
Phase 1. That is worth saying explicitly when seeking funding: the project is not
viable as a solo effort, but Phase 0 *is*, and Phase 0 is exactly what converts
this assessment into a decision.

---

## 4. (c) Blockers and challenges

Ordered by "would kill or reshape the project" first.

### 4.1 Licence incompatibility between the science and the substrate — **do this first**

LFRic Core is BSD-3. VPCM is **CeCILL v2** (GPL-compatible copyleft). VULCAN-Venus
is **GPLv3**. Copying `phyvenus` routines or VULCAN-generated code into an
LFRic-derived model plausibly makes the result copyleft, which the Met Office stack
is unlikely to accept, and SOCRATES has its own licence terms again.

Routes: (i) re-implement physics from the published equations and papers rather
than copying source, using VPCM only as a reference implementation; (ii) negotiate
explicit relicensing with LMD and with Dai/Tsai; (iii) keep Venus physics in a
separately-licensed plug-in library behind a clean interface. Option (i) is
probably what happens anyway (§4.5), but the decision must be made **before** the
first line is copied, not after.

### 4.2 Variable heat capacity — a dycore-level problem, not a physics plug-in

Venus c_p varies by roughly a factor of two between the surface and 100 km. LMDZ.VENUS
carries `cpdet_mod` / `cpdet_phy_mod` precisely for this, and uses a *generalised*
potential temperature. GungHo's equation set is built on constant-c_p, constant-κ
Exner thermodynamics (θ, Π), and that assumption is baked into the semi-implicit
solver's linearisation and reference profile.

This is the most serious technical challenge in the dynamics. It is not solved by
writing a new kernel; it touches the core equation set. Options are to accept the
error and quantify it, to carry a temperature-dependent κ through the
thermodynamics, or to reformulate in terms of a generalised potential temperature
as LMD did. **Establish which of these is acceptable during Phase 0** — this is a
question for the LFRic dynamics team, and it should be asked in month one.

### 4.3 Angular momentum conservation and superrotation

Venus superrotation reaches ~60× solid-body at cloud top. Its maintenance is a
delicate balance that is easily destroyed by spurious numerical AM sources or
sinks. LFRic's AM conservation properties in a strongly superrotating,
slowly-rotating regime are, as far as I know, unestablished — the model was
designed and tested for Earth.

Mitigation: build the AM budget diagnostic into Phase 0 (you already have this
machinery on the analysis side in `venuslab/angular_momentum_budget.py`), and treat
"does GungHo sustain superrotation without spurious AM drift" as the explicit
pass/fail gate. Discovering an AM problem in year three would be fatal;
discovering it in month eight is a result.

### 4.4 The Venus longwave spectral file does not exist — now the single biggest work package

Revised after surveying SOCRATES (§1.4). This risk is now **split**: the shortwave
half is largely retired, the longwave half is confirmed and concentrated.

**Retired.** Shortwave has Venus species compiled into SOCRATES itself, a 280-band
spectral file with the right absorbers, continua and sulphuric-acid aerosol, and a
2022–2024 validation campaign against three reference atmospheres including LMD's.
The physics, the data and a heating-rate baseline all exist.

**Confirmed and quantified.** Two deliverables stand between that and a GCM:

1. **Build a Venus longwave spectral file from nothing.** Correlated-k for a 92-bar
   CO2 atmosphere: sub-Lorentzian far-wing line shapes, CO2–CO2 CIA, optical depths
   in the hundreds, H2SO4 cloud scattering, over a 735→180 K temperature range. This
   is specialist spectroscopy, not model coupling — realistically **12–18 months of
   a spectroscopist's time**, and probably needs the person who built the shortwave
   file. It is the critical path through Phase 1.
2. **Reduce the 280-band shortwave file to GCM cost.** Target the Mars precedent
   (42 SW / 17 LW bands). The existing `.hrts` campaign is the acceptance test: the
   reduced file must reproduce the reference heating-rate profiles. That framing
   makes this tractable and well-posed, but it is still months of work.

**Unchanged.** The spin-up problem compounds whatever cost results. The
near-surface radiative timescale is of order decades; superrotation spin-up needs
O(100–1000) Venus days; deep-atmosphere equilibration far longer. Any Venus GCM is
spin-up-dominated. Design in a cheap Newtonian-cooling spin-up path (VPCM's
`radlwsw_NewtonCool.F` is the template), reduced radiation call frequency, and
initialisation from a regridded VPCM state rather than from rest — the last needs
lat-lon → cubed-sphere state regridding, a work package in itself, though your
`venuslab` tooling (`oasis_convert.py`, `oasis_prep.py`) is relevant experience.

**Consequence for §3.** Phase 1 is not "couple SOCRATES-Venus to LFRic". It is
"build a Venus longwave spectral file, reduce the shortwave one, *then* couple" —
and the coupling is the small part, because SOCRATES is already wired into
LFRic-Atmosphere (`lfric_apps/rose-meta/socrates-radiation/`). The 12–18 month
Phase 1 estimate survives, but its content and its staffing change: it needs
spectroscopy expertise, not model-coupling expertise, and that expertise is the
scarce resource. Identify who builds the longwave file **before** committing to
the phase.

### 4.5 `phyvenus` is a reference implementation, not a portable one

Your own audit makes this unambiguous. 614 unprotected `SAVE` variables are exactly
the module-level mutable state that LFRic kernels forbid — PSyKAl kernels must be
side-effect-free and thread-safe. 169 bare `stop`s cannot survive in an MPI model
driven from a framework. 18 routines lack `implicit none`. The severity-A defects
(hardcoded ×3.5/×1.5 solar tuning, zeroed sedimentation, k_B inconsistency, the
`ROSAS` array/scalar mismatch) are live in the shipped configurations.

Plan for **re-implementation using `phyvenus` as the specification**, not
translation. Two consequences, one bad and one good:

- Effort estimates must use "rewrite" rates, not "port" rates. That is what §3 assumes.
- Your audit tickets 5–10 already constitute the defect list to fix during that
  rewrite. The audit work is not sunk cost — it is the specification. Combined with
  ticket 1's harness design, it is also the only description in existence of what
  the Venus physics is *supposed* to do.

### 4.6 Chemistry in 3-D on an unstructured mesh

Architecturally this fits LFRic well: a stiff column solve is a natural PSyKAl
column kernel. The problems are elsewhere.

- **Tracer count.** 60+ advected species through LFRic's transport scheme is a
  large memory and time cost, and the transport must be positive-definite and
  monotonic for chemistry. What limiters `lfric_apps` transport provides needs
  checking early.
- **Jacobian cost.** A 62-species implicit solve per column per timestep is the
  dominant physics cost after radiation.
- **The opportunity.** VULCAN's `make_chem_funs.py` already generates an analytic
  Jacobian from a text network. Writing a **Fortran backend for that generator**,
  emitting LFRic-conformant kernels (no saved state, explicit arguments), is a
  self-contained few-month work package that needs no LFRic access, no licence
  resolution for the *generator* itself, and pays off regardless of which model
  the chemistry ends up in — including VPCM. **This is the best thing to start
  now**, in parallel with chasing `lfric_apps` access.

### 4.7 Scope: exclude the thermosphere from v1

15,798 lines of NLTE, EUV heating, molecular diffusion and ion chemistry — and
your `chem_96x96x78` package exercises it (`callthermos=y`, `callnlte=y`,
`callnirco2=y`), so it is not dead code. But it is effectively a second model, it
was the worst category on every mechanical metric in your audit (261 unprotected
`SAVE`, 37 bare `stop`), and it was never read at depth. Whether GungHo is even
appropriate above ~120 km (non-LTE, molecular viscosity, non-hydrostatic) is an
open question.

Scope v1 to surface–~100 km and say so explicitly. Revisit in Phase 3 or later.

### 4.8 Validation has no ready-made ladder

VPCM has no tests, so there is no regression baseline to inherit. LFRic-Venus needs
its own validation ladder built from scratch: analytic/idealised cases (Held-Suarez
analogue, Newtonian-cooling superrotation), 1-D column comparison against VPCM's
`rcm1d` and against VULCAN-Venus for chemistry, then observations (VIRTIS — you have
`~/repos/VIRTIS_code` — VeRa, Akatsuki), with VPCM output as an intercomparison
target rather than as truth. Budget this as real work; it is folded into Phase 3
above but tends to be underestimated.

### 4.9 Team size and institutional dependency

This is the blocker most likely to decide the outcome. LFRic-Atmosphere's
adaptation to other planets was a multi-year funded collaboration, not a side
project. LFRic-Venus needs, at minimum: the Met Office LFRic/GungHo team (dycore
questions in §4.2, §4.3 are unanswerable without them), the Exeter planetary group
(who have already done a planetary port), LMD (physics provenance and validation),
and whoever owns SOCRATES-Venus. Securing those relationships is Phase 0 work with
the same priority as the code.

### 4.10 Ongoing merge cost — familiar, and manageable

`lfric_core` and `lfric_apps` release in lockstep on a regular cadence, and a Venus
fork carries the same recurring rebase cost you already manage against the monthly
LMD SVN port. Not a blocker; but the fork strategy (branch per concern, rebase after
each upstream release, keep diffs surgical) should be decided at the outset, and
the strategy you already documented for VPCM transfers directly.

---

## 5. Recommendation

Run **Phase 0 as a decision gate**, not as the first phase of a committed project.
Concretely, the four things that most reduce uncertainty per unit of effort:

1. **Establish `lfric_apps` access and the licensing route.** Nothing else matters
   until these are settled. Weeks of email, potentially fatal if refused.
2. **Ask the LFRic dynamics team the variable-c_p question (§4.2) directly.** Their
   answer determines whether this is an adaptation or a dycore project.
3. **Build the dry Venus demonstrator with an AM budget (§4.3).** 6–12 months,
   publishable, and decisive.
4. **Identify who will build the Venus longwave spectral file (§4.4).** This is now
   the critical path through Phase 1 and needs spectroscopy expertise, not modelling
   expertise. Establish the provenance of `sp_sw_280_je_venus` and whether its author
   is available — that conversation is worth more than any code written this year.

Deliberately *not* on this list, revised from the first draft: writing a Fortran
backend for VULCAN's chemistry generator. Chemistry is Phase 2b; its original
justification was that it needed no LFRic access, and that constraint disappeared
when `lfric_apps` was cloned. The cheap, non-invasive version — extracting VPCM's
hardcoded network (`indice` + `krates`, ~4,700 lines, no data file behind it) into
a machine-readable table and diffing it against VULCAN-Venus's 438-reaction
network — remains worth a few days whenever convenient, because it answers a real
science question and produces the network file any future generator would consume.
It is not urgent.

If Phase 0 passes, the project is a credible 3–5-year bid for a state-of-the-art
Venus model with a genuine scientific advantage over the lat-lon alternatives. If
it fails on angular momentum or on radiation cost, you will know within a year, at
a cost of one FTE-year, and the fallback — continuing the VPCM modernisation you
have already scoped in `VPCM_refactors` — remains fully available.
