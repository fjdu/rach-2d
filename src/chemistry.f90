module chemistry

use trivials
use phy_const
use data_struct

implicit none

integer, parameter, private :: const_len_species_name       = 12
integer, parameter, private :: const_len_reactionfile_row   = 150
integer, parameter, private :: const_len_init_abun_file_row = 64
integer, parameter, private :: const_nSpecies_guess         = 512
integer, parameter, private :: const_n_dupli_max_guess      = 16
integer, parameter, private :: const_n_reac_max             = 3
integer, parameter, private :: const_n_prod_max             = 4
integer, parameter, private :: const_nElement               = 17
character(LEN=8), dimension(const_nElement), parameter :: &
  const_nameElements = &
    (/'+-      ', 'E       ', 'Grain   ', 'H       ', &
      'D       ', 'He      ', 'C       ', 'N       ', &
      'O       ', 'Si      ', 'S       ', 'Fe      ', &
      'Na      ', 'Mg      ', 'Cl      ', 'P       ', &
      'F       '/)
double precision, dimension(const_nElement), parameter :: &
  const_ElementMassNumber = &
    (/0D0,        5.45D-4,    0D0,        1D0,        &
      2D0,        4D0,        12D0,       14D0,       &
      16D0,       28D0,       32D0,       56D0,       &
      23D0,       24D0,       35.5D0,     31D0,       &
      19D0/)

type :: type_chemical_evol_idx_species
  integer i_H2, i_HI, i_E, i_CI, i_Cplus, i_OI, i_CO, i_H2O, i_OH, i_Hplus, i_gH2
  integer iiH2, iiHI, iiE, iiCI, iiCplus, iiOI, iiCO, iiH2O, iiOH, iiHplus, iigH2
  integer :: nItem = 11
  integer, dimension(:), allocatable :: idx
  character(len=8), dimension(11) :: names = &
    (/'H2      ', 'H       ', 'E-      ', 'C       ', 'C+      ', &
      'O       ', 'CO      ', 'H2O     ', 'OH      ', 'H+      ', &
      'gH2     '/)
end type type_chemical_evol_idx_species

type :: type_chemical_evol_reactions_str
  integer nReactions
  character :: commentChar = '!'
  character(len=const_len_reactionfile_row), dimension(:), allocatable :: list
end type type_chemical_evol_reactions_str

type :: type_chemical_evol_a_list
  integer nItem
  integer, dimension(:), allocatable :: list
end type type_chemical_evol_a_list

type :: type_chemical_evol_reactions
  integer nReactions
  character(len=const_len_species_name), dimension(:,:), allocatable :: &
    reac_names, prod_names
  integer, dimension(:,:), allocatable :: reac, prod
  integer, dimension(:), allocatable :: n_reac, n_prod
  double precision, dimension(:,:), allocatable :: ABC
  double precision, dimension(:,:), allocatable :: T_range
  integer, dimension(:), allocatable :: itype
  character(len=2), dimension(:), allocatable :: ctype
  character, dimension(:), allocatable :: quality
  double precision, dimension(:), allocatable :: rates
  type(type_chemical_evol_a_list), dimension(:), allocatable :: dupli
end type type_chemical_evol_reactions

type :: type_chemical_evol_species
  integer nSpecies
  character(len=const_len_species_name), dimension(:), allocatable :: names
  double precision, dimension(:), allocatable :: mass_num
  double precision, dimension(:), allocatable :: vib_freq
  double precision, dimension(:), allocatable :: Edesorb
  double precision, dimension(:), allocatable :: adsorb_coeff
  double precision, dimension(:), allocatable :: desorb_coeff
  integer, dimension(:,:), allocatable :: elements
  type(type_chemical_evol_a_list), dimension(:), allocatable :: prod, cons
end type type_chemical_evol_species

type :: type_chemical_evol_solver_params
  character(len=128) chem_files_dir, filename_chemical_network, filename_initial_abundances
  double precision RTOL, ATOL
  double precision t_max, dt_first_step, ratio_tstep
  logical allow_stop_before_t_max
  real :: max_runtime_allowed = 3600.0 ! seconds
  integer n_record, n_record_real
  integer NEQ, ITOL, ITASK, ISTATE, IOPT, LIW, LRW, MF, NNZ
  integer NERR
end type type_chemical_evol_solver_params

type :: type_chemical_evol_solver_storage
  double precision, dimension(:), allocatable :: RWORK
  integer, dimension(:), allocatable :: IWORK
  logical, dimension(:, :), allocatable :: sparseMaskJac
  double precision, dimension(:), allocatable :: y
  double precision, dimension(:), allocatable :: ydot
  double precision, dimension(:), allocatable :: touts
  double precision, dimension(:, :), allocatable :: record
end type type_chemical_evol_solver_storage

type(type_chemical_evol_reactions_str)  :: chem_reac_str

type(type_chemical_evol_idx_species)    :: chem_idx_some_spe

type(type_chemical_evol_reactions)      :: chem_net

type(type_chemical_evol_species)        :: chem_species

type(type_chemical_evol_solver_params)  :: chem_solver_params
type(type_chemical_evol_solver_storage) :: chem_solver_storage

! This thing is specific to each cell.
type(type_cell_rz_phy_basic), pointer   :: chem_params => null()


double precision, parameter :: const_cosmicray_intensity_0 = 1.36D-17 ! UMIST paper
double precision, parameter :: CosmicDesorpPreFactor = 3.16D-19
double precision, parameter :: CosmicDesorpGrainT = 70D0
double precision, parameter :: SitesDensity_CGS = 1D15

namelist /chemistry_configure/ &
  chem_solver_params


contains


