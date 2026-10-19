!-----------------------------------------------------------------------------
! (C) Crown copyright 2026 Met Office. All rights reserved.
! The file LICENCE, distributed with this code, contains details of the terms
! under which the code may be used.
!-----------------------------------------------------------------------------

!> @brief Computes a warm bubble perturbation to the potential temperature
!> @details The bubble has the shape of the Bryan and Fritsch (2002) test,
!!          with its size and position set by arguments rather than fixed,
!!          so it can be placed on any background profile. The increment is
!!          \f[
!!          \Delta\theta = A \cos^2\left(\frac{\pi L}{2}\right), \quad
!!          L = \frac{\sqrt{x^2 + (z - z_c)^2}}{r}
!!          \f]
!!          for L <= 1 and zero outside. The bubble is centred at x = 0 and
!!          is uniform in y. It is only meaningful for planar geometry, where
!!          z is the height above the surface.
module theta_bubble_perturb_kernel_mod

  use argument_mod,              only: arg_type, func_type,       &
                                       GH_FIELD, GH_REAL,         &
                                       GH_SCALAR, GH_READ,        &
                                       GH_WRITE,                  &
                                       ANY_SPACE_9, GH_BASIS,     &
                                       ANY_DISCONTINUOUS_SPACE_3, &
                                       CELL_COLUMN, GH_EVALUATOR
  use constants_mod,             only: r_def, i_def, pi
  use fs_continuity_mod,         only: Wtheta
  use kernel_mod,                only: kernel_type

  ! Configuration modules
  use base_mesh_config_mod,      only: geometry, topology
  use finite_element_config_mod, only: coord_system
  use planet_config_mod,         only: scaled_radius

  implicit none

  private

  !---------------------------------------------------------------------------
  ! Public types
  !---------------------------------------------------------------------------
  !> The type declaration for the kernel. Contains the metadata needed by the
  !> Psy layer.
  type, public, extends(kernel_type) :: theta_bubble_perturb_kernel_type
    private
    type(arg_type) :: meta_args(6) = (/                                       &
         arg_type(GH_FIELD,   GH_REAL, GH_WRITE,     Wtheta),                 &
         arg_type(GH_FIELD*3, GH_REAL, GH_READ,      ANY_SPACE_9),            &
         arg_type(GH_FIELD,   GH_REAL, GH_READ,      ANY_DISCONTINUOUS_SPACE_3), &
         arg_type(GH_SCALAR,  GH_REAL, GH_READ),                              &
         arg_type(GH_SCALAR,  GH_REAL, GH_READ),                              &
         arg_type(GH_SCALAR,  GH_REAL, GH_READ)                               &
         /)
    type(func_type) :: meta_funcs(1) = (/                                     &
         func_type(ANY_SPACE_9, GH_BASIS)                                     &
         /)
    integer :: operates_on = CELL_COLUMN
    integer :: gh_shape = GH_EVALUATOR
  contains
    procedure, nopass :: theta_bubble_perturb_code
  end type

  !---------------------------------------------------------------------------
  ! Contained functions/subroutines
  !---------------------------------------------------------------------------
  public :: theta_bubble_perturb_code
  public :: bubble_increment

contains

