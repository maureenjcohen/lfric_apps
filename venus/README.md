# LFRic-Venus

This directory holds the container recipe, offline analysis tools and fork conventions for
LFRic-Venus: a Venus climate model built on LFRic, developed in this fork of
[MetOffice/lfric_apps](https://github.com/MetOffice/lfric_apps).

- `container/` — the `lfric_dev` image recipe.
- `tools/variable_cp_diagnostics.py` — computes temperature, c_p(T), the variable-c_p
  potential temperature θ_L and the static stability from an `lfric_diag.nc` that writes θ
  on full levels. Run it with `--help` for options. Its tests are the `test_*` functions in
  `tools/test_variable_cp_diagnostics.py`, runnable with pytest.
- `tools/neutral_profile.py` — writes the θ table, as a Rose `[namelist:initial_temperature]`
  fragment, for an atmosphere neutral under c_p(T): constant θ_L, built from a surface
  temperature and pressure. At most 100 points, the size of the model's table arrays.
- `tools/bubble_slice_analysis.py` — time series for a warm-bubble slice: background vertical
  wind, the bubble's θ_L excess, and its centroid and top heights, each measured against a
  run of the same background without the bubble.

## Fork conventions

- `main` is pristine: it tracks `upstream` (MetOffice/lfric_apps) and never
  receives Venus commits.
- `venus` is the integration branch: everything Venus lives here, rebased onto
  `main` after each upstream sync.
- Work-package branches (`venus-wp1-variable-cp`, ...) fork off `venus` and merge back.
  A `venus/…` name is not possible while a branch called `venus` exists.
- The Venus footprint is mostly additive: new kernels under
  `science/gungho/source/kernel/external_forcing/`, the variable-c_p module and source-term
  kernel under `science/gungho/source/kernel/core_dynamics/`, the bubble and standing-wave
  perturbation kernels under `science/gungho/source/kernel/initialisation/`, the variable-c_p
  solver operator kernel under `science/gungho/source/kernel/solver/`, rose-stem optional configs in
  `rose-stem/app/gungho_model/opt/`, and this `venus/` directory. It is not entirely
  additive, and cannot be. Registering a new `theta_forcing` value needs the
  `external_forcing=theta_forcing` enum in
  `science/gungho/rose-meta/lfric-gungho/HEAD/rose-meta.conf`, a `case` branch in
  `external_forcing_alg_mod.X90`, and entries in the rose-stem task and group lists.
  Keep such edits small so the rebase surface stays known.
- `lfric_core` is consumed unmodified. If something appears to require a change there,
  that is a design problem to raise, not a patch to write.
