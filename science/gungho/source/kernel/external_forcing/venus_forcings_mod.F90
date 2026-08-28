!-----------------------------------------------------------------------------
! (c) Crown copyright 2026 Met Office. All rights reserved.
! The file LICENCE, distributed with this code, contains details of the terms
! under which the code may be used.
!-----------------------------------------------------------------------------
!> @brief Contains forcing terms for use in the idealised Venus kernel.
!>
!> @details Support functions for a kernel that relaxes potential temperature
!!          towards a prescribed Venus equilibrium profile on a radiative
!!          timescale (Newtonian cooling), following the pattern of the
!!          hot Jupiter and tidally locked Earth idealised tests.
!!
!!          The equilibrium temperature is tabulated against log10 of pressure
!!          and latitude, and interpolated bilinearly. It was derived from the
!!          Crisp radiative heating rate tables distributed with the LMD Venus
!!          PCM, as T_eq = T + tau * Q_net, where T and Q_net are the reference
!!          temperature and net radiative heating rate. The tables give the
!!          solar heating rate at eight solar zenith angles; the solar
!!          contribution to Q_net has been diurnally averaged at each latitude
!!          assuming zero obliquity, so that cos(sza) = cos(lat)*cos(h) and the
!!          average is taken over the illuminated half of the day. Venus's
!!          obliquity is small enough (about 2.6 degrees effective) that this
!!          leaves no seasonal cycle. The equator-to-pole contrast in T_eq
!!          peaks at about 21 K near 64 km and falls below 1 K below 50 km.
!!
!!          There is deliberately no longitudinal structure. Venus is not
!!          tidally locked - its solar day is about 117 Earth days - so a
!!          static day/night pattern would pin the substellar point to a fixed
!!          model longitude and manufacture a stationary wave that does not
!!          exist. Representing the diurnal cycle properly would require T_eq
!!          to depend on model time through the substellar longitude.
!!
!!          The relaxation timescale is the standard radiative estimate
!!            tau = cp * p / (4 * g * sigma * T_eq**3)
!!          evaluated from the namelist cp and gravity so that it stays
!!          consistent with the configured planet. This estimate assumes
!!          emission to space and so substantially underestimates tau in the
!!          optically thick deep atmosphere, where the true value is orders of
!!          magnitude larger. The relaxation is therefore tapered to zero below
!!          taper_top, leaving the deep atmosphere to the dynamics and its
!!          initial condition rather than pulling it towards a profile the
!!          estimate does not support.
!!
!!          This is an idealised configuration intended for exercising the
!!          dynamical core. It is not a substitute for radiative transfer.
!>
module venus_forcings_mod

  use constants_mod,     only: i_def, r_def, pi
  use planet_config_mod, only: cp, gravity, p_zero, kappa

  implicit none

  private

  public :: venus_equilibrium_temperature
  public :: venus_equilibrium_theta
  public :: venus_newton_frequency

  !> Number of pressure levels in the tabulated equilibrium profile.
  integer(kind=i_def), parameter :: nlev = 49
  !> Number of latitudes in the tabulated equilibrium profile.
  integer(kind=i_def), parameter :: nlat = 10

  !> Latitude spacing of the table (degrees). Latitudes run from the equator
  !> to the pole; the profile is symmetric, so magnitude of latitude is used.
  real(kind=r_def), parameter :: dlat_tab = 10.0_r_def

  !> Stefan-Boltzmann constant (W m-2 K-4).
  real(kind=r_def), parameter :: sigma_sb = 5.670374419E-08_r_def

  !> Heights between which the Newtonian relaxation is ramped off (m). Below
  !> taper_bot the forcing is zero; above taper_top it is applied in full.
  real(kind=r_def), parameter :: taper_bot = 3.0E4_r_def
  real(kind=r_def), parameter :: taper_top = 4.0E4_r_def

  !> log10 of pressure (Pa) at the tabulated levels, ascending.
  real(kind=r_def), parameter :: log10_p_tab(nlev) = (/  &
       7.535831E-01_r_def, 9.932157E-01_r_def, 1.232996E+00_r_def, 1.470557E+00_r_def,  &
       1.703721E+00_r_def, 1.931204E+00_r_def, 2.150756E+00_r_def, 2.361728E+00_r_def,  &
       2.562887E+00_r_def, 2.755112E+00_r_def, 2.940765E+00_r_def, 3.121231E+00_r_def,  &
       3.297761E+00_r_def, 3.469822E+00_r_def, 3.638489E+00_r_def, 3.805501E+00_r_def,  &
       3.968483E+00_r_def, 4.128722E+00_r_def, 4.285557E+00_r_def, 4.435367E+00_r_def,  &
       4.578639E+00_r_def, 4.713910E+00_r_def, 4.840733E+00_r_def, 4.960233E+00_r_def,  &
       5.073718E+00_r_def, 5.182700E+00_r_def, 5.287802E+00_r_def, 5.389166E+00_r_def,  &
       5.487845E+00_r_def, 5.583765E+00_r_def, 5.676694E+00_r_def, 5.766413E+00_r_def,  &
       5.852785E+00_r_def, 5.936262E+00_r_def, 6.017033E+00_r_def, 6.095169E+00_r_def,  &
       6.170995E+00_r_def, 6.244277E+00_r_def, 6.315970E+00_r_def, 6.385606E+00_r_def,  &
       6.452553E+00_r_def, 6.517855E+00_r_def, 6.582063E+00_r_def, 6.644931E+00_r_def,  &
       6.706291E+00_r_def, 6.766413E+00_r_def, 6.824776E+00_r_def, 6.881670E+00_r_def,  &
       6.937518E+00_r_def  /)

  !> Equilibrium temperature (K), by pressure level and latitude.
  real(kind=r_def), parameter :: t_eq_tab(nlev,nlat) = reshape( (/  &
       1.656110E+02_r_def, 1.631937E+02_r_def, 1.642597E+02_r_def, 1.669712E+02_r_def,  &
       1.707377E+02_r_def, 1.755904E+02_r_def, 1.825238E+02_r_def, 1.921725E+02_r_def,  &
       2.024980E+02_r_def, 2.121606E+02_r_def, 2.206707E+02_r_def, 2.282569E+02_r_def,  &
       2.356937E+02_r_def, 2.437132E+02_r_def, 2.527496E+02_r_def, 2.578188E+02_r_def,  &
       2.675968E+02_r_def, 2.794546E+02_r_def, 2.730740E+02_r_def, 2.777524E+02_r_def,  &
       2.918389E+02_r_def, 3.155744E+02_r_def, 3.283596E+02_r_def, 3.447456E+02_r_def,  &
       3.587455E+02_r_def, 3.636789E+02_r_def, 3.826453E+02_r_def, 3.970806E+02_r_def,  &
       4.096355E+02_r_def, 4.227620E+02_r_def, 4.379626E+02_r_def, 4.533465E+02_r_def,  &
       4.691189E+02_r_def, 4.864988E+02_r_def, 5.036143E+02_r_def, 5.209294E+02_r_def,  &
       5.373371E+02_r_def, 5.538184E+02_r_def, 5.712727E+02_r_def, 5.881964E+02_r_def,  &
       6.030978E+02_r_def, 6.166660E+02_r_def, 6.301773E+02_r_def, 6.450923E+02_r_def,  &
       6.614172E+02_r_def, 6.773468E+02_r_def, 6.933125E+02_r_def, 7.093132E+02_r_def,  &
       7.275879E+02_r_def, 1.655831E+02_r_def, 1.631831E+02_r_def, 1.642483E+02_r_def,  &
       1.669582E+02_r_def, 1.707233E+02_r_def, 1.755739E+02_r_def, 1.825039E+02_r_def,  &
       1.921488E+02_r_def, 2.024719E+02_r_def, 2.121332E+02_r_def, 2.206403E+02_r_def,  &
       2.282187E+02_r_def, 2.356418E+02_r_def, 2.436344E+02_r_def, 2.526152E+02_r_def,  &
       2.575770E+02_r_def, 2.671744E+02_r_def, 2.789453E+02_r_def, 2.727943E+02_r_def,  &
       2.775633E+02_r_def, 2.917439E+02_r_def, 3.154865E+02_r_def, 3.282989E+02_r_def,  &
       3.447053E+02_r_def, 3.587177E+02_r_def, 3.636637E+02_r_def, 3.826352E+02_r_def,  &
       3.970708E+02_r_def, 4.096258E+02_r_def, 4.227523E+02_r_def, 4.379531E+02_r_def,  &
       4.533371E+02_r_def, 4.691097E+02_r_def, 4.864899E+02_r_def, 5.036057E+02_r_def,  &
       5.209211E+02_r_def, 5.373292E+02_r_def, 5.538108E+02_r_def, 5.712656E+02_r_def,  &
       5.881897E+02_r_def, 6.030915E+02_r_def, 6.166602E+02_r_def, 6.301720E+02_r_def,  &
       6.450877E+02_r_def, 6.614132E+02_r_def, 6.773434E+02_r_def, 6.933098E+02_r_def,  &
       7.093111E+02_r_def, 7.275865E+02_r_def, 1.654984E+02_r_def, 1.631506E+02_r_def,  &
       1.642137E+02_r_def, 1.669187E+02_r_def, 1.706794E+02_r_def, 1.755238E+02_r_def,  &
       1.824432E+02_r_def, 1.920765E+02_r_def, 2.023926E+02_r_def, 2.120495E+02_r_def,  &
       2.205461E+02_r_def, 2.280995E+02_r_def, 2.354795E+02_r_def, 2.433886E+02_r_def,  &
       2.521986E+02_r_def, 2.568362E+02_r_def, 2.659021E+02_r_def, 2.774368E+02_r_def,  &
       2.719717E+02_r_def, 2.770071E+02_r_def, 2.914639E+02_r_def, 3.152269E+02_r_def,  &
       3.281193E+02_r_def, 3.445859E+02_r_def, 3.586357E+02_r_def, 3.636188E+02_r_def,  &
       3.826050E+02_r_def, 3.970417E+02_r_def, 4.095969E+02_r_def, 4.227237E+02_r_def,  &
       4.379248E+02_r_def, 4.533093E+02_r_def, 4.690825E+02_r_def, 4.864635E+02_r_def,  &
       5.035802E+02_r_def, 5.208965E+02_r_def, 5.373055E+02_r_def, 5.537882E+02_r_def,  &
       5.712443E+02_r_def, 5.881699E+02_r_def, 6.030731E+02_r_def, 6.166432E+02_r_def,  &
       6.301565E+02_r_def, 6.450739E+02_r_def, 6.614013E+02_r_def, 6.773334E+02_r_def,  &
       6.933016E+02_r_def, 7.093048E+02_r_def, 7.275821E+02_r_def, 1.653606E+02_r_def,  &
       1.630976E+02_r_def, 1.641573E+02_r_def, 1.668549E+02_r_def, 1.706083E+02_r_def,  &
       1.754424E+02_r_def, 1.823442E+02_r_def, 1.919586E+02_r_def, 2.022631E+02_r_def,  &
       2.119114E+02_r_def, 2.203870E+02_r_def, 2.278954E+02_r_def, 2.352021E+02_r_def,  &
       2.429719E+02_r_def, 2.515040E+02_r_def, 2.556353E+02_r_def, 2.639097E+02_r_def,  &
       2.751452E+02_r_def, 2.707350E+02_r_def, 2.761697E+02_r_def, 2.910400E+02_r_def,  &
       3.148333E+02_r_def, 3.278463E+02_r_def, 3.444042E+02_r_def, 3.585108E+02_r_def,  &
       3.635505E+02_r_def, 3.825591E+02_r_def, 3.969975E+02_r_def, 4.095530E+02_r_def,  &
       4.226801E+02_r_def, 4.378818E+02_r_def, 4.532670E+02_r_def, 4.690411E+02_r_def,  &
       4.864232E+02_r_def, 5.035413E+02_r_def, 5.208591E+02_r_def, 5.372696E+02_r_def,  &
       5.537539E+02_r_def, 5.712120E+02_r_def, 5.881396E+02_r_def, 6.030449E+02_r_def,  &
       6.166172E+02_r_def, 6.301329E+02_r_def, 6.450530E+02_r_def, 6.613831E+02_r_def,  &
       6.773181E+02_r_def, 6.932891E+02_r_def, 7.092952E+02_r_def, 7.275756E+02_r_def,  &
       1.651642E+02_r_def, 1.630219E+02_r_def, 1.640770E+02_r_def, 1.667643E+02_r_def,  &
       1.705078E+02_r_def, 1.753263E+02_r_def, 1.822023E+02_r_def, 1.917898E+02_r_def,  &
       2.020772E+02_r_def, 2.117108E+02_r_def, 2.201492E+02_r_def, 2.275853E+02_r_def,  &
       2.347819E+02_r_def, 2.423477E+02_r_def, 2.504860E+02_r_def, 2.539386E+02_r_def,  &
       2.612249E+02_r_def, 2.721837E+02_r_def, 2.691581E+02_r_def, 2.750991E+02_r_def,  &
       2.904942E+02_r_def, 3.143250E+02_r_def, 3.274925E+02_r_def, 3.441683E+02_r_def,  &
       3.583484E+02_r_def, 3.634617E+02_r_def, 3.824995E+02_r_def, 3.969401E+02_r_def,  &
       4.094960E+02_r_def, 4.226234E+02_r_def, 4.378259E+02_r_def, 4.532120E+02_r_def,  &
       4.689872E+02_r_def, 4.863710E+02_r_def, 5.034907E+02_r_def, 5.208103E+02_r_def,  &
       5.372228E+02_r_def, 5.537093E+02_r_def, 5.711699E+02_r_def, 5.881003E+02_r_def,  &
       6.030084E+02_r_def, 6.165834E+02_r_def, 6.301022E+02_r_def, 6.450257E+02_r_def,  &
       6.613595E+02_r_def, 6.772981E+02_r_def, 6.932729E+02_r_def, 7.092827E+02_r_def,  &
       7.275670E+02_r_def, 1.649100E+02_r_def, 1.629235E+02_r_def, 1.639732E+02_r_def,  &
       1.666483E+02_r_def, 1.703789E+02_r_def, 1.751756E+02_r_def, 1.820168E+02_r_def,  &
       1.915693E+02_r_def, 2.018350E+02_r_def, 2.114421E+02_r_def, 2.198180E+02_r_def,  &
       2.271472E+02_r_def, 2.341956E+02_r_def, 2.414971E+02_r_def, 2.491492E+02_r_def,  &
       2.518382E+02_r_def, 2.581333E+02_r_def, 2.689491E+02_r_def, 2.674521E+02_r_def,  &
       2.739323E+02_r_def, 2.898937E+02_r_def, 3.137635E+02_r_def, 3.270998E+02_r_def,  &
       3.439061E+02_r_def, 3.581679E+02_r_def, 3.633628E+02_r_def, 3.824331E+02_r_def,  &
       3.968762E+02_r_def, 4.094324E+02_r_def, 4.225603E+02_r_def, 4.377636E+02_r_def,  &
       4.531507E+02_r_def, 4.689272E+02_r_def, 4.863127E+02_r_def, 5.034344E+02_r_def,  &
       5.207561E+02_r_def, 5.371706E+02_r_def, 5.536595E+02_r_def, 5.711231E+02_r_def,  &
       5.880565E+02_r_def, 6.029676E+02_r_def, 6.165458E+02_r_def, 6.300680E+02_r_def,  &
       6.449953E+02_r_def, 6.613332E+02_r_def, 6.772759E+02_r_def, 6.932548E+02_r_def,  &
       7.092687E+02_r_def, 7.275574E+02_r_def, 1.646013E+02_r_def, 1.628035E+02_r_def,  &
       1.638477E+02_r_def, 1.665095E+02_r_def, 1.702240E+02_r_def, 1.749916E+02_r_def,  &
       1.817888E+02_r_def, 1.912996E+02_r_def, 2.015381E+02_r_def, 2.111018E+02_r_def,  &
       2.193851E+02_r_def, 2.265758E+02_r_def, 2.334523E+02_r_def, 2.404584E+02_r_def,  &
       2.475928E+02_r_def, 2.495402E+02_r_def, 2.549482E+02_r_def, 2.657143E+02_r_def,  &
       2.657461E+02_r_def, 2.727564E+02_r_def, 2.892846E+02_r_def, 3.131923E+02_r_def,  &
       3.266990E+02_r_def, 3.436381E+02_r_def, 3.579833E+02_r_def, 3.632618E+02_r_def,  &
       3.823653E+02_r_def, 3.968108E+02_r_def, 4.093675E+02_r_def, 4.224958E+02_r_def,  &
       4.376999E+02_r_def, 4.530881E+02_r_def, 4.688658E+02_r_def, 4.862532E+02_r_def,  &
       5.033768E+02_r_def, 5.207006E+02_r_def, 5.371173E+02_r_def, 5.536087E+02_r_def,  &
       5.710751E+02_r_def, 5.880117E+02_r_def, 6.029259E+02_r_def, 6.165073E+02_r_def,  &
       6.300330E+02_r_def, 6.449641E+02_r_def, 6.613062E+02_r_def, 6.772532E+02_r_def,  &
       6.932363E+02_r_def, 7.092544E+02_r_def, 7.275477E+02_r_def, 1.642213E+02_r_def,  &
       1.626554E+02_r_def, 1.636947E+02_r_def, 1.663426E+02_r_def, 1.700357E+02_r_def,  &
       1.747627E+02_r_def, 1.815037E+02_r_def, 1.909650E+02_r_def, 2.011674E+02_r_def,  &
       2.106581E+02_r_def, 2.188044E+02_r_def, 2.258209E+02_r_def, 2.325159E+02_r_def,  &
       2.392244E+02_r_def, 2.458737E+02_r_def, 2.472288E+02_r_def, 2.520034E+02_r_def,  &
       2.628046E+02_r_def, 2.641979E+02_r_def, 2.716757E+02_r_def, 2.887204E+02_r_def,  &
       3.126613E+02_r_def, 3.263250E+02_r_def, 3.433877E+02_r_def, 3.578107E+02_r_def,  &
       3.631672E+02_r_def, 3.823019E+02_r_def, 3.967497E+02_r_def, 4.093067E+02_r_def,  &
       4.224354E+02_r_def, 4.376403E+02_r_def, 4.530294E+02_r_def, 4.688084E+02_r_def,  &
       4.861974E+02_r_def, 5.033228E+02_r_def, 5.206486E+02_r_def, 5.370674E+02_r_def,  &
       5.535610E+02_r_def, 5.710302E+02_r_def, 5.879697E+02_r_def, 6.028868E+02_r_def,  &
       6.164712E+02_r_def, 6.300002E+02_r_def, 6.449350E+02_r_def, 6.612810E+02_r_def,  &
       6.772319E+02_r_def, 6.932189E+02_r_def, 7.092411E+02_r_def, 7.275385E+02_r_def,  &
       1.637504E+02_r_def, 1.624730E+02_r_def, 1.635109E+02_r_def, 1.661436E+02_r_def,  &
       1.698021E+02_r_def, 1.744718E+02_r_def, 1.811448E+02_r_def, 1.905496E+02_r_def,  &
       2.006951E+02_r_def, 2.100669E+02_r_def, 2.180426E+02_r_def, 2.249096E+02_r_def,  &
       2.315089E+02_r_def, 2.380443E+02_r_def, 2.443890E+02_r_def, 2.453559E+02_r_def,  &
       2.496127E+02_r_def, 2.603835E+02_r_def, 2.628956E+02_r_def, 2.707619E+02_r_def,  &
       2.882434E+02_r_def, 3.122123E+02_r_def, 3.260081E+02_r_def, 3.431753E+02_r_def,  &
       3.576642E+02_r_def, 3.630869E+02_r_def, 3.822479E+02_r_def, 3.966977E+02_r_def,  &
       4.092550E+02_r_def, 4.223841E+02_r_def, 4.375897E+02_r_def, 4.529796E+02_r_def,  &
       4.687595E+02_r_def, 4.861500E+02_r_def, 5.032770E+02_r_def, 5.206045E+02_r_def,  &
       5.370249E+02_r_def, 5.535205E+02_r_def, 5.709920E+02_r_def, 5.879340E+02_r_def,  &
       6.028536E+02_r_def, 6.164406E+02_r_def, 6.299723E+02_r_def, 6.449102E+02_r_def,  &
       6.612595E+02_r_def, 6.772138E+02_r_def, 6.932042E+02_r_def, 7.092297E+02_r_def,  &
       7.275307E+02_r_def, 1.630030E+02_r_def, 1.621930E+02_r_def, 1.632352E+02_r_def,  &
       1.658276E+02_r_def, 1.693940E+02_r_def, 1.739732E+02_r_def, 1.805647E+02_r_def,  &
       1.898928E+02_r_def, 1.999655E+02_r_def, 2.092103E+02_r_def, 2.171541E+02_r_def,  &
       2.241126E+02_r_def, 2.308213E+02_r_def, 2.373515E+02_r_def, 2.435380E+02_r_def,  &
       2.442236E+02_r_def, 2.480546E+02_r_def, 2.587489E+02_r_def, 2.620106E+02_r_def,  &
       2.701395E+02_r_def, 2.879197E+02_r_def, 3.119080E+02_r_def, 3.257929E+02_r_def,  &
       3.430310E+02_r_def, 3.575646E+02_r_def, 3.630323E+02_r_def, 3.822112E+02_r_def,  &
       3.966623E+02_r_def, 4.092198E+02_r_def, 4.223491E+02_r_def, 4.375551E+02_r_def,  &
       4.529456E+02_r_def, 4.687263E+02_r_def, 4.861177E+02_r_def, 5.032457E+02_r_def,  &
       5.205744E+02_r_def, 5.369960E+02_r_def, 5.534930E+02_r_def, 5.709661E+02_r_def,  &
       5.879097E+02_r_def, 6.028310E+02_r_def, 6.164197E+02_r_def, 6.299533E+02_r_def,  &
       6.448933E+02_r_def, 6.612449E+02_r_def, 6.772015E+02_r_def, 6.931942E+02_r_def,  &
       7.092220E+02_r_def, 7.275254E+02_r_def  /), (/ nlev, nlat /) )

