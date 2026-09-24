"""Tests for variable_cp_diagnostics.py. Run with: python3 -m pytest venus/tools

The law's values are the same as in variable_cp_mod_test.pf, so the offline
diagnostics and the model agree.
"""
import numpy as np
from scipy.integrate import solve_ivp

from variable_cp_diagnostics import cp_law, static_stability, theta_l

LAW = (1000.0, 460.0, 0.35)
RD = 191.4
P_ZERO = 9.2e6


def test_cp_law_values():
    assert np.isclose(cp_law(230.0, *LAW), 784.5840978968, rtol=0, atol=1e-8)
    assert np.isclose(cp_law(735.0, *LAW), 1178.2442461288, rtol=0, atol=1e-8)


def test_cp_law_zero_exponent():
    assert cp_law(230.0, 1000.0, 460.0, 0.0) == 1000.0


def test_theta_l_at_p_zero():
    assert np.isclose(theta_l(230.0, P_ZERO, P_ZERO, RD, *LAW), 230.0)


def test_theta_l_value():
    # With R/cp for the namelist cp of 900 instead, this would be 637.77 K.
    assert np.isclose(theta_l(230.0, 1.0e5, P_ZERO, RD, *LAW),
                      584.5746538844, rtol=0, atol=1e-8)


def test_theta_l_zero_exponent():
    assert np.isclose(theta_l(230.0, 1.0e5, P_ZERO, RD, 1000.0, 460.0, 0.0),
                      546.5083806165, rtol=0, atol=1e-8)


def test_theta_l_along_adiabat():
    sol = solve_ivp(lambda lnp, t: RD * t / cp_law(t, *LAW),
                    [np.log(P_ZERO), np.log(1.0e5)], [735.0],
                    rtol=1e-12, atol=1e-10)
    t_end = sol.y[0, -1]
    assert np.isclose(theta_l(t_end, 1.0e5, P_ZERO, RD, *LAW), 735.0)


def test_static_stability_zero_on_true_adiabat():
    # A 60 km column on the true adiabat, dT/dz = -g/c_p(T), with constant
    # gravity. It cools from 735 K to about 205 K.
    gravity = 8.87
    z_full = np.linspace(0.0, 6.0e4, 41)
    z_half = 0.5 * (z_full[1:] + z_full[:-1])
    sol = solve_ivp(lambda z, t: -gravity / cp_law(t, *LAW),
                    [0.0, 6.0e4], [735.0], t_eval=z_half,
                    rtol=1e-12, atol=1e-10)
    temperature = sol.y[0][:, None]
    s = static_stability(temperature, z_half, z_full, gravity, 6.0518e6,
                         True, *LAW)
    assert np.isnan(s[0]).all() and np.isnan(s[-1]).all()
    # Second-order finite differences over 1.5 km layers.
    assert np.abs(s[1:-1]).max() < 1.0e-5
