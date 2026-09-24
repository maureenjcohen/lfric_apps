#!/usr/bin/env python3
"""Variable-c_p diagnostics from an LFRic lfric_diag.nc.

Computes, from the model's theta and exner:

  temperature       T = theta * exner                        layer centres
  cp                c_p(T) = cp_law_ref (T / cp_law_t0)^nu   layer centres
  theta_l           potential temperature conserved along a  layer centres
                    true adiabat under c_p(T)
  static_stability  dT/dz + g / c_p(T)                       interior theta levels

theta_l obeys theta_l^nu = T^nu + nu T0^nu ln[(p0/p)^(R/cp_law_ref)]. Its
exponent uses the law's reference heat capacity, not the model's kappa, which
is built on the namelist cp. The model's theta is a coordinate built on the
namelist cp and is not the potential temperature observers use.

The model writes theta on theta levels (full_levels) and exner on layer
centres (half_levels). theta is averaged onto layer centres, as lowest-order
LFRic does when it maps theta to W3. Static stability is a finite difference
between adjacent layer centres, so it sits on the theta levels between them;
the bottom and top theta levels are NaN.

Heights assume a uniform extrusion. Gravity varies as g (a / (a + z))^2 in a
deep atmosphere, matching the geopotential GungHo uses when shallow=.false.

The file is processed one time record at a time, so multi-GB files are safe.
The formulas mirror science/gungho/source/kernel/core_dynamics/variable_cp_mod.F90.
"""
import argparse

import netCDF4 as nc
import numpy as np


def cp_law(temperature, cp_law_ref, cp_law_t0, cp_law_exponent):
    """Heat capacity at constant pressure (J/kg/K) at temperature (K)."""
    return cp_law_ref * (temperature / cp_law_t0) ** cp_law_exponent


def theta_l(temperature, pressure, p_zero, rd, cp_law_ref, cp_law_t0,
            cp_law_exponent):
    """Potential temperature (K) conserved along a true adiabat under the law."""
    kappa_ref = rd / cp_law_ref
    if cp_law_exponent == 0.0:
        return temperature * (p_zero / pressure) ** kappa_ref
    return (temperature ** cp_law_exponent
            + cp_law_exponent * cp_law_t0 ** cp_law_exponent
            * kappa_ref * np.log(p_zero / pressure)) ** (1.0 / cp_law_exponent)


def gravity_at(z, gravity, planet_radius, shallow):
    """Gravitational acceleration (m/s^2) at height z (m)."""
    if shallow:
        return np.full_like(z, gravity, dtype=float)
    return gravity * (planet_radius / (planet_radius + z)) ** 2


def static_stability(temperature, z_half, z_full, gravity, planet_radius,
                     shallow, cp_law_ref, cp_law_t0, cp_law_exponent):
    """dT/dz + g/c_p(T) (K/m) on the theta levels.

    temperature has shape (layers, ...) on layer centres z_half. The result
    has shape (layers + 1, ...) on z_full; the bottom and top levels are NaN.
    """
    dtdz = np.diff(temperature, axis=0) / np.diff(z_half).reshape(
        (-1,) + (1,) * (temperature.ndim - 1))
    t_interface = 0.5 * (temperature[1:] + temperature[:-1])
    g = gravity_at(z_full[1:-1], gravity, planet_radius, shallow).reshape(
        (-1,) + (1,) * (temperature.ndim - 1))
    interior = dtdz + g / cp_law(t_interface, cp_law_ref, cp_law_t0,
                                 cp_law_exponent)
    edge = np.full((1,) + temperature.shape[1:], np.nan)
    return np.concatenate([edge, interior, edge], axis=0)


def copy_variable(src, dst, name):
    var = src.variables[name]
    fill = getattr(var, "_FillValue", None)
    out = dst.createVariable(name, var.dtype, var.dimensions, fill_value=fill)
    out.setncatts({k: var.getncattr(k) for k in var.ncattrs()
                   if k != "_FillValue"})
    out[...] = var[...]


