# LFRic-Venus

This directory holds the planning and design documents for LFRic-Venus: a Venus
climate model built on LFRic, developed in this fork of
[MetOffice/lfric_apps](https://github.com/MetOffice/lfric_apps).

## Documents

- [plan.md](plan.md) — the modular development plan: architecture, work packages
  WP0–WP6, gates G1/G2, milestones, risk register.
- [feasibility-assessment.md](feasibility-assessment.md) — the underlying resource
  survey (LFRic core/apps, VPCM, VULCAN-Venus, SOCRATES um13.0_planets) and full
  risk discussion.

## Fork conventions

- `main` is pristine: it tracks `upstream` (MetOffice/lfric_apps) and never
  receives Venus commits.
- `venus` is the integration branch: everything Venus lives here, rebased onto
  `main` after each upstream sync.
- Work-package branches (`venus/wp0-dynamics`, `venus/wp1-radiation`, ...) fork
  off `venus` and merge back.
- The Venus footprint is purely additive — new `applications/venus_model`,
  new `science/venus_physics`, this `venus/` directory — plus surgical edits to
  `interfaces/socrates_interface` from WP1c onward, to keep rebases cheap.