contains

!> @brief Interpolates the tabulated equilibrium temperature.
!> @details Bilinear in log10(pressure) and latitude, clamped to the end
!!          values outside the tabulated range so that the profile stays
!!          finite for any domain height. Clamping means the top of the domain
!!          should not extend far above the top of the table (about 98 km) if
!!          the upper atmosphere matters for the intended experiment.
!> @param[in] pressure  Pressure (Pa)
!> @param[in] lat       Latitude (radians)
!> @return    t_eq      Equilibrium temperature (K)
function venus_equilibrium_temperature(pressure, lat) result(t_eq)

  implicit none

  ! Arguments
  real(kind=r_def), intent(in) :: pressure, lat

  ! Local variables
  integer(kind=i_def) :: k, j
  real(kind=r_def)    :: x, lat_deg, wp, wl, t_lo, t_hi, t_eq

  x = log10(pressure)

  ! Pressure index and weight
  if (x <= log10_p_tab(1)) then
    k = 1_i_def
    wp = 0.0_r_def
  else if (x >= log10_p_tab(nlev)) then
    k = nlev - 1_i_def
    wp = 1.0_r_def
  else
    ! Table is small and ascending, so a linear scan is adequate here.
    k = 1_i_def
    do while (x > log10_p_tab(k+1))
      k = k + 1_i_def
    end do
    wp = (x - log10_p_tab(k)) / (log10_p_tab(k+1) - log10_p_tab(k))
  end if

  ! Latitude index and weight. The table is uniformly spaced and symmetric
  ! about the equator.
  lat_deg = abs(lat) * 180.0_r_def / pi
  if (lat_deg >= dlat_tab*real(nlat-1_i_def, r_def)) then
    j = nlat - 1_i_def
    wl = 1.0_r_def
  else
    j = 1_i_def + int(lat_deg / dlat_tab, i_def)
    wl = (lat_deg - dlat_tab*real(j-1_i_def, r_def)) / dlat_tab
  end if

  t_lo = t_eq_tab(k,j)   + wp * (t_eq_tab(k+1,j)   - t_eq_tab(k,j))
  t_hi = t_eq_tab(k,j+1) + wp * (t_eq_tab(k+1,j+1) - t_eq_tab(k,j+1))

  t_eq = t_lo + wl * (t_hi - t_lo)

