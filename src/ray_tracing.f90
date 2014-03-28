module ray_tracing


use data_struct
use grid
use chemistry
use heating_cooling
use montecarlo
use load_Draine_dusts


type :: type_mole_exc_conf
  character(len=128) :: dirname_mol_data=''
  character(len=128) :: fname_mol_data=''
  character(len=128) :: dir_save_image=''
  integer nfreq_window
  double precision, dimension(10) :: freq_mins, freq_maxs
  double precision abundance_factor
  double precision :: E_min = 50D0, E_max = 5D3
  double precision :: VeloHalfWidth
  logical :: useLTE = .true.
  !
  integer nf, nth, nx, ny
  double precision dist
  !
end type type_mole_exc_conf


type :: type_molecule_exc
  type(type_mole_exc_conf) :: conf
  type(type_molecule_energy_set), pointer :: p => null()
  integer nlevel_keep, ntran_keep
  integer, dimension(:), allocatable :: ilv_keep, ilv_reverse
  integer, dimension(:), allocatable :: itr_keep, itr_reverse
end type type_molecule_exc


type :: type_fits_par
  character(len=256) :: filename
  integer stat, fU, blocksize, bitpix, naxis
  integer, dimension(3) :: naxes
  integer i, j, group, fpixel, nelements, decimals
  integer pcount, gcount
  logical simple, extend
  character(len=32) :: extname
  character(len=32) :: author, user
end type type_fits_par

type :: type_image
  integer nx, ny
  double precision xmin, xmax, dx, ymin, ymax, dy
  double precision view_theta
  double precision freq_min, freq_max
  double precision total_flux
  integer iTran
  type(type_rad_transition) rapar
  double precision, dimension(:,:), allocatable :: val
end type type_image


type :: type_cube_header
  integer iTran
  integer nx, ny, nz
  double precision dx, dy, dz
  double precision f0
  double precision theta
  double precision Eup, Elow
  double precision Aul, Bul, Blu
  double precision total_flux_max
end type type_cube_header


type :: type_cube
  type(type_cube_header) :: h
  double precision, dimension(:,:,:), allocatable :: val
end type type_cube


type(type_mole_exc_conf) :: mole_line_conf

type(type_molecule_exc) :: mole_exc


contains