subroutine chem_load_initial_abundances
  integer fU, i, ios
  character(len=const_len_init_abun_file_row) str
  if (.NOT. getFileUnit (fU)) then
    write(*,*) 'Cannot get a file unit!  In chem_load_initial_abundances.'
    stop
  end if
  call openFileSequentialRead(fU, combine_dir_filename(chem_solver_params%chem_files_dir, &
                                  chem_solver_params%filename_initial_abundances), 999)
  chem_solver_storage%y = 0D0
  do
    read(fU, FMT='(A)', IOSTAT=ios) str
    if (ios .NE. 0) then
      exit
    end if
    do i=1, chem_species%nSpecies
      if (trim(str(1:const_len_species_name)) .EQ. chem_species%names(i)) then
        read(str(const_len_species_name+1:const_len_init_abun_file_row), &
          '(ES16.6)') chem_solver_storage%y(i)
        exit
      end if
    end do
  end do
  close(fU)
end subroutine chem_load_initial_abundances


subroutine chem_evol_solve_prepare
  !chem_solver_params%allow_stop_before_t_max = .FALSE.
  !chem_solver_params%dt_first_step = 1D-3
  !chem_solver_params%ratio_tstep = 1.4D0
  !chem_solver_params%max_runtime_allowed = 60.0
  chem_solver_params%n_record = ceiling( &
    log(chem_solver_params%t_max / chem_solver_params%dt_first_step * &
        (chem_solver_params%ratio_tstep - 1D0) + 1D0) &
    / &
    log(chem_solver_params%ratio_tstep))
  if (.NOT. allocated(chem_solver_storage%y)) then
    allocate(&
      chem_solver_storage%y(chem_species%nSpecies), &
      chem_solver_storage%ydot(chem_species%nSpecies), &
      chem_solver_storage%touts(chem_solver_params%n_record), &
      chem_solver_storage%record(chem_species%nSpecies, chem_solver_params%n_record))
  end if
end subroutine chem_evol_solve_prepare


subroutine chem_set_solver_flags
  chem_solver_params%IOPT = 1 ! 1: allow optional input; 0: disallow
  chem_solver_params%MF = 021 ! Line 2557 of opkdmain.f
  chem_solver_params%NERR = 0 ! for counting number of errors in iteration
  chem_solver_params%ITOL = 1 ! scalar control of tolerance
  chem_solver_params%ITASK = 1 ! normal, allow overshoot
  chem_solver_params%ISTATE = 1 ! first call
  !chem_solver_params%RTOL = 1D-6
  !chem_solver_params%ATOL = 1D-30
end subroutine chem_set_solver_flags


subroutine chem_evol_solve
  use my_timer
  external chem_ode_f, chem_ode_jac
  integer i, itmp
  double precision t, tout, t_step, t_scale_min
  double precision :: const_factor = 1D3
  type(atimer) timer
  real time_thisstep, runtime_thisstep, time_laststep, runtime_laststep
  !--
  character(len=128) :: chem_evol_save_filename = 'chem_evol_tmp.dat'
  character(len=32) fmtstr
  logical flag_chem_evol_save
  integer fU_chem_evol_save
  flag_chem_evol_save = .false.
  if (flag_chem_evol_save) then
    if (.not. getFileUnit(fU_chem_evol_save)) then
      write(*,*) 'Cannot get a unit for output!  In chem_evol_solve.'
      stop
    end if
    call openFileSequentialWrite(fU_chem_evol_save, chem_evol_save_filename, 99999)
    write(fmtstr, '("(", I4, "A14)")') chem_species%nSpecies+1
    write(fU_chem_evol_save, fmtstr) '!Time', chem_species%names(1:chem_species%nSpecies)
    write(fmtstr, '("(", I4, "ES14.4E4)")') chem_species%nSpecies+1
  end if
  !--
  t = 0D0
  tout = chem_solver_params%dt_first_step
  t_step = chem_solver_params%dt_first_step
  chem_solver_storage%touts(1) = tout
  chem_solver_storage%record(:,1) = chem_solver_storage%y
  !
  call timer%init('Chem')
  time_laststep = timer%elapsed_time()
  runtime_laststep = huge(0.0)
  !
  do i=2, chem_solver_params%n_record
    write (*, '(A, "Solving... ", I6, " (", F5.1, "%)", "  t = ", ES9.2, "  tStep = ", ES9.2)') &
      CHAR(27)//'[A', i, real(i*100)/real(chem_solver_params%n_record), t, t_step
    call DLSODES( &
         chem_ode_f, &
         !
         chem_solver_params%NEQ, &
         chem_solver_storage%y, &
         !
         t, &
         tout, &
         !
         chem_solver_params%ITOL, &
         chem_solver_params%RTOL, &
         chem_solver_params%ATOL, &
         chem_solver_params%ITASK, &
         chem_solver_params%ISTATE, &
         chem_solver_params%IOPT, &
         chem_solver_storage%RWORK, &
         chem_solver_params%LRW, &
         chem_solver_storage%IWORK, &
         chem_solver_params%LIW, &
         !
         chem_ode_jac, &
         !
         chem_solver_params%MF)
    !--
    if (flag_chem_evol_save) then
      write(fU_chem_evol_save, fmtstr) tout, chem_solver_storage%y
    end if
    !--
    time_thisstep = timer%elapsed_time()
    runtime_thisstep = time_thisstep - time_laststep
    if ((runtime_thisstep .gt. max(5.0*runtime_laststep, 0.1*chem_solver_params%max_runtime_allowed)) &
        .or. &
        (time_thisstep .gt. chem_solver_params%max_runtime_allowed)) then
      write(*, '(A, ES9.2/)') 'Premature finish: t = ', t
      exit
    end if
    time_laststep = time_thisstep
    runtime_laststep = runtime_thisstep
    !
    if (chem_solver_params%ISTATE .LT. 0) then
      chem_solver_params%NERR = chem_solver_params%NERR + 1
      write(*, '(A, I3/)') 'Error: ', chem_solver_params%ISTATE
      chem_solver_params%ISTATE = 3
    end if
    if (chem_solver_params%allow_stop_before_t_max) then
      call dintdy(t, 1, &
        chem_solver_storage%RWORK(chem_solver_storage%IWORK(22)), &
        chem_solver_params%NEQ, chem_solver_storage%ydot, itmp)
      !where (chem_solver_storage%y .LE. 1D-15)
      !  chem_solver_storage%ydot = 1D-200
      !end where
      t_scale_min = minval(abs(chem_solver_storage%y(chem_idx_some_spe%idx) / &
                     chem_solver_storage%ydot(chem_idx_some_spe%idx)))
      if (t_scale_min .GT. const_factor * chem_solver_params%t_max) then
        chem_solver_params%n_record_real = i
        write(*, '(A, ES9.2, 2X, A, ES9.2/)') 'Early finishing: t_scale_min = ', &
          t_scale_min, ' t = ', t
        exit
      end if
    end if
    chem_solver_storage%touts(i) = tout
    chem_solver_storage%record(:,i) = chem_solver_storage%y
    t_step = t_step * chem_solver_params%ratio_tstep
    tout = t + t_step
  end do
  !--
  if (flag_chem_evol_save) then
    close(fU_chem_evol_save)
  end if
  !--
