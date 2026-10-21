!-----------------------------------------------------------------------------
! (c) Crown copyright 2026 Met Office. All rights reserved.
! The file LICENCE, distributed with this code, contains details of the terms
! under which the code may be used.
!-----------------------------------------------------------------------------
!> @brief Contains forcing terms for the Lee et al. (2007) idealised Venus
!>        temperature forcing.
!>
!> @details Lee, C., Lewis, S. R. and Read, P. L. (2007), Superrotation in a
!!          Venus general circulation model, J. Geophys. Res., 112, E04S11,
!!          doi:10.1029/2006JE002874.
!!
!!          Temperature is relaxed on a fixed 25 Earth day timescale at all
!!          levels towards (Lee eq. 5)
!!            T_eq(eta, lat) = T_Z(eta) + T_H(eta) * cos(lat),
!!          where eta = p/p_surf. T_Z is a fifth-order polynomial in
!!          log10(eta), fitted by Lee to Pioneer Venus and VIRA data. T_H is
!!          tabulated on Lee's 31 levels (Table 1) and interpolated linearly
!!          in log10(eta).
!!
!!          The coefficient signs of T_Z are not legible in the published
!!          text. Those here reproduce the 31-level T_Z table of the LMD Venus
!!          PCM to within 1E-3 K.
!!
!!          The equation is used as printed, with cos(lat) rather than
!!          cos(lat) - pi/4, so the global mean of T_eq is T_Z + (pi/4) T_H.
!!          This form is convectively stable at all latitudes, as Lee states
!!          the relaxation field is; the form with the zero-mean residual is
!!          not, at the pole near 36 km.
!!
!!          Above the top of Table 1, T_Z and T_H are held at their values
!!          there. There is no diurnal cycle and no longitudinal structure.
!>
module venus_lee2007_forcings_mod

  use constants_mod, only: i_def, r_def

  implicit none

  private

  public :: venus_lee2007_equilibrium_temperature

  !> Relaxation rate at all levels (s-1): one per 25 Earth days.
  real(kind=r_def), parameter, public :: venus_lee2007_newton_frequency = &
                                         1.0_r_def / (25.0_r_def * 86400.0_r_def)

  !> Number of levels in Lee's Table 1.
  integer(kind=i_def), parameter :: nlev = 31

  !> Coefficients of T_Z (K) in powers of log10(eta), lowest power first.
  real(kind=r_def), parameter :: t_z_coeffs(0:5) = (/ &
       733.4861_r_def, 301.2670_r_def,  47.2002_r_def, &
        -5.0230_r_def,  -2.3257_r_def,  -0.1896_r_def /)

  !> eta at the levels of Lee's Table 1, from the surface upwards.
  real(kind=r_def), parameter :: eta_tab(nlev) = (/ &
       9.602E-1_r_def, 8.679E-1_r_def, 7.577E-1_r_def, 6.420E-1_r_def, &
       5.299E-1_r_def, 4.273E-1_r_def, 3.373E-1_r_def, 2.610E-1_r_def, &
       1.979E-1_r_def, 1.472E-1_r_def, 1.074E-1_r_def, 7.672E-2_r_def, &
       5.361E-2_r_def, 3.657E-2_r_def, 2.430E-2_r_def, 1.569E-2_r_def, &
       9.814E-3_r_def, 5.929E-3_r_def, 3.454E-3_r_def, 1.934E-3_r_def, &
       1.043E-3_r_def, 5.400E-4_r_def, 2.710E-4_r_def, 1.324E-4_r_def, &
       6.355E-5_r_def, 3.070E-5_r_def, 1.525E-5_r_def, 7.950E-6_r_def, &
       4.500E-6_r_def, 2.925E-6_r_def, 2.265E-6_r_def /)

  !> Amplitude of the cos(lat) term (K) at the levels of eta_tab.
  real(kind=r_def), parameter :: t_h_tab(nlev) = (/ &
        6.101_r_def,  6.136_r_def,  6.176_r_def,  6.410_r_def,  6.634_r_def, &
        6.678_r_def,  6.719_r_def,  6.762_r_def,  7.167_r_def,  7.524_r_def, &
        9.840_r_def, 14.948_r_def, 21.370_r_def, 28.746_r_def, 36.373_r_def, &
       43.315_r_def, 48.534_r_def, 51.175_r_def, 50.757_r_def, 47.342_r_def, &
       41.536_r_def, 34.295_r_def, 26.758_r_def, 19.807_r_def, 14.001_r_def, &
        9.599_r_def,  6.504_r_def,  4.439_r_def,  3.126_r_def,  2.370_r_def, &
        2.000_r_def /)

contains

!> @brief Equilibrium temperature of the Lee et al. (2007) forcing.
!> @param[in] eta    Pressure divided by surface pressure
!> @param[in] lat    Latitude (radians)
!> @return    t_eq   Equilibrium temperature (K)
function venus_lee2007_equilibrium_temperature(eta, lat) result(t_eq)

  implicit none

  ! Arguments
  real(kind=r_def), intent(in) :: eta, lat

  ! Local variables
  integer(kind=i_def) :: i, k
  real(kind=r_def)    :: x, t_z, t_h, w, t_eq

  x = log10(max(eta, eta_tab(nlev)))

  t_z = 0.0_r_def
  do i = 5, 0, -1
    t_z = t_z*x + t_z_coeffs(i)
  end do

  ! Table is small and ordered by decreasing eta, so a linear scan is
  ! adequate here.
  if (eta >= eta_tab(1)) then
    t_h = t_h_tab(1)
  else if (eta <= eta_tab(nlev)) then
    t_h = t_h_tab(nlev)
  else
    k = 1_i_def
    do while (eta < eta_tab(k+1))
      k = k + 1_i_def
    end do
    w = (x - log10(eta_tab(k))) / (log10(eta_tab(k+1)) - log10(eta_tab(k)))
    t_h = t_h_tab(k) + w*(t_h_tab(k+1) - t_h_tab(k))
  end if

  t_eq = t_z + t_h*cos(lat)

end function venus_lee2007_equilibrium_temperature

end module venus_lee2007_forcings_mod