subroutine make_cubes
  use my_timer
  integer ntr, itr
  integer i, j, k, i1, j1
  !integer, parameter :: nf = 100, nth = 4
  !integer, parameter :: nx = 201, ny = 201
  !double precision, parameter :: dist = 50D0 ! pc
  integer nf, nth
  integer nx, ny
  double precision dist
  !
  double precision :: xmin, xmax, ymin, ymax
  double precision VeloHalfWidth
  double precision delf, df, f0, fmin, dtheta
  double precision dv, vmax
  character(len=128) im_dir, fname
  type(type_image) :: image
  type(type_cube) :: cube
  double precision, dimension(:,:), allocatable :: &
    arr_tau, arr_tau1, Ncol_up, Ncol_low
  double precision, dimension(:), allocatable :: vec_flux
  !
  type(type_fits_par) :: fp
  type(date_time) a_date_time
  !
  nf  = mole_exc%conf%nf
  nth = mole_exc%conf%nth
  nx  = mole_exc%conf%nx
  ny  = mole_exc%conf%ny
  dist = mole_exc%conf%dist
  !
  xmax = max(root%xmax, root%ymax)
  xmin = -xmax
  ymin = -xmax
  ymax = xmax
  !
  VeloHalfWidth = mole_line_conf%VeloHalfWidth
  !VeloHalfWidth = 1.3D0 * sqrt( &
  !  phy_GravitationConst_SI * a_disk%star_mass_in_Msun * phy_Msun_SI / &
  !    (root%xmin * phy_AU2m) + &
  !  phy_kBoltzmann_SI * 2D3 / (phy_mProton_SI * 2.8D0) * 3D0)
  !
  fp%stat = 0
  fp%blocksize = 1
  fp%pcount = 0
  fp%gcount = 1
  fp%group=1
  fp%fpixel=1
  fp%decimals = 16
  fp%author = 'Fujun Du (fdu@umich.edu)'
  fp%user = ''
  fp%simple=.true.
  fp%extend=.true.
  fp%bitpix=-64 ! double
  !
  !im_dir = trim(combine_dir_filename(a_disk_iter_params%iter_files_dir, 'images/'))
  im_dir = trim(combine_dir_filename(mole_line_conf%dir_save_image, 'images/'))
  if (.not. dir_exist(im_dir)) then
    call my_mkdir(im_dir)
  end if
  !
  dtheta = 90D0 / dble(nth-1)
  !
  ntr = mole_exc%ntran_keep
  !
  image%nx = nx
  image%ny = ny
  image%xmin = xmin
  image%xmax = xmax
  image%ymin = ymin
  image%ymax = ymax
  image%dx = (xmax - xmin) / dble(nx-1)
  image%dy = (ymax - ymin) / dble(ny-1)
  !
  allocate(cube%val(nx, ny, nf), &
           image%val(nx, ny), &
           arr_tau(nx, ny), &
           arr_tau1(nx, ny), &
           Ncol_up(nx, ny), &
           Ncol_low(nx, ny), &
           vec_flux(nf))
  !
  do i=1, ntr ! Transitions
    itr = mole_exc%itr_keep(i)
    image%iTran = itr
    f0 = a_mol_using%rad_data%list(itr)%freq
    delf = f0 * VeloHalfWidth / phy_SpeedOfLight_SI
    fmin = f0 - delf
    df = delf * 2D0 / dble(nf)
    image%rapar = a_mol_using%rad_data%list(itr)
    !
    do k=1, nth ! Viewing angles
      image%view_theta = dtheta * dble(k-1)
      !
      arr_tau = 0D0
      do j=1, nf ! Frequency channels
        !
        image%freq_min = fmin + dble(j-1) * df 
        image%freq_max = fmin + dble(j)   * df 
        !
        write(*, '(3I4, " / ", 3I4)') i, j, k, ntr, nf, nth
        !
        call make_a_channel_image(image, arr_tau1, Ncol_up, Ncol_low, nx, ny)
        !
        do j1=1, ny
        do i1=1, nx
          arr_tau(i1, j1) = max(arr_tau1(i1, j1), arr_tau(i1, j1))
        end do
        end do
        !
        cube%val(:, :, j) = image%val
        !
        image%total_flux = sum(image%val) * &
                           (image%dx * image%dy * phy_AU2cm**2 / &
                            (dist * phy_pc2cm)**2) / &
                           phy_jansky2CGS
        vec_flux(j) = image%total_flux
        !
      end do
      !
      write(fname, '(3(I0.5,"_"), ES14.5, "_", F09.2, ".fits")') i, itr, k, &
        f0, image%view_theta
      call dropout_char(fname, ' ')
      !
      fp%filename = trim(combine_dir_filename(im_dir, fname))
      !
      call ftgiou(fp%fU, fp%stat)
      call ftinit(fp%fU, fp%filename, fp%blocksize, fp%stat)
      !
      fp%naxis=3
      fp%naxes(1)=nx
      fp%naxes(2)=ny
      fp%naxes(3)=nf
      fp%nelements = nx * ny * nf
      call ftphpr(fp%fU, fp%simple, fp%bitpix, fp%naxis, fp%naxes, &
                  fp%pcount, fp%gcount, fp%extend, fp%stat)
      !
      call ftpprd(fp%fU, fp%group, fp%fpixel, fp%nelements, cube%val, fp%stat)
      !
      call ftpkyd(fp%fU, 'CDELT1', image%dx,  fp%decimals, 'dx (AU)', fp%stat)
      call ftpkyd(fp%fU, 'CDELT2', image%dy,  fp%decimals, 'dy (AU)', fp%stat)
      call ftpkyd(fp%fU, 'CDELT3', df      ,  fp%decimals, 'df (Hz)', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX1', 1.0D0,    fp%decimals, 'i0', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX2', 1.0D0,    fp%decimals, 'j0', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX3', 1.0D0,    fp%decimals, 'k0', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL1', xmin,   fp%decimals, 'xmin', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL2', ymin,   fp%decimals, 'ymin', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL3', fmin + 0.5D0 * df,   fp%decimals, 'fmin', fp%stat)
      call ftpkys(fp%fU, 'CTYPE1', 'X', 'AU', fp%stat)
      call ftpkys(fp%fU, 'CTYPE2', 'Y', 'AU', fp%stat)
      call ftpkys(fp%fU, 'CTYPE3', 'F', 'Hz', fp%stat)
      !
      call ftpkyd(fp%fU, 'Dist',  mole_exc%conf%dist, fp%decimals, 'pc', fp%stat)
      call ftpkyd(fp%fU, 'Theta', image%view_theta, fp%decimals, 'deg', fp%stat)
      call ftpkyj(fp%fU, 'Itr',   itr   ,  'trans num', fp%stat)
      call ftpkyd(fp%fU, 'F0',    f0/1D9,  fp%decimals, 'GHz', fp%stat)
      call ftpkyd(fp%fU, 'lam0',  image%rapar%lambda, fp%decimals, 'micron', fp%stat)
      call ftpkyd(fp%fU, 'Eup',   image%rapar%Eup,  fp%decimals, 'K', fp%stat)
      call ftpkyd(fp%fU, 'Elow',  image%rapar%Elow,  fp%decimals, 'K', fp%stat)
      call ftpkyj(fp%fU, 'iup',   image%rapar%iup,  '', fp%stat)
      call ftpkyj(fp%fU, 'ilow',  image%rapar%ilow, '', fp%stat)
      call ftpkyd(fp%fU, 'Aul',   image%rapar%Aul,  fp%decimals, 's-1', fp%stat)
      call ftpkyd(fp%fU, 'Bul',   image%rapar%Bul,  fp%decimals, '', fp%stat)
      call ftpkyd(fp%fU, 'Blu',   image%rapar%Blu,  fp%decimals, '', fp%stat)
      call ftpkyd(fp%fU, 'MaxFlux', maxval(vec_flux),  fp%decimals, 'jy', fp%stat)
      call ftpkyd(fp%fU, 'MaxTau',  maxval(arr_tau),   fp%decimals, '', fp%stat)
      !
      call ftpkys(fp%fU, 'Author', fp%author, '', fp%stat)
      call ftpkys(fp%fU, 'User',   fp%user,   '', fp%stat)
      call ftpkys(fp%fU, 'SavedAt', trim(a_date_time%date_time_str()), '', fp%stat)
      !
      ! First extension: tau map
      call ftcrhd(fp%fU, fp%stat)
      fp%naxis = 2
      fp%naxes(1) = nx
      fp%naxes(2) = ny
      call ftiimg(fp%fU, fp%bitpix, fp%naxis, fp%naxes(1:2), fp%stat)
      !
      call ftpprd(fp%fU, fp%group, fp%fpixel, nx*ny, arr_tau, fp%stat)
      !
      call ftpkyd(fp%fU, 'CDELT1', image%dx,  fp%decimals, 'dx', fp%stat)
      call ftpkyd(fp%fU, 'CDELT2', image%dy,  fp%decimals, 'dy', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX1', 1.0D0,    fp%decimals, 'i0', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX2', 1.0D0,    fp%decimals, 'j0', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL1', xmin,   fp%decimals, 'xmin', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL2', ymin,   fp%decimals, 'ymin', fp%stat)
      call ftpkys(fp%fU, 'CTYPE1', 'X', 'AU', fp%stat)
      call ftpkys(fp%fU, 'CTYPE2', 'Y', 'AU', fp%stat)
      call ftpkys(fp%fU, 'ExtName', 'TauMap', 'peak values', fp%stat)
      !
      ! Second extension: integrated map
      call ftcrhd(fp%fU, fp%stat)
      fp%naxis = 2
      fp%naxes(1) = nx
      fp%naxes(2) = ny
      call ftiimg(fp%fU, fp%bitpix, fp%naxis, fp%naxes(1:2), fp%stat)
      !
      call ftpprd(fp%fU, fp%group, fp%fpixel, nx*ny, sum(cube%val, 3) * df, fp%stat)
      !
      call ftpkyd(fp%fU, 'CDELT1', image%dx,  fp%decimals, 'dx', fp%stat)
      call ftpkyd(fp%fU, 'CDELT2', image%dy,  fp%decimals, 'dy', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX1', 1.0D0,    fp%decimals, 'i0', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX2', 1.0D0,    fp%decimals, 'j0', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL1', xmin,   fp%decimals, 'xmin', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL2', ymin,   fp%decimals, 'ymin', fp%stat)
      call ftpkys(fp%fU, 'CTYPE1', 'X', 'AU', fp%stat)
      call ftpkys(fp%fU, 'CTYPE2', 'Y', 'AU', fp%stat)
      call ftpkys(fp%fU, 'ExtName', 'IntMap', 'Int(I, nu)', fp%stat)
      !
      ! Third extension: upper column density
      call ftcrhd(fp%fU, fp%stat)
      fp%naxis = 2
      fp%naxes(1) = nx
      fp%naxes(2) = ny
      call ftiimg(fp%fU, fp%bitpix, fp%naxis, fp%naxes(1:2), fp%stat)
      !
      call ftpprd(fp%fU, fp%group, fp%fpixel, nx*ny, Ncol_up, fp%stat)
      !
      call ftpkyd(fp%fU, 'CDELT1', image%dx,  fp%decimals, 'dx', fp%stat)
      call ftpkyd(fp%fU, 'CDELT2', image%dy,  fp%decimals, 'dy', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX1', 1.0D0,    fp%decimals, 'i0', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX2', 1.0D0,    fp%decimals, 'j0', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL1', xmin,   fp%decimals, 'xmin', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL2', ymin,   fp%decimals, 'ymin', fp%stat)
      call ftpkys(fp%fU, 'CTYPE1', 'X', 'AU', fp%stat)
      call ftpkys(fp%fU, 'CTYPE2', 'Y', 'AU', fp%stat)
      call ftpkys(fp%fU, 'ExtName', 'ColumnDensityUp', 'cm-2', fp%stat)
      !
      ! Fourth extension: lower column density
      call ftcrhd(fp%fU, fp%stat)
      fp%naxis = 2
      fp%naxes(1) = nx
      fp%naxes(2) = ny
      call ftiimg(fp%fU, fp%bitpix, fp%naxis, fp%naxes(1:2), fp%stat)
      !
      call ftpprd(fp%fU, fp%group, fp%fpixel, nx*ny, Ncol_low, fp%stat)
      !
      call ftpkyd(fp%fU, 'CDELT1', image%dx,  fp%decimals, 'dx', fp%stat)
      call ftpkyd(fp%fU, 'CDELT2', image%dy,  fp%decimals, 'dy', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX1', 1.0D0,    fp%decimals, 'i0', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX2', 1.0D0,    fp%decimals, 'j0', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL1', xmin,   fp%decimals, 'xmin', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL2', ymin,   fp%decimals, 'ymin', fp%stat)
      call ftpkys(fp%fU, 'CTYPE1', 'X', 'AU', fp%stat)
      call ftpkys(fp%fU, 'CTYPE2', 'Y', 'AU', fp%stat)
      call ftpkys(fp%fU, 'ExtName', 'ColumnDensityLow', 'cm-2', fp%stat)
      !
      ! Fifth extension: spectrum integrated over the whole region
      call ftcrhd(fp%fU, fp%stat)
      fp%naxis = 2
      fp%naxes(1) = nf
      fp%naxes(2) = 1
      call ftiimg(fp%fU, fp%bitpix, fp%naxis, fp%naxes(1:2), fp%stat)
      !
      call ftpprd(fp%fU, fp%group, fp%fpixel, nf, vec_flux, fp%stat)
      !
      dv = -df / f0 * phy_SpeedOfLight_SI / 1D3
      vmax = (1D0 - (fmin + 0.5D0 * df)/f0) * phy_SpeedOfLight_SI / 1D3
      call ftpkyd(fp%fU, 'CDELT1', dv   ,  fp%decimals, 'dv', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX1', 1.0D0,  fp%decimals, 'k0', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL1', vmax, fp%decimals, 'vmax', fp%stat)
      call ftpkys(fp%fU, 'CTYPE1', 'V', 'km s-1', fp%stat)
      call ftpkyd(fp%fU, 'CDELT2', 0D0   ,  fp%decimals, 'dumb', fp%stat)
      call ftpkyd(fp%fU, 'CRPIX2', 0.0D0,  fp%decimals, 'dumb', fp%stat)
      call ftpkyd(fp%fU, 'CRVAL2', 0D0, fp%decimals, 'dumb', fp%stat)
      call ftpkys(fp%fU, 'CTYPE2', 'dumb', 'To make ds9 work.', fp%stat)
      call ftpkys(fp%fU, 'ExtName', 'FluxSpec', 'jy', fp%stat)
      !
      call ftclos(fp%fU, fp%stat)
      call ftfiou(fp%fU, fp%stat)
    end do
  end do