end subroutine chem_evol_solve


subroutine chem_cal_rates
  integer i, j, k, i1, i2
  double precision T300, TemperatureReduced, JNegaPosi, JChargeNeut
  double precision, dimension(4) :: tmpVecReal
  integer, dimension(1) :: tmpVecInt
  double precision :: SitesPerGrain
  T300 = chem_params%Tgas / 300D0
  TemperatureReduced = phy_kBoltzmann_SI * chem_params%Tgas / &
    (phy_elementaryCharge_SI**2 * phy_CoulombConst_SI / &
    (chem_params%GrainRadius_CGS*1D-4))
  ! Pagani 2009, equation 11, 12, 13; not activated here.
  ! JNegaPosi = (1D0 + 1D0/TemperatureReduced) * &
  !             (1D0 + sqrt(2D0/(2D0+TemperatureReduced)))
  ! JChargeNeut = (1D0 + sqrt(phy_Pi/2D0/TemperatureReduced))
  !
  SitesPerGrain = SitesDensity_CGS * (4D0 * phy_Pi * chem_params%GrainRadius_CGS**2)
  !
  if (chem_params%ratioDust2HnucNum .LT. 1D-80) then ! If not set, calculate it.
    chem_params%ratioDust2HnucNum = & ! n_Grain/n_H
      chem_params%ratioDust2GasMass * (phy_mProton_CGS * chem_params%MeanMolWeight) &
      / (4.0D0*phy_Pi/3.0D0 * (chem_params%GrainRadius_CGS)**3 * &
         chem_params%GrainMaterialDensity_CGS)
  end if
  ! Le Petit 2009, equation 46 (not quite clear)
  ! Le Bourlot 1995, Appendix A
  ! Formation rate of H2:
  !   d/dt n(H2) = chem_params%R_H2_form_rate * n(H) * n_gas
  !if (chem_params%R_H2_form_rate .LT. 1D-80) then ! If not set, calculate it.
  !  ! Le Petit 2006
  !  chem_params%stickCoeffH = sqrt(10D0/max(10D0, chem_params%Tgas))
  !  chem_params%R_H2_form_rate = 0.5D0 * chem_params%stickCoeffH &
  !    * 3D0 / 4D0 * chem_params%MeanMolWeight * phy_mProton_CGS &
  !    * chem_params%ratioDust2GasMass / chem_params%GrainMaterialDensity_CGS &
  !    / sqrt(chem_params%aGrainMin_CGS * chem_params%aGrainMax_CGS) &
  !    * sqrt(8D0*phy_kBoltzmann_CGS*chem_params%Tgas/(phy_Pi * phy_mProton_CGS))
  !end if
  !
  do i=1, chem_net%nReactions
    ! Reactions with very negative barriers AND with a temperature range not
    ! quite applicable are discarded.
    ! To check the most up-to-date UMIST document to see if there is any
    ! more detailed prescription for this.
    !
    ! Reactions with negative barriers are evil!
    !if (chem_net%ABC(3, i) .LT. -100D0) then
    !  if ((minval(chem_net%T_range(:,i)/chem_params%Tgas) .GE. 2D0) .OR. &
    !      (minval(chem_params%Tgas/chem_net%T_range(:,i)) .GE. 2D0)) then
    !    cycle
    !  end if
    !endif
    if (chem_net%ABC(3, i) .LT. 0D0) then
      cycle
    end if
    select case (chem_net%itype(i))
      case (5, 53) !- Reactions with itype=53 need not be included.
        chem_net%rates(i) = chem_net%ABC(1, i) * (T300**chem_net%ABC(2, i)) &
            * exp(-chem_net%ABC(3, i)/chem_params%Tgas)
      case (1)
        chem_net%rates(i) = (chem_params%zeta_cosmicray_H2/const_cosmicray_intensity_0) &
            * chem_net%ABC(1, i)
      case (2) ! Todo
        chem_net%rates(i) = (chem_params%zeta_cosmicray_H2/const_cosmicray_intensity_0) &
            * chem_net%ABC(1, i) * (T300**chem_net%ABC(2, i)) &
            * chem_net%ABC(3, i) / (1D0 - chem_params%omega_albedo)
      case (3) ! Todo
        chem_net%rates(i) = chem_params%UV_G0_factor &
            * chem_net%ABC(1, i) &
            * exp(-chem_net%ABC(3, i) * chem_params%Av) &
            * f_selfshielding(i)
      case (13)
        chem_net%rates(i) = chem_params%LymanAlpha_flux_0 &
            * chem_net%ABC(1, i) &
            * exp(-chem_net%ABC(3, i) * chem_params%Av) &
            * f_selfshielding(i)
      !case (0)
      !  chem_net%rates(i) = chem_net%ABC(1, i) * chem_params%R_H2_form_rate
      case (61) ! Adsorption
        ! rates(i) * Population =  number of i molecules 
        !   accreted per grain per unit time
        ! Pi * r**2 * V * n
        ! Also take into account the possible effect of
        !   stick coefficient and other temperature dependence 
        !   (e.g., coloumb focus).
        chem_net%rates(i) = &
          chem_net%ABC(1, i) * phy_Pi * chem_params%GrainRadius_CGS**2 &
          * sqrt(8D0/phy_Pi*phy_kBoltzmann_CGS*chem_params%Tgas &
                 / (chem_species%mass_num(chem_net%reac(1, i)) * phy_mProton_CGS)) &
          * chem_params%n_dust
        chem_species%adsorb_coeff(chem_net%reac(1, i)) = chem_net%rates(i)
        chem_species%adsorb_coeff(chem_net%prod(1, i)) = chem_net%rates(i)
      case (62) ! Desorption
        ! <timestamp>2011-06-10 Fri 18:07:51</timestamp>
        !     A serious typo is corrected.
        chem_net%rates(i) = &
          chem_species%vib_freq(chem_net%reac(1, i)) &
          * exp(-chem_net%ABC(3, i)/chem_params%Tdust) &
          ! Cosmic ray desorption rate from Hasegawa1993.
          + CosmicDesorpPreFactor * exp(-chem_net%ABC(3, i)/CosmicDesorpGrainT)
        if (chem_net%reac_names(1, i) .eq. 'gH2') then
          chem_params%R_H2_form_rate_coeff = chem_net%rates(i)
        end if
        chem_species%desorb_coeff(chem_net%reac(1, i)) = chem_net%rates(i)
        chem_species%desorb_coeff(chem_net%prod(1, i)) = chem_net%rates(i)
      case (63) ! A + A -> xxx
        i1 = chem_net%reac(1, i)
        chem_net%rates(i) = &
          getMobility(chem_species%vib_freq(i1), &
                      chem_species%mass_num(i1), &
                      chem_species%Edesorb(i1), chem_params%Tdust) &
          / (SitesPerGrain * chem_params%ratioDust2HnucNum)
        ! Todo
        chem_net%rates(i) = chem_net%rates(i) * chem_species%adsorb_coeff(chem_net%reac(1, i)) &
                         / (chem_net%rates(i) + chem_species%desorb_coeff(chem_net%reac(1, i)))
      case (64) ! A + B -> xxx
        i1 = chem_net%reac(1, i)
        i2 = chem_net%reac(2, i)
        chem_net%rates(i) = ( &
          getMobility(chem_species%vib_freq(i1), &
                      chem_species%mass_num(i1), &
                      chem_species%Edesorb(i1), chem_params%Tdust) &
          + &
          getMobility(chem_species%vib_freq(i2), &
                      chem_species%mass_num(i2), &
                      chem_species%Edesorb(i2), chem_params%Tdust)) &
          / (SitesPerGrain * chem_params%ratioDust2HnucNum)
      case default
        chem_net%rates(i) = 0D0
    end select
    ! Change the time unit from seconds into years.
    chem_net%rates(i) = chem_net%rates(i) * phy_SecondsPerYear
    ! dn/dt = k n1 n2 => dx/dt := d(n/n_H)/dt = k*n_H x1 x2
    if ((chem_net%n_reac(i) .EQ. 2) .and. (chem_net%itype(i) .lt. 60)) then
      chem_net%rates(i) = chem_net%rates(i) * chem_params%n_gas
    end if
    ! Choose the reaction with temperature range that
    ! best matches the current temperature.
    ! Since different locations can have very different temperatures,
    ! it is important to do this for each location.
    if (chem_net%dupli(i)%nItem .GT. 0) then
      do j=1, chem_net%dupli(i)%nItem
        k = chem_net%dupli(i)%list(j)
        tmpVecReal(1:2) = abs(chem_net%T_range(:,k) - chem_params%Tgas)
        tmpVecReal(3:4) = abs(chem_net%T_range(:,i) - chem_params%Tgas)
        tmpVecInt = minloc(tmpVecReal)
        i1 = tmpVecInt(1)
        if ((i1 .EQ. 1) .OR. (i1 .EQ. 2)) then
          chem_net%rates(i) = 0D0
          exit
        end if
        if ((i1 .EQ. 3) .OR. (i1 .EQ. 4)) then
          chem_net%rates(k) = 0D0
          cycle
        end if
      end do
    end if
  end do