def new_field(dst, name, dims, long_name, units, mesh_attrs):
    var = dst.createVariable(name, "f8", dims, fill_value=np.nan)
    var.long_name = long_name
    var.units = units
    var.setncatts(mesh_attrs)
    return var


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", help="input lfric_diag.nc")
    ap.add_argument("output", help="output NetCDF file")
    ap.add_argument("--theta-name", default="theta",
                    help="theta variable in the input (default: theta)")
    ap.add_argument("--exner-name", default="exner",
                    help="exner variable in the input (default: exner)")
    ap.add_argument("--domain-height", type=float, default=9.0e4,
                    help="model top height, m (default: 9.0E4)")
    ap.add_argument("--cp", type=float, default=900.0,
                    help="namelist cp, the constant defining theta and exner "
                         "(default: 900)")
    ap.add_argument("--rd", type=float, default=191.4,
                    help="specific gas constant, J/kg/K (default: 191.4)")
    ap.add_argument("--p-zero", type=float, default=9.2e6,
                    help="reference pressure, Pa (default: 9.2E6)")
    ap.add_argument("--gravity", type=float, default=8.87,
                    help="surface gravity, m/s^2 (default: 8.87)")
    ap.add_argument("--planet-radius", type=float, default=6.0518e6,
                    help="planet radius, m (default: 6.0518E6)")
    ap.add_argument("--shallow", action="store_true",
                    help="constant gravity with height, as for shallow=.true.")
    ap.add_argument("--cp-law-ref", type=float, default=1000.0,
                    help="heat capacity at cp_law_t0, J/kg/K (default: 1000)")
    ap.add_argument("--cp-law-t0", type=float, default=460.0,
                    help="reference temperature of the law, K (default: 460)")
    ap.add_argument("--cp-law-exponent", type=float, default=0.35,
                    help="exponent of the law (default: 0.35)")
    args = ap.parse_args()

    law = (args.cp_law_ref, args.cp_law_t0, args.cp_law_exponent)
    kappa = args.rd / args.cp

    src = nc.Dataset(args.path)
    theta_var = src.variables[args.theta_name]
    exner_var = src.variables[args.exner_name]
    time_dim, full_dim, face_dim = theta_var.dimensions
    half_dim = exner_var.dimensions[1]
    layers = len(src.dimensions[half_dim])

    dz = args.domain_height / layers
    z_full = np.arange(layers + 1) * dz
    z_half = (np.arange(layers) + 0.5) * dz

    dst = nc.Dataset(args.output, "w")
    for name, dim in src.dimensions.items():
        dst.createDimension(name, None if dim.isunlimited() else len(dim))

    # Mesh topology, coordinates and time, so the output reads like LFRic
    # output.
    for name, var in src.variables.items():
        if var.dimensions and var.dimensions[0] == time_dim and name not in (
                "time", "time_bounds"):
            continue
        copy_variable(src, dst, name)

    mesh_attrs = {k: theta_var.getncattr(k) for k in ("mesh", "location")
                  if k in theta_var.ncattrs()}
    half = (time_dim, half_dim, face_dim)
    full = (time_dim, full_dim, face_dim)
    out_t = new_field(dst, "temperature", half, "temperature", "K", mesh_attrs)
    out_cp = new_field(dst, "cp", half,
                       "heat capacity at constant pressure, c_p(T)",
                       "J kg-1 K-1", mesh_attrs)
    out_thl = new_field(dst, "theta_l", half,
                        "potential temperature conserved under c_p(T)", "K",
                        mesh_attrs)
    out_s = new_field(dst, "static_stability", full,
                      "static stability dT/dz + g/c_p(T)", "K m-1",
                      mesh_attrs)
    dst.setncatts({
        "source": args.path,
        "cp": args.cp, "rd": args.rd, "p_zero": args.p_zero,
        "gravity": args.gravity, "planet_radius": args.planet_radius,
        "shallow": int(args.shallow), "domain_height": args.domain_height,
        "cp_law_ref": args.cp_law_ref, "cp_law_t0": args.cp_law_t0,
        "cp_law_exponent": args.cp_law_exponent,
    })

    for i in range(len(src.dimensions[time_dim])):
        theta = np.asarray(theta_var[i], dtype=float)
        exner = np.asarray(exner_var[i], dtype=float)
        theta_half = 0.5 * (theta[1:] + theta[:-1])
        temperature = theta_half * exner
        pressure = args.p_zero * exner ** (1.0 / kappa)

        out_t[i] = temperature
        out_cp[i] = cp_law(temperature, *law)
        out_thl[i] = theta_l(temperature, pressure, args.p_zero, args.rd, *law)
        out_s[i] = static_stability(temperature, z_half, z_full, args.gravity,
                                    args.planet_radius, args.shallow, *law)

    dst.close()
    src.close()


if __name__ == "__main__":
    main()