end subroutine make_cubes



subroutine make_a_channel_image(im, arr_tau, Ncol_up, Ncol_low, nx, ny)
  integer, intent(in) :: nx, ny
  type(type_image), intent(inout) :: im
  double precision, dimension(nx, ny), intent(out) :: arr_tau, Ncol_up, Ncol_low
  integer i, j, k, i1, j1
  integer xy_sub_div
  integer f_sub_div
  double precision dx, dy, df
  double precision x, y, z, f
  double precision x_ll, y_ll, x_rr, y_rr
  double precision costheta, sintheta
  double precision nave
  double precision tau
  double precision I_0
  double precision Nup, Nlow, Ncol, tau_tot
  type(type_photon_packet) ph
  double precision :: min_tau = 1D-8
  !
  z = -max(root%xmax, root%ymax, &
           abs(im%xmax), abs(im%xmin), &
           abs(im%ymax), abs(im%ymin)) * 5D0
  !
  costheta = cos(im%view_theta / 180D0 * phy_Pi)
  sintheta = sin(im%view_theta / 180D0 * phy_Pi)
  !
  if (.not. allocated(im%val)) then
    allocate(im%val(im%nx, im%ny))
  end if
  !
  a_mol_using => mole_exc%p
  !
  write(*,*)
  do j=1, im%ny
    y_ll = im%ymin + (dble(j-1) - 0.5D0) * im%dy
    y_rr = im%ymin + (dble(j-1) + 0.5D0) * im%dy
    do i=1, im%nx
      x_ll = im%xmin + (dble(i-1) - 0.5D0) * im%dx
      x_rr = im%xmin + (dble(i-1) + 0.5D0) * im%dx
      !
      im%val(i, j)   = 0D0
      arr_tau(i, j)  = 0D0
      Ncol_up(i, j)  = 0D0
      Ncol_low(i, j) = 0D0
      !
      Ncol = max( &
        colden_along_a_direction(x_ll, y_ll, z, &
            costheta, sintheta, a_mol_using%iSpe), &
        colden_along_a_direction(x_ll, y_rr, z, &
            costheta, sintheta, a_mol_using%iSpe), &
        colden_along_a_direction(x_rr, y_ll, z, &
            costheta, sintheta, a_mol_using%iSpe), &
        colden_along_a_direction(x_rr, y_rr, z, &
            costheta, sintheta, a_mol_using%iSpe)) &
        * a_mol_using%abundance_factor
      !
      tau_tot = phy_hPlanck_CGS * im%freq_min / (4D0*phy_Pi) * &
           Ncol / (phy_sqrt2Pi * im%freq_min * a_mol_using%dv &
                   / phy_SpeedOfLight_CGS) &
           * a_mol_using%rad_data%list(im%iTran)%Blu
      if (tau_tot .gt. min_tau) then
        xy_sub_div = 3 + int(10e0/(x_ll*x_ll + y_ll*y_ll + 1.0))
        f_sub_div  = 3 + int(10e0/(x_ll*x_ll + y_ll*y_ll + 1.0))
        nave = dble(f_sub_div * xy_sub_div * xy_sub_div)
      else
        xy_sub_div = 3
        f_sub_div  = 2
        nave = dble(f_sub_div * xy_sub_div * xy_sub_div)
      end if
      !
      dx = im%dx / dble(xy_sub_div-1)
      dy = im%dy / dble(xy_sub_div-1)
      df = (im%freq_max - im%freq_min) / dble(f_sub_div - 1)
      !
      write(*, '(A, 10X, 2I6, " / (", 2I6, ")")') &
        CHAR(27)//'[A', i, j, im%nx, im%ny
      !
      do k=1, f_sub_div
        f = im%freq_min + dble(k - 1) * df
        ph%f = f
        !
        I_0 = planck_B_nu(phy_CMB_T, f)
        !
        ph%ray%vx = 0D0
        ph%ray%vy = -sintheta
        ph%ray%vz =  costheta
        !
        ph%lam = phy_SpeedOfLight_CGS / (f * phy_micron2cm)
        ph%iKap = get_idx_for_kappa(ph%lam, dust_0)
        ph%iTran = im%iTran
        !
        y = y_ll
        do j1=1, xy_sub_div
          x = x_ll
          do i1=1, xy_sub_div
            !
            ph%ray%x =  x
            ph%ray%y =  y * costheta - z * sintheta
            ph%ray%z =  y * sintheta + z * costheta
            !
            ph%Inu = I_0
            !
            call integerate_a_ray(ph, tau, Nup, Nlow)
            !
            if (tau .gt. arr_tau(i, j)) then
              arr_tau(i, j) = tau
            end if
            !
            im%val(i, j) = im%val(i, j) + ph%Inu
            Ncol_up(i, j)  = Ncol_up(i, j) + Nup
            Ncol_low(i, j) = Ncol_low(i, j) + Nlow
            !
            x = x + dx
          end do
          y = y + dy
          !
        end do
      end do
      im%val(i, j)   = im%val(i, j) / nave
      Ncol_up(i, j)  = Ncol_up(i, j) / nave
      Ncol_low(i, j) = Ncol_low(i, j) / nave
    end do
  end do