end subroutine chem_cal_rates


function f_selfshielding(iReac)
  double precision f_selfshielding
  integer iReac
  if ((chem_net%ctype(iReac) .NE. 'PH') .OR. &
      (chem_net%ctype(iReac) .NE. 'LA')) then
    f_selfshielding = 1D0
    return
  end if
  select case (chem_species%names(chem_net%reac(1, iReac)))
    case ('H2')
      f_selfshielding = chem_params%f_selfshielding_H2
    case ('H2O')
      f_selfshielding = chem_params%f_selfshielding_H2O
    case ('OH')
      f_selfshielding = chem_params%f_selfshielding_OH
    case ('CO')
      f_selfshielding = chem_params%f_selfshielding_CO
    case default
      f_selfshielding = 1D0
  end select
end function f_selfshielding


subroutine chem_prepare_solver_storage
  integer i, j, k
  chem_solver_params%LRW = &
    20 + 4 * chem_solver_params%NNZ + 28 * chem_solver_params%NEQ
    !20 + chem_solver_params%NEQ * (12 + 1) &
    !+ 3 * chem_solver_params%NEQ + 4 * chem_solver_params%NNZ &
    !+ 2 * chem_solver_params%NEQ + chem_solver_params%NNZ &
    !+ 10 * chem_solver_params%NEQ
  chem_solver_params%LIW = 31 + chem_solver_params%NEQ + chem_solver_params%NNZ
  allocate( &
    chem_solver_storage%RWORK(chem_solver_params%LRW), &
    chem_solver_storage%IWORK(chem_solver_params%LIW))
  chem_solver_storage%RWORK(5:10) = 0D0
  chem_solver_storage%IWORK(5:10) = 0
  chem_solver_storage%IWORK(6) = 2000 ! Maximum number of steps
  chem_solver_storage%IWORK(31) = 1
  k = 1
  do i=1, chem_solver_params%NEQ
    do j=1, chem_solver_params%NEQ
      if (chem_solver_storage%sparseMaskJac(j, i)) then
        chem_solver_storage%IWORK(31 + chem_solver_params%NEQ + k) = j
        k = k + 1
      end if
    end do
    chem_solver_storage%IWORK(31+i) = k
  end do
  deallocate(chem_solver_storage%sparseMaskJac)
