# LFRic-Venus

This directory holds the container recipe and fork conventions for LFRic-Venus: a Venus
climate model built on LFRic, developed in this fork of
[MetOffice/lfric_apps](https://github.com/MetOffice/lfric_apps).

## Fork conventions

- `main` is pristine: it tracks `upstream` (MetOffice/lfric_apps) and never
  receives Venus commits.
- `venus` is the integration branch: everything Venus lives here, rebased onto
  `main` after each upstream sync.
- Work-package branches (`venus-wp1-variable-cp`, ...) fork off `venus` and merge back.
  A `venus/…` name is not possible while a branch called `venus` exists.
- The Venus footprint is mostly additive: new kernels under
  `science/gungho/source/kernel/external_forcing/`, a rose-stem optional config in
  `rose-stem/app/gungho_model/opt/`, and this `venus/` directory. It is not entirely
  additive, and cannot be. Registering a new `theta_forcing` value needs the
  `external_forcing=theta_forcing` enum in
  `science/gungho/rose-meta/lfric-gungho/HEAD/rose-meta.conf`, a `case` branch in
  `external_forcing_alg_mod.X90`, and entries in the rose-stem task and group lists.
  Keep such edits small so the rebase surface stays known.
- `lfric_core` is consumed unmodified. If something appears to require a change there,
  that is a design problem to raise, not a patch to write.