end subroutine make_a_channel_image



subroutine integerate_a_ray(ph, tau, Nup, Nlow)
  ! ph must be guaranteed to be inside c.
  ! An intersection between ph and c must exist, unless there is a
  ! numerical error.
  type(type_photon_packet), intent(inout) :: ph
  double precision, intent(out) :: tau
  double precision, intent(out) :: Nup, Nlow
  type(type_cell), pointer :: c
  type(type_cell), pointer :: cnext
  logical found
  double precision length, r, z, eps
  integer dirtype
  integer itr, ilow, iup, iL, iU
  double precision ylow, yup
  double precision f0, del_nu, line_alpha, line_J
  double precision tau_this
  double precision t1
  !
  double precision cont_alpha, cont_J
  !
  integer i
  !
  tau = 0D0
  Nup = 0D0
  Nlow = 0D0
  !
  call enter_the_domain_mirror(ph, root, c, found)
  if (.not. found) then
    return
  end if
  !
  do i=1, root%nOffspring*2
    ! Get the intersection between the photon ray and the boundary of the cell
    ! that this photon resides in
    call calc_intersection_ray_cell_mirror(ph%ray, c, &
      length, r, z, eps, found, dirtype)
    if (.not. found) then
      write(*,'(A, I6, 10ES10.2/)') 'In integerate_a_ray, ph not cross c: ', &
        i, &
        ph%ray%x, ph%ray%y, ph%ray%z, &
        ph%ray%vx, ph%ray%vy, ph%ray%vz, &
        c%xmin, c%xmax, c%ymin, c%ymax
      return
    end if
    !
    if (c%using) then
      !
      call set_using_mole_params(a_mol_using, c)
      !
      itr = ph%iTran
      ilow = a_mol_using%rad_data%list(itr)%ilow
      iup  = a_mol_using%rad_data%list(itr)%iup
      iL = mole_exc%ilv_reverse(ilow)
      iU = mole_exc%ilv_reverse(iup)
      !
      ylow = c%focc%vals(iL)
      yup  = c%focc%vals(iU)
      del_nu = ph%f * a_mol_using%dv / phy_SpeedOfLight_CGS
      f0 = a_mol_using%rad_data%list(itr)%freq
      !
      Nup  = Nup  + a_mol_using%density_mol * length * phy_AU2cm * yup
      Nlow = Nlow + a_mol_using%density_mol * length * phy_AU2cm * ylow
      !
      ! Rybicki & Lightman, p31
      t1 = phy_hPlanck_CGS * f0 / (4D0*phy_Pi) * &
           a_mol_using%density_mol &
           / (phy_sqrt2Pi * del_nu)
      line_alpha = t1 * &
                   (ylow * a_mol_using%rad_data%list(itr)%Blu - &
                    yup  * a_mol_using%rad_data%list(itr)%Bul)
      line_J     = t1 * yup * &
                   a_mol_using%rad_data%list(itr)%Aul
      !
      if ((ph%iKap .gt. 0) .and. c%using) then
        call make_local_cont_lut(c)
        cont_alpha = cont_lut%alpha(ph%iKap)
        cont_J = cont_lut%J(ph%iKap) * cont_alpha
      else
        cont_alpha = 0D0
        cont_J = 0D0
      end if
      call integrate_within_one_cell(ph, length, f0, del_nu, &
        line_alpha, line_J, cont_alpha, cont_J, tau_this)
      tau = tau + tau_this
    end if
    !
    ph%ray%x = ph%ray%x + ph%ray%vx * (length + eps)
    ph%ray%y = ph%ray%y + ph%ray%vy * (length + eps)
    ph%ray%z = ph%ray%z + ph%ray%vz * (length + eps)
    !
    call locate_photon_cell_mirror(r, z, c, cnext, found)
    if (.not. found) then! Not entering a neighboring cell
      ! May be entering a non-neighboring cell?
      call enter_the_domain_mirror(ph, root, cnext, found)
      if (.not. found) then ! Escape
        return
      end if
    end if
    !
    c => cnext
    !
  end do
  !
  write(*, '(A)') 'In integerate_a_ray:'
  write(*, '(A)') 'Should not reach here!'
  write(*,'(I6, 10ES10.2/)') &
    i, &
    ph%ray%x, ph%ray%y, ph%ray%z, &
    ph%ray%vx, ph%ray%vy, ph%ray%vz, &
    c%xmin, c%xmax, c%ymin, c%ymax
  write(*,'(4ES10.2, I4, L4/)') sqrt(r), z, length, eps, dirtype, found
  stop