end subroutine chem_prepare_solver_storage


subroutine chem_make_sparse_structure
  integer i, j, k
  chem_solver_params%NEQ = chem_species%nSpecies
  allocate(chem_solver_storage%sparseMaskJac(chem_species%nSpecies, &
    chem_species%nSpecies))
  chem_solver_storage%sparseMaskJac = .FALSE.
  do i=1, chem_net%nReactions
    do j=1, chem_net%n_reac(i)
      do k=1, chem_net%n_reac(i)
        chem_solver_storage%sparseMaskJac &
          (chem_net%reac(k, i), chem_net%reac(j, i)) = .TRUE.
      end do
      do k=1, chem_net%n_prod(i)
        chem_solver_storage%sparseMaskJac &
          (chem_net%prod(k, i), chem_net%reac(j, i)) = .TRUE.
      end do
    end do
  end do
  chem_solver_params%NNZ = count(chem_solver_storage%sparseMaskJac)
end subroutine chem_make_sparse_structure


subroutine chem_get_idx_for_special_species
  integer i
  allocate(chem_idx_some_spe%idx(chem_idx_some_spe%nItem))
  do i=1, chem_species%nSpecies
    select case (trim(chem_species%names(i)))
      case ('H2')
        chem_idx_some_spe%i_H2 = i
        chem_idx_some_spe%iiH2 = 1
        chem_idx_some_spe%idx(1) = i
      case ('H')
        chem_idx_some_spe%i_HI = i
        chem_idx_some_spe%iiHI = 2
        chem_idx_some_spe%idx(2) = i
      case ('E-')
        chem_idx_some_spe%i_E = i
        chem_idx_some_spe%iiE = 3
        chem_idx_some_spe%idx(3) = i
      case ('C')
        chem_idx_some_spe%i_CI = i
        chem_idx_some_spe%iiCI = 4
        chem_idx_some_spe%idx(4) = i
      case ('C+')
        chem_idx_some_spe%i_Cplus = i
        chem_idx_some_spe%iiCplus = 5
        chem_idx_some_spe%idx(5) = i
      case ('O')
        chem_idx_some_spe%i_OI = i
        chem_idx_some_spe%iiOI = 6
        chem_idx_some_spe%idx(6) = i
      case ('CO')
        chem_idx_some_spe%i_CO = i
        chem_idx_some_spe%iiCO = 7
        chem_idx_some_spe%idx(7) = i
      case ('H2O')
        chem_idx_some_spe%i_H2O = i
        chem_idx_some_spe%iiH2O = 8
        chem_idx_some_spe%idx(8) = i
      case ('OH')
        chem_idx_some_spe%i_OH = i
        chem_idx_some_spe%iiOH = 9
        chem_idx_some_spe%idx(9) = i
      case ('H+')
        chem_idx_some_spe%i_Hplus = i
        chem_idx_some_spe%iiHplus = 10
        chem_idx_some_spe%idx(10) = i
      case ('gH2')
        chem_idx_some_spe%i_gH2 = i
        chem_idx_some_spe%iigH2 = 11
        chem_idx_some_spe%idx(11) = i
    end select
  end do
end subroutine chem_get_idx_for_special_species


subroutine chem_get_dupli_reactions
  ! Find out the duplicated reactions.
  ! Among all the reaction belonging to a single "duplicated set",
  ! one and only one will be used.
  ! For each reaction, this subroutine finds out all the reactions with smaller
  ! indices and the same reactants, products, and reaction types.
  integer i, j, i1
  integer, dimension(const_n_dupli_max_guess) :: indices
  do i=1, chem_net%nReactions
    chem_net%dupli(i)%nItem = 0
    i1 = 0
    do j=1, i-1
      if ((chem_net%ctype(i) .EQ. chem_net%ctype(j)) .AND. &
          (chem_net%itype(i) .EQ. chem_net%itype(j)) .AND. &
          (sum(abs(chem_net%reac(:, j)-chem_net%reac(:, i))) .EQ. 0) .AND. &
          (sum(abs(chem_net%prod(:, j)-chem_net%prod(:, i))) .EQ. 0)) then
        i1 = i1 + 1
        indices(i1) = j
      end if
    end do
    if (i1 .GT. 0) then
      chem_net%dupli(i)%nItem = i1
      allocate(chem_net%dupli(i)%list(i1))
      chem_net%dupli(i)%list = indices(1:i1) 
    end if
  end do