!> @brief Computes a warm bubble perturbation to the potential temperature
!! @param[in] nlayers Number of layers
!! @param[in,out] theta_pert Potential temperature perturbation
!! @param[in] chi_1 First component of the chi coordinate field
!! @param[in] chi_2 Second component of the chi coordinate field
!! @param[in] chi_3 Third component of the chi coordinate field
!! @param[in] panel_id A field giving the ID for mesh panels
!! @param[in] amplitude Potential temperature increment at the centre (K)
!! @param[in] z_centre Height of the bubble centre (m)
!! @param[in] radius Radius of the bubble (m)
!! @param[in] ndf_wtheta Number of degrees of freedom per cell for wtheta
!! @param[in] undf_wtheta Number of total degrees of freedom for wtheta
!! @param[in] map_wtheta Dofmap for the cell at the base of the column
!! @param[in] ndf_chi Number of degrees of freedom per cell for chi
!! @param[in] undf_chi Number of total degrees of freedom for chi
!! @param[in] map_chi Dofmap for the cell at the base of the column
!! @param[in] chi_basis Basis functions evaluated at Wtheta points
!! @param[in] ndf_pid  Number of degrees of freedom per cell for panel_id
!! @param[in] undf_pid Number of unique degrees of freedom for panel_id
!! @param[in] map_pid  Dofmap for the cell at the base of the column for panel_id
subroutine theta_bubble_perturb_code(nlayers,                               &
                                     theta_pert,                            &
                                     chi_1, chi_2, chi_3,                   &
                                     panel_id,                              &
                                     amplitude, z_centre, radius,           &
                                     ndf_wtheta, undf_wtheta, map_wtheta,   &
                                     ndf_chi, undf_chi, map_chi, chi_basis, &
                                     ndf_pid, undf_pid, map_pid             )

  use sci_chi_transform_mod, only : chi2xyz

  implicit none

  ! Arguments
  integer(kind=i_def), intent(in) :: nlayers, ndf_wtheta, ndf_chi, ndf_pid
  integer(kind=i_def), intent(in) :: undf_wtheta, undf_chi, undf_pid

  integer(kind=i_def), dimension(ndf_wtheta), intent(in) :: map_wtheta
  integer(kind=i_def), dimension(ndf_chi),    intent(in) :: map_chi
  integer(kind=i_def), dimension(ndf_pid),    intent(in) :: map_pid

  real(kind=r_def),    dimension(undf_wtheta),           intent(inout) :: theta_pert
  real(kind=r_def),    dimension(undf_chi),              intent(in)    :: chi_1, chi_2, chi_3
  real(kind=r_def),    dimension(undf_pid),              intent(in)    :: panel_id
  real(kind=r_def),    dimension(1,ndf_chi,ndf_wtheta),  intent(in)    :: chi_basis
  real(kind=r_def),                                      intent(in)    :: amplitude
  real(kind=r_def),                                      intent(in)    :: z_centre
  real(kind=r_def),                                      intent(in)    :: radius

  ! Internal variables
  real(kind=r_def),   dimension(ndf_chi) :: chi_1_e, chi_2_e, chi_3_e
  real(kind=r_def)                       :: coords(3), xyz(3)
  integer(kind=i_def)                    :: df, dfc, k, ipanel

  ipanel = int(panel_id(map_pid(1)), i_def)

  do k = 0, nlayers-1
    do dfc = 1, ndf_chi
      chi_1_e(dfc) = chi_1( map_chi(dfc) + k)
      chi_2_e(dfc) = chi_2( map_chi(dfc) + k)
      chi_3_e(dfc) = chi_3( map_chi(dfc) + k)
    end do

    do df = 1, ndf_wtheta
      coords(:) = 0.0_r_def
      do dfc = 1, ndf_chi
        coords(1) = coords(1) + chi_1_e(dfc)*chi_basis(1,dfc,df)
        coords(2) = coords(2) + chi_2_e(dfc)*chi_basis(1,dfc,df)
        coords(3) = coords(3) + chi_3_e(dfc)*chi_basis(1,dfc,df)
      end do

      call chi2xyz( coords(1), coords(2), coords(3), &
                    ipanel, geometry, topology,      &
                    coord_system, scaled_radius,     &
                    xyz(1), xyz(2), xyz(3) )

      theta_pert(map_wtheta(df) + k) = bubble_increment( xyz(1), xyz(3), &
                                                         amplitude,      &
                                                         z_centre, radius )
    end do
  end do

end subroutine theta_bubble_perturb_code

!> @brief Potential temperature increment of the bubble at one point
!! @param[in] x Horizontal position, measured from the bubble centre (m)
!! @param[in] z Height above the surface (m)
!! @param[in] amplitude Increment at the centre (K)
!! @param[in] z_centre Height of the bubble centre (m)
!! @param[in] radius Radius of the bubble (m)
!! @return The increment (K)
pure function bubble_increment(x, z, amplitude, z_centre, radius) &
                               result(increment)

  implicit none

  real(kind=r_def), intent(in) :: x, z, amplitude, z_centre, radius
  real(kind=r_def)             :: increment

  real(kind=r_def) :: l

  l = sqrt( x**2 + (z - z_centre)**2 ) / radius
  if ( l <= 1.0_r_def ) then
    increment = amplitude * cos( 0.5_r_def * pi * l )**2
  else
    increment = 0.0_r_def
  end if

end function bubble_increment

end module theta_bubble_perturb_kernel_mod