end subroutine integerate_a_ray


function colden_along_a_direction(x, y, z, costheta, sintheta, iSpe) result(N)
  double precision N
  double precision, intent(in) :: x, y, z
  double precision, intent(in) :: costheta, sintheta
  integer, intent(in) :: iSpe
  type(type_photon_packet) :: ph
  !
  ph%ray%vx = 0D0
  ph%ray%vy = -sintheta
  ph%ray%vz =  costheta
  !
  ph%ray%x =  x
  ph%ray%y =  y * costheta - z * sintheta
  ph%ray%z =  y * sintheta + z * costheta
  !
  N = colden_along_a_ray(ph, iSpe)
end function colden_along_a_direction



function colden_along_a_ray(ph0, iSpe) result(N)
  ! ph must be guaranteed to be inside c.
  ! An intersection between ph and c must exist, unless there is a
  ! numerical error.
  double precision N
  type(type_photon_packet), intent(in) :: ph0
  integer, intent(in) :: iSpe
  type(type_cell), pointer :: c
  type(type_cell), pointer :: cnext
  type(type_photon_packet) :: ph
  double precision length, r, z, eps
  logical found
  integer dirtype
  !
  integer i
  !
  N = 0D0
  !
  ph = ph0
  !
  call enter_the_domain_mirror(ph, root, c, found)
  if (.not. found) then
    return
  end if
  !
  do i=1, root%nOffspring*2
    ! Get the intersection between the photon ray and the boundary of the cell
    ! that this photon resides in
    call calc_intersection_ray_cell_mirror(ph%ray, c, &
      length, r, z, eps, found, dirtype)
    if (.not. found) then
      write(*,'(A, I6, 10ES10.2/)') 'In colden_along_a_ray, ph not cross c: ', &
        i, &
        ph%ray%x, ph%ray%y, ph%ray%z, &
        ph%ray%vx, ph%ray%vy, ph%ray%vz, &
        c%xmin, c%xmax, c%ymin, c%ymax
      return
    end if
    !
    if (c%using) then
      !
      N = N + c%par%n_gas * c%abundances(iSpe) * length * phy_AU2cm
      !
    end if
    !
    ph%ray%x = ph%ray%x + ph%ray%vx * (length + eps)
    ph%ray%y = ph%ray%y + ph%ray%vy * (length + eps)
    ph%ray%z = ph%ray%z + ph%ray%vz * (length + eps)
    !
    call locate_photon_cell_mirror(r, z, c, cnext, found)
    if (.not. found) then! Not entering a neighboring cell
      ! May be entering a non-neighboring cell?
      call enter_the_domain_mirror(ph, root, cnext, found)
      if (.not. found) then ! Escape
        return
      end if
    end if
    !
    c => cnext
    !
  end do
  !
  write(*, '(A)') 'In colden_along_a_ray:'
  write(*, '(A)') 'Should not reach here!'
  write(*,'(I6, 10ES10.2/)') &
    i, &
    ph%ray%x, ph%ray%y, ph%ray%z, &
    ph%ray%vx, ph%ray%vy, ph%ray%vz, &
    c%xmin, c%xmax, c%ymin, c%ymax
  write(*,'(4ES10.2, I4, L4/)') sqrt(r), z, length, eps, dirtype, found
  stop