end subroutine chem_get_dupli_reactions


subroutine chem_parse_reactions
  integer i, j, k, n_tmp
  logical flag
  character(len=const_len_species_name), &
    dimension(const_nSpecies_guess) :: names_tmp
  chem_net%reac = 0
  chem_net%prod = 0
  names_tmp(1) = chem_net%reac_names(1, 1)
  n_tmp = 1
  do i=1, chem_net%nReactions
    do k=1, chem_net%n_reac(i)
      flag = .TRUE.
      do j=1, n_tmp
        if (trim(names_tmp(j)) .EQ. trim(chem_net%reac_names(k, i))) then
          flag = .FALSE.
          chem_net%reac(k, i) = j
          exit
        end if
      end do
      if (flag) then
        n_tmp = n_tmp + 1
        names_tmp(n_tmp) = chem_net%reac_names(k, i)
        chem_net%reac(k, i) = n_tmp
      end if
    end do
    do k=1, chem_net%n_prod(i)
      flag = .TRUE.
      do j=1, n_tmp
        if (trim(names_tmp(j)) .EQ. trim(chem_net%prod_names(k, i))) then
          flag = .FALSE.
          chem_net%prod(k, i) = j
          exit
        end if
      end do
      if (flag) then
        n_tmp = n_tmp + 1
        names_tmp(n_tmp) = chem_net%prod_names(k, i)
        chem_net%prod(k, i) = n_tmp
      end if
    end do
  end do
  chem_species%nSpecies = n_tmp
  allocate( &
        chem_species%names(n_tmp), &
        chem_species%mass_num(n_tmp), &
        chem_species%vib_freq(n_tmp), &
        chem_species%Edesorb(n_tmp), &
        chem_species%adsorb_coeff(n_tmp), &
        chem_species%desorb_coeff(n_tmp), &
        chem_species%elements(const_nElement, n_tmp))
  chem_species%names = names_tmp(1:n_tmp)
  do i=1, chem_species%nSpecies
    call getElements(chem_species%names(i), const_nameElements, &
                     const_nElement, chem_species%elements(:, i))
    chem_species%mass_num(i) = sum(dble(chem_species%elements(:, i)) * &
                                   const_ElementMassNumber)
  end do
  do i=1, chem_net%nReactions
    if (chem_net%itype(i) .eq. 62) then
      chem_species%vib_freq(chem_net%reac(1, i)) = &
        getVibFreq(chem_species%mass_num(chem_net%reac(1, i)), &
                   chem_net%ABC(3, i))
      chem_species%Edesorb(chem_net%reac(1, i)) = chem_net%ABC(3, i)
    end if
  end do
end subroutine chem_parse_reactions


subroutine chem_load_reactions
  integer i, j, k, ios
  chem_net%nReactions = chem_reac_str%nReactions
  allocate(chem_net%reac_names(const_n_reac_max, chem_net%nReactions), &
           chem_net%prod_names(const_n_prod_max, chem_net%nReactions), &
           chem_net%reac(const_n_reac_max, chem_net%nReactions), &
           chem_net%prod(const_n_prod_max, chem_net%nReactions), &
           chem_net%n_reac(chem_net%nReactions), &
           chem_net%n_prod(chem_net%nReactions), &
           chem_net%ABC(3, chem_net%nReactions), &
           chem_net%T_range(2, chem_net%nReactions), &
           chem_net%itype(chem_net%nReactions), &
           chem_net%ctype(chem_net%nReactions), &
           chem_net%quality(chem_net%nReactions), &
           chem_net%rates(chem_net%nReactions), &
           chem_net%dupli(chem_net%nReactions))
  chem_net%reac_names = ' '
  chem_net%prod_names = ' '
  chem_net%n_reac = 0
  chem_net%n_prod = 0
  do i=1, chem_net%nReactions
    read(chem_reac_str%list(i), FMT = &
      '(7(A12), 3F9.0, 2F6.0, I3, X, A1, X, A2)', IOSTAT=ios) &
      chem_net%reac_names(:,i), &
      chem_net%prod_names(:,i), &
      chem_net%ABC(:,i), &
      chem_net%T_range(:,i), &
      chem_net%itype(i), &
      chem_net%quality(i), &
      chem_net%ctype(i)
    do j=1, const_n_reac_max
      do k=1, const_len_species_name
        if (chem_net%reac_names(j, i)(k:k) .NE. ' ') then
          chem_net%n_reac(i) = chem_net%n_reac(i) + 1
          exit
        end if
      end do
      if (trim(chem_net%reac_names(j, i)) .EQ. 'PHOTON') then
        chem_net%n_reac(i) = chem_net%n_reac(i) - 1
      end if
      if (trim(chem_net%reac_names(j, i)) .EQ. 'CRPHOT') then
        chem_net%n_reac(i) = chem_net%n_reac(i) - 1
      end if
      if (trim(chem_net%reac_names(j, i)) .EQ. 'CRP') then
        chem_net%n_reac(i) = chem_net%n_reac(i) - 1
      end if
    end do
    do j=1, const_n_prod_max
      do k=1, const_len_species_name
        if (chem_net%prod_names(j, i)(k:k) .NE. ' ') then
          chem_net%n_prod(i) = chem_net%n_prod(i) + 1
          exit
        end if
      end do
      if (trim(chem_net%prod_names(j, i)) .EQ. 'PHOTON') then
        chem_net%n_prod(i) = chem_net%n_prod(i) - 1
      end if
    end do
  end do
