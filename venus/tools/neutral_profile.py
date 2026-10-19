#!/usr/bin/env python3
"""Potential temperature table for an atmosphere neutral under c_p(T).

The atmosphere follows a true dry adiabat under the heat capacity law, so its
theta_cp_law is the same at every height. Along it

  T(p)^nu = theta_cp_law^nu - nu T0^nu (R/cp_law_ref) ln(p0/p)

and hydrostatic balance, dp/dz = -g p / (R T), gives p(z) and so T(z). The
table holds the model's theta = T (p0/p)^(R/cp), built on the namelist cp,
which rises with height wherever c_p(T) differs from cp.

Gravity is constant, as in planar geometry. The output is a Rose
[namelist:initial_temperature] fragment of profile_data, profile_heights and
profile_size, in the layout of rose-app-venus.conf.
"""
import argparse
import sys

import numpy as np
from scipy.integrate import solve_ivp

from variable_cp_diagnostics import cp_law, theta_cp_law


def adiabat_temperature(pressure, theta_l, p_zero, rd, cp_law_ref, cp_law_t0,
                        cp_law_exponent):
    """Temperature (K) at pressure (Pa) on the adiabat of constant theta_l."""
    kappa_ref = rd / cp_law_ref
    if cp_law_exponent == 0.0:
        return theta_l * (pressure / p_zero) ** kappa_ref
    return (theta_l ** cp_law_exponent
            - cp_law_exponent * cp_law_t0 ** cp_law_exponent
            * kappa_ref * np.log(p_zero / pressure)) ** (1.0 / cp_law_exponent)


def neutral_profile(heights, t_surf, p_surf, gravity, rd, p_zero, cp_law_ref,
                    cp_law_t0, cp_law_exponent):
    """Temperature (K) and pressure (Pa) at heights (m) on the neutral adiabat."""
    law = (cp_law_ref, cp_law_t0, cp_law_exponent)
    theta_l = theta_cp_law(t_surf, p_surf, p_zero, rd, *law)

    def dlnp_dz(z, lnp):
        t = adiabat_temperature(np.exp(lnp), theta_l, p_zero, rd, *law)
        return -gravity / (rd * t)

    sol = solve_ivp(dlnp_dz, (heights[0], heights[-1]), [np.log(p_surf)],
                    t_eval=heights, rtol=1e-12, atol=1e-12)
    pressure = np.exp(sol.y[0])
    temperature = adiabat_temperature(pressure, theta_l, p_zero, rd, *law)
    return temperature, pressure


def rose_list(name, values, per_line=6):
    """A Rose list setting, with '=' continuation lines."""
    items = [f"{v:.6E}" for v in values]
    lines = [",".join(items[i:i + per_line])
             for i in range(0, len(items), per_line)]
    pad = " " * len(name)
    out = [f"{name}={lines[0]}"]
    out += [f"{pad}={line}" for line in lines[1:]]
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--t-surf", type=float, default=735.0,
                    help="surface temperature, K (default: 735)")
    ap.add_argument("--p-surf", type=float, default=9.2e6,
                    help="surface pressure, Pa (default: 9.2e6)")
    ap.add_argument("--depth", type=float, default=1.0e4,
                    help="height of the top of the table, m (default: 1e4)")
    ap.add_argument("--points", type=int, default=100,
                    help="number of points in the table, at most 100 "
                         "(default: 100)")
    ap.add_argument("--gravity", type=float, default=8.87,
                    help="gravitational acceleration, m/s^2 (default: 8.87)")
    ap.add_argument("--rd", type=float, default=191.4,
                    help="specific gas constant, J/kg/K (default: 191.4)")
    ap.add_argument("--cp", type=float, default=900.0,
                    help="namelist cp on which theta is built, J/kg/K "
                         "(default: 900)")
    ap.add_argument("--p-zero", type=float, default=9.2e6,
                    help="reference pressure, Pa (default: 9.2e6)")
    ap.add_argument("--cp-law-ref", type=float, default=1000.0,
                    help="heat capacity at the law's reference temperature, "
                         "J/kg/K (default: 1000)")
    ap.add_argument("--cp-law-t0", type=float, default=460.0,
                    help="reference temperature of the law, K (default: 460)")
    ap.add_argument("--cp-law-exponent", type=float, default=0.35,
                    help="exponent of the law (default: 0.35)")
    args = ap.parse_args()

    # profile_interp_kernel_mod holds the table in arrays of 100 elements and
    # does not check profile_size, so a longer table overruns them.
    n = args.points
    if not 2 <= n <= 100:
        sys.exit(f"{n} points; the table must have 2 to 100 points")
    heights = np.linspace(0.0, args.depth, n)
    law = (args.cp_law_ref, args.cp_law_t0, args.cp_law_exponent)

    temperature, pressure = neutral_profile(
        heights, args.t_surf, args.p_surf, args.gravity, args.rd, args.p_zero,
        *law)
    theta = temperature * (args.p_zero / pressure) ** (args.rd / args.cp)

    cp = cp_law(temperature, *law)
    print(f"T {temperature[0]:.2f} -> {temperature[-1]:.2f} K, "
          f"p {pressure[0]:.4E} -> {pressure[-1]:.4E} Pa, "
          f"c_p {cp[0]:.1f} -> {cp[-1]:.1f} J/kg/K, "
          f"theta {theta[0]:.2f} -> {theta[-1]:.2f} K",
          file=sys.stderr)

    print("[namelist:initial_temperature]")
    print(rose_list("profile_data", theta))
    print(rose_list("profile_heights", heights))
    print(f"profile_size={n}")


if __name__ == "__main__":
    main()