end function colden_along_a_ray



subroutine integrate_within_one_cell(ph, length, f0, del_nu, &
        line_alpha, line_J, cont_alpha, cont_J, tau)
  type(type_photon_packet), intent(inout) :: ph
  double precision, intent(in) :: length, f0, del_nu, line_alpha, line_J, cont_alpha, cont_J
  double precision nu, nu1, nu2, dnu, x, dl, dtau, t1
  double precision, intent(out) :: tau
  double precision jnu, knu
  type(type_ray) ray
  integer i, ndiv
  !
  ray%x = ph%ray%x + ph%ray%vx * length
  ray%y = ph%ray%y + ph%ray%vy * length
  ray%z = ph%ray%z + ph%ray%vz * length
  ray%vx = ph%ray%vx
  ray%vy = ph%ray%vy
  ray%vz = ph%ray%vz
  !
  nu1 = get_doppler_nu(star_0%mass, ph%f, ph%ray)
  nu2 = get_doppler_nu(star_0%mass, ph%f, ray)
  !
  ndiv = 1 + &
    min(int(10D0 * abs(nu1 - nu2) / del_nu), &
        int(1D2 * (line_alpha + cont_alpha) * length * phy_AU2cm))
  dnu = (nu2 - nu1) / dble(ndiv)
  dl = length * phy_AU2cm / dble(ndiv)
  nu = nu1
  !
  tau = 0D0
  !
  do i=1, ndiv
    x = (nu - f0) / del_nu
    !
    if ((x .gt. 20D0) .or. (x .lt. -20D0)) then
      t1 = 0D0
    else
      t1 = exp(-x*x*0.5D0)
    end if
    !
    jnu = t1 * line_J + cont_J
    knu = t1 * line_alpha + cont_alpha
    !
    dtau = knu * dl
    tau = tau + dtau
    !
    if (dtau .ge. 1D-4) then
      if (dtau .gt. 100D0) then
        t1 = 0D0
        ph%Inu = jnu/knu
      else
        t1 = exp(-dtau)
        ph%Inu = ph%Inu * t1 + jnu/knu * (1D0 - t1)
      end if
    else
      ph%Inu = ph%Inu * (1D0 - dtau) + dl * jnu
    end if
    nu = nu + dnu
  end do
end subroutine integrate_within_one_cell




subroutine line_excitation_do
  type(type_cell), pointer :: c
  integer i
  !if (.not. a_disk_iter_params%do_line_transfer) then
  !  return
  !end if
  write(*, '(A/)') 'Doing energy level excitation calculation.'
  do i=1, leaves%nlen
    c => leaves%list(i)%p
    call do_exc_calc(c)
    write(*, '(I4, 4ES10.2)') i, c%xmin, c%xmax, c%ymin, c%ymax
  end do
end subroutine line_excitation_do