end subroutine chem_load_reactions


subroutine chem_read_reactions()
  integer fU, i, ios
  chem_reac_str%nReactions = &
    GetFileLen_comment_blank(combine_dir_filename(chem_solver_params%chem_files_dir, &
                             chem_solver_params%filename_chemical_network), &
    chem_reac_str%commentChar)
  if (.NOT. getFileUnit (fU)) then
    write(*,'(/A/)') 'Cannot get a file unit!  In chem_read_reactions.'
    stop
  end if
  call openFileSequentialRead(fU, combine_dir_filename(chem_solver_params%chem_files_dir, &
                                  chem_solver_params%filename_chemical_network), 999)
  allocate(chem_reac_str%list(chem_reac_str%nReactions))
  i = 1
  do
    read(fU, FMT='(A)', IOSTAT=ios) chem_reac_str%list(i)
    if (ios .NE. 0) then
      exit
    end if
    if (.NOT. &
        ( &
         (chem_reac_str%list(i)(1:1) .EQ. chem_reac_str%commentChar) .OR. &
         (chem_reac_str%list(i)(1:1) .EQ. ' ') &
        )) then
      i = i + 1
    end if
    if (i .GT. chem_reac_str%nReactions) then
      exit
    end if
  end do
  close(fU)
end subroutine chem_read_reactions


! Get the elemental composition of each molecule.
subroutine getElements &
  (nameSpec, listElements, nElements, arrNElements)
character(len=*) nameSpec, listElements(nElements)
integer, dimension(nElements) :: arrNElements
integer i, j, k, ntmp, lenName, lenEle, nElements
integer, dimension(32) :: belongto
logical, dimension(32) :: used
logical flagReplace
integer, parameter :: chargePos = 1
arrNElements = 0
lenName = len(trim(nameSpec))
belongto = 0
used = .FALSE.
do i=1, nElements
  lenEle = len(trim(listElements(i)))
  do j=1, lenName-lenEle+1
    if (nameSpec(j:(j+lenEle-1)) .EQ. &
        listElements(i)(1:(lenEle))) then
      flagReplace = .TRUE.
      do k=j, (j+lenEle-1)
        if (used(k)) then
          if (len(trim(listElements(belongto(k)))) .GE. &
              len(trim(listElements(i)))) then
            flagReplace = .FALSE.
            exit
          else
            arrNElements(belongto(k)) = &
              arrNElements(belongto(k)) - 1
          end if
        end if
      end do
      if (flagReplace) then
        belongto(j:(j+lenEle-1)) = i
        used(j:(j+lenEle-1)) = .TRUE.
        arrNElements(i) = arrNElements(i) + 1
      end if
    end if
  end do
end do
!
do i=2, lenName
  if (.NOT. used(i)) then
    do j=1, (i-1)
      if (used(i-j)) then
        belongto(i) = belongto(i-j)
        exit
      end if
    end do
    if (((nameSpec(i-1:i-1) .GT. '9') .OR. &
      (nameSpec(i-1:i-1) .LT. '0')) .AND. &
      (nameSpec(i:i) .LE. '9') .AND. &
      (nameSpec(i:i) .GE. '0')) then
      if ((nameSpec(i+1:i+1) .LE. '9') .AND. &
        (nameSpec(i+1:i+1) .GE. '0')) then
        read (nameSpec(i:i+1), '(I2)') ntmp
        if (ntmp .EQ. 0) cycle
        arrNElements(belongto(i)) = &
          arrNElements(belongto(i)) + ntmp - 1
      else
        read (nameSpec(i:i), '(I1)') ntmp
        if (ntmp .EQ. 0) cycle
        arrNElements(belongto(i)) = &
          arrNElements(belongto(i)) + ntmp - 1
      end if
    else if (nameSpec(i:i) .EQ. '+') then
      arrNElements(chargePos) = 1
    else if (nameSpec(i:i) .EQ. '-') then
      arrNElements(chargePos) = -1
    end if
  end if
end do
end subroutine getElements


function getVibFreq(massnum, Edesorb)
double precision getVibFreq
double precision, intent(in) :: massnum, Edesorb
getVibFreq = &
   sqrt(2D0 * SitesDensity_CGS * &
      phy_kBoltzmann_CGS * Edesorb / (phy_Pi**2) / &
      (phy_mProton_CGS * massnum))
end function getVibFreq


function getMobility(vibfreq, massnum, Edesorb, Tdust)
  double precision getMobility
  double precision, intent(in) :: vibfreq, massnum, Edesorb, Tdust
  double precision, parameter :: Diff2DesorRatio = 0.5D0
  double precision, parameter :: DiffBarrierWidth_CGS = 1D-8
  getMobility = vibfreq * exp(max( &
              -Edesorb * Diff2DesorRatio / Tdust, &
              -2D0 * DiffBarrierWidth_CGS / phy_hbarPlanck_CGS * &
                sqrt(2D0 * massnum * phy_mProton_CGS &
                  * phy_kBoltzmann_CGS * Edesorb * Diff2DesorRatio)))
end function getMobility


end module chemistry



