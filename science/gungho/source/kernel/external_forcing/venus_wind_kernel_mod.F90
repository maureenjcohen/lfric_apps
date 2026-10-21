!-----------------------------------------------------------------------------
! (c) Crown copyright 2026 Met Office. All rights reserved.
! The file LICENCE, distributed with this code, contains details of the terms
! under which the code may be used.
!-----------------------------------------------------------------------------
!> @brief Adds idealised Venus surface friction using the finite difference
!>        representation of the fields.
!>
!> @details This kernel is only intended for use with lowest order elements.
!>
!>          Rayleigh drag, du/dt = -k*u, is applied to the horizontal wind in
!>          the lowest model layer only, at the rate of Lee, Lewis and Read
!>          (2007), Superrotation in a Venus general circulation model,
!>          J. Geophys. Res., 112, E04S11, doi:10.1029/2006JE002874. It gives
!>          the atmosphere an exchange of angular momentum with the surface.
!>
module venus_wind_kernel_mod

  use argument_mod,      only: arg_type,          &
                               GH_FIELD, GH_REAL, &
                               GH_READ, GH_INC,   &
                               GH_SCALAR,         &
                               CELL_COLUMN
  use constants_mod,     only: r_def, i_def
  use fs_continuity_mod, only: W2
  use kernel_mod,        only: kernel_type

  implicit none

  private

  !> Drag rate on the lowest layer (s-1): one per 25 Earth days.
  real(kind=r_def), parameter, public :: venus_surface_drag_rate = &
                                         1.0_r_def / (25.0_r_def * 86400.0_r_def)

  !---------------------------------------------------------------------------
  ! Public types
  !---------------------------------------------------------------------------
  !> The type declaration for the kernel. Contains the metadata needed by the
  !> Psy layer.
  !>
  type, public, extends(kernel_type) :: venus_wind_kernel_type
    private
    type(arg_type) :: meta_args(4) = (/                 &
         arg_type(GH_FIELD,  GH_REAL, GH_INC,  W2),     &
         arg_type(GH_FIELD,  GH_REAL, GH_READ, W2),     &
         arg_type(GH_FIELD,  GH_REAL, GH_READ, W2),     &
         arg_type(GH_SCALAR, GH_REAL, GH_READ)          &
         /)
    integer :: operates_on = CELL_COLUMN
  contains
    procedure, nopass :: venus_wind_code
  end type

  !---------------------------------------------------------------------------
  ! Contained functions/subroutines
  !---------------------------------------------------------------------------
  public :: venus_wind_code

contains

!> @brief The subroutine which is called directly by the psy layer
!! @param[in] nlayers Integer the number of layers
!! @param[in,out] du u increment data
!! @param[in] u u data
!! @param[in] w2_rmultiplicity Reciprocal of multiplicity for W2
!! @param[in] dt The model timestep length
!! @param[in] ndf_w2 The number of degrees of freedom per cell for W2
!! @param[in] undf_w2 The number of unique degrees of freedom for W2
!! @param[in] map_w2 Integer array holding the dofmap for the cell at the
!>            base of the column for W2
subroutine venus_wind_code(nlayers,                 &
                           du, u, w2_rmultiplicity, &
                           dt,                      &
                           ndf_w2, undf_w2, map_w2  &
                           )

  implicit none

  ! Arguments
  integer(kind=i_def), intent(in) :: nlayers

  integer(kind=i_def), intent(in) :: ndf_w2, undf_w2

  real(kind=r_def), dimension(undf_w2), intent(inout) :: du
  real(kind=r_def), dimension(undf_w2), intent(in)    :: u, w2_rmultiplicity
  real(kind=r_def),                     intent(in)    :: dt

  integer(kind=i_def), dimension(ndf_w2), intent(in) :: map_w2

  ! Internal variables
  integer(kind=i_def) :: df

  ! Horizontal dofs of the lowest layer only. The vertical dofs keep the zero
  ! the increment field is initialised with.
  do df = 1, 4
    du(map_w2(df)) = du(map_w2(df)) - &
       venus_surface_drag_rate*u(map_w2(df))*dt*w2_rmultiplicity(map_w2(df))
  end do

end subroutine venus_wind_code

end module venus_wind_kernel_mod