subroutine line_tran_prep
  !if (a_disk_iter_params%do_line_transfer) then
  call load_exc_molecule
  !else
  !  return
  !end if
  statistic_equil_params%NEQ = mole_exc%p%n_level
  statistic_equil_params%LIW = 20 + statistic_equil_params%NEQ
  statistic_equil_params%LRW = 22 + 9*statistic_equil_params%NEQ + &
                               statistic_equil_params%NEQ*statistic_equil_params%NEQ
  if (statistic_equil_params%NEQ .gt. mole_exc%p%n_level) then
    if (allocated(statistic_equil_params%IWORK)) then
      deallocate(statistic_equil_params%IWORK, statistic_equil_params%RWORK)
    end if
  end if
  if (.not. allocated(statistic_equil_params%IWORK)) then
    allocate(statistic_equil_params%IWORK(statistic_equil_params%LIW), &
             statistic_equil_params%RWORK(statistic_equil_params%LRW))
  end if
end subroutine line_tran_prep



subroutine load_exc_molecule
  integer i, i0, i1, j
  character(len=const_len_species_name) str, str1
  integer, dimension(:), allocatable :: itmp, itmp1
  double precision freq, en
  integer iup, ilow
  logical in_freq_window
  !
  mole_exc%conf = mole_line_conf
  allocate(mole_exc%p)
  !
  a_mol_using => mole_exc%p
  !
  mole_exc%p%abundance_factor = mole_exc%conf%abundance_factor
  !
  call load_moldata_LAMBDA(&
    combine_dir_filename(mole_exc%conf%dirname_mol_data, &
    mole_exc%conf%fname_mol_data))
  !
  a_mol_using%iType = -1
  !
  i = index(a_mol_using%name_molecule, '(')
  if (i .eq. 0) then
    str = a_mol_using%name_molecule
    a_mol_using%iType = 0
    str1 = ''
  else
    str = a_mol_using%name_molecule(1:(i-1))
    i = index(a_mol_using%name_molecule, 'ortho')
    if (i .ne. 0) then
      a_mol_using%iType = 1
      str1 = 'ortho'
    else
      i = index(a_mol_using%name_molecule, 'para')
      if (i .ne. 0) then
        a_mol_using%iType = 2
        str1 = 'para'
      end if
    end if
  end if
  !
  a_mol_using%iSpe = -1
  !
  do i=1, chem_species%nSpecies
    if (str .eq. chem_species%names(i)) then
      a_mol_using%iSpe = i
      exit
    end if
  end do
  if ((a_mol_using%iSpe .eq. -1) .or. (a_mol_using%iType .eq. -1)) then
    write(*, '(A)') 'In load_exc_molecule:'
    write(*, '(A)') 'Unidentified molecule name and/or type:'
    write(*, '(A)') a_mol_using%name_molecule
    write(*, '(A)') 'In file:'
    write(*, '(A)') combine_dir_filename( &
      mole_exc%conf%dirname_mol_data, &
      mole_exc%conf%fname_mol_data)
    stop
  end if
  write(*, '(A, 2A16)') 'Molecule: ', trim(str), str1
  write(*, '(A, I6)') 'Total number of levels: ', mole_exc%p%n_level
  write(*, '(A, I6)') 'Total number of radiative transitions: ', mole_exc%p%rad_data%n_transition
  write(*, '(A, I6)') 'Total number of collisional partners: ', mole_exc%p%colli_data%n_partner
  do i=1, mole_exc%p%colli_data%n_partner
    write(*, '(I2, 2X, 2A)') i, 'Partner name: ', mole_exc%p%colli_data%list(i)%name_partner
    write(*, '(I2, 2X, A, I6)') i, 'Total number of collisional transitions: ', &
      mole_exc%p%colli_data%list(i)%n_transition
    write(*, '(I2, 2X, A, I6)') i, 'Total number of collisional temperatures: ', &
      mole_exc%p%colli_data%list(i)%n_T
  end do
  !write(*,*)
  !write(*, '(A, 2ES12.4)') 'Frequency range to consider: ', &
  !     mole_exc%conf%freq_min, mole_exc%conf%freq_max
  !
  allocate(itmp(a_mol_using%n_level), &
           itmp1(a_mol_using%rad_data%n_transition), &
           mole_exc%ilv_reverse(a_mol_using%n_level))
  mole_exc%ilv_reverse = 0
  i0 = 0
  i1 = 0
  do i=1, a_mol_using%rad_data%n_transition
    freq = a_mol_using%rad_data%list(i)%freq
    en   = a_mol_using%rad_data%list(i)%Eup
    !
    in_freq_window = .false.
    do j=1, mole_exc%conf%nfreq_window
      if ((mole_exc%conf%freq_mins(j) .le. freq) .and. &
          (freq .le. mole_exc%conf%freq_maxs(j))) then
        in_freq_window = .true.
        exit
      end if
    end do
    !
    if (in_freq_window .and. &
        (en .ge. mole_exc%conf%E_min) .and. &
        (en .le. mole_exc%conf%E_max)) then
      i1 = i1 + 1
      itmp1(i1) = i
      iup = a_mol_using%rad_data%list(i)%iup
      ilow = a_mol_using%rad_data%list(i)%ilow
      if (.not. is_in_list_int(ilow, i0, itmp(1:i0))) then
        i0 = i0 + 1
        itmp(i0) = ilow
        mole_exc%ilv_reverse(ilow) = i0
      end if
      if (.not. is_in_list_int(iup, i0, itmp(1:i0))) then
        i0 = i0 + 1
        itmp(i0) = iup
        mole_exc%ilv_reverse(iup) = i0
      end if
    end if
  end do
  !
  mole_exc%nlevel_keep = i0
  mole_exc%ntran_keep  = i1
  allocate(mole_exc%ilv_keep(i0), &
           mole_exc%itr_keep(i1))
  mole_exc%ilv_keep = itmp(1:i0)
  mole_exc%itr_keep = itmp1(1:i1)
  deallocate(itmp, itmp1)
  write(*, '(A, I6)') 'Number of levels to keep:', mole_exc%nlevel_keep
  write(*, '(A, I6)') 'Number of transitions to keep:', mole_exc%ntran_keep
  !do i=1, mole_exc%nlevel_keep
  !  i0 = mole_exc%ilv_keep(i)
  !  write(*, '(I4, ES12.4)') i, mole_exc%p%level_list(i0)%energy
  !end do
  write(*,*)