subroutine chem_ode_f(NEQ, t, y, ydot)
  use chemistry
  integer NEQ, i, j
  double precision t, y(NEQ), ydot(NEQ), rtmp
  ydot = 0D0
  do i=1, chem_net%nReactions
    rtmp = 0D0
    if (chem_net%n_reac(i) .EQ. 1) then
      rtmp = chem_net%rates(i) * y(chem_net%reac(1, i))
    else if (chem_net%n_reac(i) .EQ. 2) then
      if (.not. ((chem_net%itype(i) .eq. 0) .or. (chem_net%itype(i) .eq. 63))) then
        rtmp = chem_net%rates(i) * y(chem_net%reac(1, i)) * y(chem_net%reac(2, i))
      else
        rtmp = chem_net%rates(i) * y(chem_net%reac(1, i))
      end if
    end if
    if (rtmp .NE. 0D0) then
      do j=1, chem_net%n_reac(i)
        ydot(chem_net%reac(j, i)) = ydot(chem_net%reac(j, i)) - rtmp
      end do
      do j=1, chem_net%n_prod(i)
        ydot(chem_net%prod(j, i)) = ydot(chem_net%prod(j, i)) + rtmp
      end do
    end if
  end do
end subroutine chem_ode_f


subroutine chem_ode_jac(NEQ, t, y, j, ian, jan, pdj)
  use chemistry
  double precision t, rtmp
  double precision, dimension(NEQ) :: y, pdj
  double precision, dimension(:) :: ian, jan
  integer NEQ, i, j, k
  do i=1, chem_net%nReactions
    if ((j .EQ. chem_net%reac(1, i)) .OR. &
        (j .EQ. chem_net%reac(2, i))) then
      rtmp = 0D0
      if (chem_net%n_reac(i) .EQ. 1) then
        rtmp = chem_net%rates(i)
      else if (chem_net%n_reac(i) .EQ. 2) then
        if (.not. ((chem_net%itype(i) .eq. 0) .or. (chem_net%itype(i) .eq. 63))) then
          if (j .EQ. chem_net%reac(1, i)) then
            rtmp = chem_net%rates(i) * y(chem_net%reac(2, i))
          else if (j .EQ. chem_net%reac(2, i)) then
            rtmp = chem_net%rates(i) * y(chem_net%reac(1, i))
          end if
        else
          rtmp = chem_net%rates(i)
        end if
      end if
      if (rtmp .NE. 0D0) then
        do k=1, chem_net%n_reac(i)
          pdj(chem_net%reac(k, i)) = pdj(chem_net%reac(k, i)) - rtmp
        end do
        if (chem_net%reac(1, i) .eq. chem_net%reac(2, i)) then
          rtmp = rtmp * 2D0
        end if
        do k=1, chem_net%n_prod(i)
          pdj(chem_net%prod(k, i)) = pdj(chem_net%prod(k, i)) + rtmp
        end do
      end if
    end if
  end do
end subroutine chem_ode_jac


! <timestamp>2013-07-30 Tue 10:44:44</timestamp> 
! Todo
!subroutine chem_ode_f_vodpk(NEQ, t, y, ydot, rpar, ipar)
!  use chemistry
!  integer NEQ, i, j
!  double precision, dimension(:) :: rpar
!  integer, dimension(:) :: ipar
!  double precision t, y(NEQ), ydot(NEQ), rtmp
!  ydot = 0D0
!  do i=1, chem_net%nReactions
!    rtmp = 0D0
!    if (chem_net%n_reac(i) .EQ. 1) then
!      rtmp = chem_net%rates(i) * y(chem_net%reac(1, i))
!    else if (chem_net%n_reac(i) .EQ. 2) then
!      if (chem_net%itype(i) .NE. 0) then
!        rtmp = chem_net%rates(i) * y(chem_net%reac(1, i)) * y(chem_net%reac(2, i))
!      else
!        rtmp = chem_net%rates(i) * y(chem_net%reac(2, i))
!      end if
!    end if
!    if (rtmp .NE. 0D0) then
!      do j=1, chem_net%n_reac(i)
!        ydot(chem_net%reac(j, i)) = ydot(chem_net%reac(j, i)) - rtmp
!      end do
!      do j=1, chem_net%n_prod(i)
!        ydot(chem_net%prod(j, i)) = ydot(chem_net%prod(j, i)) + rtmp
!      end do
!    end if
!  end do
!end subroutine chem_ode_f_vodpk
!
!
!subroutine chem_ode_jac_vodpk(f, NEQ, t, y, ysv, rewt, fty, v, hrl1, wp, iwp, ier, rpar, ipar)
!  use chemistry
!  external f
!  double precision t, rtmp, hrl1
!  double precision, dimension(NEQ) :: y, ysv, rewt, fty, v
!  double precision, dimension(:) :: rpar, wp
!  integer, dimension(:) :: iwp, ipar
!  integer NEQ, i, j, k
!  wp = 0D0
!  do i=1, chem_net%nReactions
!    if (chem_net%n_reac(i) .eq. 1) then
!      wp(chem_net%n_reac(i)) = wp(chem_net%n_reac(i)) - chem_net%rates(i)
!    else if (chem_net%%n_reac(i) .eq. 2) then
!    else
!    end if
!  end do
!end subroutine chem_ode_jac_vodpk
!
!
!subroutine chem_ode_psol_vodpk(NEQ, t, y, fty, wk, hrl1, wp, iwp, b, lr, ier, rpar, ipar)
!  integer NEQ, ier, lr
!  double precision t, hrl1
!  double precision, dimension(NEQ) :: y, fty, wk, b
!  double precision, dimension(:) :: wp, rpar
!  integer, dimension(:) :: iwp, ipar
!  integer i
!  do i=1, NEQ
!    b(i) = b(i) / (1D0 - hrl1 * wp(i))
!  end do
!  ier = 0
!end subroutine chem_ode_psol_vodpk