end function venus_equilibrium_temperature

!> @brief Function to calculate equilibrium theta for the Venus temperature forcing.
!> @param[in] exner     Exner pressure
!> @param[in] lat       Latitude (radians)
!> @return    theta_eq  Equilibrium potential temperature (K)
function venus_equilibrium_theta(exner, lat) result(theta_eq)

  implicit none

  ! Arguments
  real(kind=r_def), intent(in) :: exner, lat

  ! Local variables
  real(kind=r_def) :: t_eq, theta_eq

  t_eq = venus_equilibrium_temperature(pressure_from_exner(exner), lat)

  ! Recall using potential temperature
  ! Therefore, must convert the temperature to potential
  theta_eq = t_eq / exner

end function venus_equilibrium_theta

!> @brief Function to calculate the Newton relaxation frequency for the Venus
!!        idealised test case.
!> @details The radiative timescale is estimated as cp*p/(4*g*sigma*T_eq**3)
!!          and ramped linearly to zero between taper_top and taper_bot.
!> @param[in] exner              Exner pressure
!> @param[in] lat                Latitude (radians)
!> @param[in] height             Height above the surface (m)
!> @return    venus_frequency    Newton cooling relaxation frequency (s-1)
function venus_newton_frequency(exner, lat, height) result(venus_frequency)

  implicit none

  ! Arguments
  real(kind=r_def), intent(in) :: exner, lat, height

  ! Local variables
  real(kind=r_def) :: pressure, t_eq, tau, taper, venus_frequency

  if (height <= taper_bot) then
    venus_frequency = 0.0_r_def
  else
    pressure = pressure_from_exner(exner)
    t_eq = venus_equilibrium_temperature(pressure, lat)

    tau = cp * pressure / (4.0_r_def * gravity * sigma_sb * t_eq**3_i_def)

    if (height >= taper_top) then
      taper = 1.0_r_def
    else
      taper = (height - taper_bot) / (taper_top - taper_bot)
    end if

    venus_frequency = taper / tau
  end if

end function venus_newton_frequency

!> @brief Function to calculate pressure from exner function
!> @param[in] exner         Exner pressure
!> @return    pressure      Pressure
function pressure_from_exner(exner) result(pressure)

  implicit none

  ! Arguments
  real(kind=r_def), intent(in) :: exner

  ! Local variables
  real(kind=r_def) :: pressure

  pressure = p_zero * exner ** (1.0_r_def / kappa)

end function pressure_from_exner

end module venus_forcings_mod
