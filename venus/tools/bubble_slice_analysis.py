#!/usr/bin/env python3
"""Time series for a warm-bubble vertical slice from LFRic lfric_diag.nc files.

For each output time it prints, per run:

  w_far      largest |w| (m/s) in the columns outside the bubble at the
             first output time; gravity waves from the bubble show up here
  w_max      largest |w| (m/s) anywhere
  dthl_max   largest excess of theta_cp_law over the reference run (K)
  z_cen      height of the bubble centroid (m), the mean height weighted by
             the excess where it is above a tenth of its starting maximum
  z_top      highest level where the excess is above that threshold (m)

theta_cp_law is the potential temperature a parcel conserves under c_p(T).
In an atmosphere neutral under c_p(T) a rising bubble keeps its excess, so
dthl_max stays near its starting value while z_cen and z_top climb. In a
stratified atmosphere the bubble overshoots and oscillates, and z_cen swings
at the buoyancy period.

The excess is taken point by point against a reference run of the same
background without the bubble, at the same output time. A background at rest
has no divergence, so the variable-c_p source term leaves it unchanged and one
reference serves runs with the switch on and off. Heights assume a uniform
extrusion. The formulas for theta_cp_law are those of
variable_cp_diagnostics.py.
"""
import argparse

import netCDF4 as nc
import numpy as np

from variable_cp_diagnostics import theta_cp_law


def on_half_levels(field, n_half):
    """Average a full-level field onto layer centres; pass half-level ones."""
    if field.shape[0] == n_half + 1:
        return 0.5 * (field[1:] + field[:-1])
    return field


class Run:
    """theta_cp_law and |w| at each output time of one lfric_diag.nc."""

    def __init__(self, path, args):
        self.path = path
        self.args = args
        self.src = nc.Dataset(path)
        try:
            self.theta = self.src.variables[args.theta_name]
            self.exner = self.src.variables[args.exner_name]
            self.w = self.src.variables[args.w_name]
        except KeyError as err:
            raise SystemExit(f"{path}: no variable {err}; variables are "
                             f"{sorted(self.src.variables)}")
        self.n_time = self.theta.shape[0]
        self.n_half = self.exner.shape[1]
        self.times = (self.src.variables["time"][:]
                      if "time" in self.src.variables else None)

    def thl(self, i):
        a = self.args
        law = (a.cp_law_ref, a.cp_law_t0, a.cp_law_exponent)
        theta = on_half_levels(np.asarray(self.theta[i], dtype=float),
                               self.n_half)
        exner = np.asarray(self.exner[i], dtype=float)
        temperature = theta * exner
        pressure = a.p_zero * exner ** (a.cp / a.rd)
        return theta_cp_law(temperature, pressure, a.p_zero, a.rd, *law)

    def abs_w(self, i):
        return np.abs(np.asarray(self.w[i], dtype=float))


def analyse(run, ref):
    if (run.n_time, run.n_half) != (ref.n_time, ref.n_half):
        raise SystemExit(f"{run.path} and {ref.path} differ in shape")
    z_half = (np.arange(run.n_half) + 0.5) * run.args.domain_height / run.n_half

    excess0 = run.thl(0) - ref.thl(0)
    start_max = excess0.max()
    if start_max <= 0.0:
        raise SystemExit(f"{run.path}: no bubble against {ref.path}")
    far = excess0.max(axis=0) < 0.01 * start_max
    threshold = 0.1 * start_max

    rows = []
    for i in range(run.n_time):
        w = run.abs_w(i)
        excess = run.thl(i) - ref.thl(i)
        inside = excess > threshold
        if inside.any():
            weight = np.where(inside, excess, 0.0)
            z_cen = (weight * z_half[:, None]).sum() / weight.sum()
            z_top = z_half[inside.any(axis=1)].max()
        else:
            z_cen = z_top = np.nan
        t = float(run.times[i]) if run.times is not None else float(i)
        rows.append((t, w[:, far].max(), w.max(), excess.max(), z_cen, z_top))
    return np.array(rows), far.sum(), far.size, start_max


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference",
                    help="lfric_diag.nc of the same background without the bubble")
    ap.add_argument("paths", nargs="+", help="lfric_diag.nc files, one per run")
    ap.add_argument("--every", type=int, default=2,
                    help="print every n-th output time (default: 2)")
    ap.add_argument("--theta-name", default="theta")
    ap.add_argument("--exner-name", default="exner")
    ap.add_argument("--w-name", default="w_in_wth")
    ap.add_argument("--domain-height", type=float, default=1.0e4,
                    help="model top height, m (default: 1e4)")
    ap.add_argument("--cp", type=float, default=900.0,
                    help="namelist cp, J/kg/K (default: 900)")
    ap.add_argument("--rd", type=float, default=191.4,
                    help="specific gas constant, J/kg/K (default: 191.4)")
    ap.add_argument("--p-zero", type=float, default=9.2e6,
                    help="reference pressure, Pa (default: 9.2e6)")
    ap.add_argument("--cp-law-ref", type=float, default=1000.0)
    ap.add_argument("--cp-law-t0", type=float, default=460.0)
    ap.add_argument("--cp-law-exponent", type=float, default=0.35)
    args = ap.parse_args()

    ref = Run(args.reference, args)
    for path in args.paths:
        rows, n_far, n_cols, start_max = analyse(Run(path, args), ref)
        print(f"== {path}")
        print(f"   {n_far} of {n_cols} columns outside the bubble at the first "
              f"output; largest excess {start_max:.3f} K")
        print(f"   {'t (s)':>8} {'w_far':>10} {'w_max':>10} {'dthl_max':>9} "
              f"{'z_cen':>8} {'z_top':>8}")
        for row in rows[::args.every]:
            print("   {:8.0f} {:10.3e} {:10.3e} {:9.4f} {:8.0f} {:8.0f}"
                  .format(*row))


if __name__ == "__main__":
    main()