end subroutine load_exc_molecule


subroutine set_using_mole_params(mole, c)
  type(type_cell), intent(in), pointer :: c
  type(type_molecule_energy_set), intent(inout), pointer :: mole
  select case (mole%iType)
  case (0)
    mole%density_mol = c%par%n_gas * c%abundances(mole%iSpe)
  case (1)
    mole%density_mol = c%par%n_gas * c%abundances(mole%iSpe) * 0.75D0
  case (2)
    mole%density_mol = c%par%n_gas * c%abundances(mole%iSpe) * 0.25D0
  case default
    write(*, '(A)') 'In set_using_mole_params:'
    write(*, '(A, I4)') 'Unknown molecule type: ', mole%iType
    write(*, '(A)') 'Will use the full abundance.'
    mole%density_mol = c%par%n_gas * c%abundances(mole%iSpe)
  end select
  !
  mole%density_mol = mole%density_mol * mole%abundance_factor
  !
  mole%Tkin = c%par%Tgas
  mole%dv = c%par%velo_width_turb
  mole%length_scale = c%par%coherent_length
end subroutine set_using_mole_params


subroutine do_exc_calc(c)
  type(type_cell), intent(inout), pointer :: c
  integer i
  !
  a_mol_using => mole_exc%p
  !
  call set_using_mole_params(a_mol_using, c)
  !
  a_mol_using%f_occupation = a_mol_using%level_list%weight * &
      exp(-a_mol_using%level_list%energy / a_mol_using%Tkin)
  a_mol_using%f_occupation = a_mol_using%f_occupation / sum(a_mol_using%f_occupation)
  !
  if (.not. mole_exc%conf%useLTE) then
    do i=1, a_mol_using%colli_data%n_partner
      select case (a_mol_using%colli_data%list(i)%name_partner)
      case ('H2')
        a_mol_using%colli_data%list(i)%dens_partner = &
          c%par%n_gas * c%par%X_H2
      case ('o-H2')
        a_mol_using%colli_data%list(i)%dens_partner = &
          0.75D0 * c%par%n_gas * c%par%X_H2
      case ('p-H2')
        a_mol_using%colli_data%list(i)%dens_partner = &
          0.25D0 * c%par%n_gas * c%par%X_H2
      case ('H')
        a_mol_using%colli_data%list(i)%dens_partner = &
          c%par%n_gas * c%par%X_HI
      case ('H+')
        a_mol_using%colli_data%list(i)%dens_partner = &
          c%par%n_gas * c%par%X_Hplus
      case ('e')
        a_mol_using%colli_data%list(i)%dens_partner = &
          c%par%n_gas * c%par%X_E
      case default
        write(*, '(A)') 'In do_exc_calc:'
        write(*, '(A)') 'Unknown collision partner:'
        write(*, '(A)') a_mol_using%colli_data%list(i)%name_partner
        write(*, '(A)') 'Will use zero abundance for this partner.'
        a_mol_using%colli_data%list(i)%dens_partner = 0D0
      end select
    end do
    !
    call make_local_cont_lut(c)
    !
    call statistic_equil_solve
  end if
  !
  if (.not. allocated(c%focc)) then
    allocate(c%focc)
    c%focc%nlevels = mole_exc%nlevel_keep
    allocate(c%focc%vals(c%focc%nlevels))
  end if
  c%focc%vals = a_mol_using%f_occupation(mole_exc%ilv_keep)
  !
  !nullify(a_mol_using)
end subroutine do_exc_calc



subroutine make_local_cont_lut(c)
  type(type_cell), intent(in), pointer :: c
  integer i
  double precision dlam, lam
  !
  if (.not. allocated(cont_lut%lam)) then
    cont_lut%n = dust_0%n
    allocate(cont_lut%lam(dust_0%n), &
             cont_lut%alpha(dust_0%n), &
             cont_lut%J(dust_0%n))
  end if
  !
  do i=1, cont_lut%n
    cont_lut%lam(i) = dust_0%lam(i)
    cont_lut%alpha(i) = c%optical%summed(i)
  end do
  !
  do i=1, cont_lut%n
    if (i .lt. cont_lut%n) then
      dlam = cont_lut%lam(i+1) - cont_lut%lam(i)
      lam = (cont_lut%lam(i+1) + cont_lut%lam(i)) * 0.5D0
      ! Energy per unit area per unit frequency per second per sqradian
      cont_lut%J(i) = c%optical%flux(i) &
        / dlam * lam * lam * phy_micron2cm / phy_SpeedOfLight_CGS &
        / (4D0 * phy_Pi)
    else
      cont_lut%J(i) = cont_lut%J(i-1)
    end if
  end do
end subroutine make_local_cont_lut

end module ray_tracing