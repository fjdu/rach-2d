module load_Draine_dusts

use phy_const
use trivials

implicit none

integer, parameter, private :: constLenDustName = 64
integer, parameter, private :: nDustRawSpeciesMax = 4
integer, parameter, private :: nDustMixturesMax = 4


type :: type_dust_composition
  ! These are to be set by the user
  character(len=128) dir
  integer id, nrawdust
  double precision rho
  character(len=128), dimension(nDustRawSpeciesMax) :: filenames
  double precision, dimension(nDustRawSpeciesMax) :: weights
end type type_dust_composition


type :: type_mix_info
  integer nmixture
  double precision :: lam_min, lam_max
  type(type_dust_composition), dimension(nDustMixturesMax) :: mix
end type type_mix_info


type :: type_dust_data
  ! The following will be loaded by the code
  character(len=constLenDustName) dustname
  integer nradius, nlam
  double precision radmin, radmax, wmin, wmax
  double precision, dimension(:),    allocatable :: r  ! radius (micron)
  double precision, dimension(:),    allocatable :: w  ! wavelengths (micron)
  double precision, dimension(:, :), allocatable :: ab ! absorption cross section (micron^2)
  double precision, dimension(:, :), allocatable :: sc
  double precision, dimension(:, :), allocatable :: g
end type type_dust_data


type :: type_dust_collection_data
  integer n
  type(type_dust_data), dimension(:), allocatable :: list
end type type_dust_collection_data


type(type_mix_info) :: dustmix_info

type(type_dust_collection_data) :: dustmix_data

namelist /dustmix_configure/ dustmix_info


private :: reorder_dust_data, clip_dust_data


contains


subroutine prep_dust_data
  integer i
  type(type_dust_collection_data) :: rawdust_data
  character(len=32) str
  !
  dustmix_data%n = dustmix_info%nmixture
  if (.not. allocated(dustmix_data%list)) then
    allocate(dustmix_data%list(dustmix_info%nmixture))
  end if
  !
  do i=1, dustmix_info%nmixture
    if (allocated(rawdust_data%list)) then
      deallocate(rawdust_data%list)
    end if
    rawdust_data%n = dustmix_info%mix(i)%nrawdust
    allocate(rawdust_data%list(rawdust_data%n))
    !
    call load_dusts(dustmix_info%mix(i), rawdust_data%list)
    !
    call mix_rawdusts(rawdust_data%n, rawdust_data%list, &
                   dustmix_info%mix(i)%weights, dustmix_data%list(i))
    !
    call reorder_dust_data(dustmix_data%list(i))
    !
    call clip_dust_data(dustmix_data%list(i), &
        dustmix_info%lam_min, dustmix_info%lam_max)
    !
    write(str, '("(A, ", I2, "(", A, "F0.2))")') &
      dustmix_info%mix(i)%nrawdust, '"-",'
    write(dustmix_data%list(i)%dustname, str) &
      'Mixed', dustmix_info%mix(i)%weights(1:rawdust_data%n)
    !write(*,*) dustmix_data%list(i)%dustname
    !write(*,*) dustmix_data%list(i)%nradius, dustmix_data%list(i)%nlam
    !write(*,*) dustmix_data%list(i)%r(1:5), dustmix_data%list(i)%w(1:5)
    !write(*,*) dustmix_data%list(i)%ab(1:5, i), dustmix_data%list(i)%sc(1:5, i)
    !write(*,*) maxval(dustmix_data%list(i)%g(:, i))
    !write(*,*) maxval(rawdust_data%list(1)%g)
    !write(*,*) maxval(rawdust_data%list(2)%g)
    !write(*,*) maxval(rawdust_data%list(3)%g)
  end do
end subroutine prep_dust_data




subroutine mix_rawdusts(nrawdust, rawdusts, wei, mixed)
  ! Mix different dust species, NOT mix different dust sizes!
  ! Dust grains with different size share the same weights.
  ! Arrays in all the rawdusts to be mixed must have the same dimension.
  integer, intent(in) :: nrawdust
  type(type_dust_data), dimension(:), intent(in) :: rawdusts
  double precision, dimension(:), intent(in) :: wei
  type(type_dust_data), intent(out) :: mixed
  double precision sumw
  integer i
  !
  if (allocated(mixed%r)) then
    deallocate(mixed%r, mixed%w, mixed%ab, mixed%sc, mixed%g)
  end if
  !
  mixed%nradius = rawdusts(1)%nradius
  mixed%nlam = rawdusts(1)%nlam
  mixed%radmin = rawdusts(1)%radmin
  mixed%radmax = rawdusts(1)%radmax
  mixed%wmin = rawdusts(1)%wmin
  mixed%wmax = rawdusts(1)%wmax
  !
  allocate(mixed%r(mixed%nradius), &
           mixed%w(mixed%nlam), &
           mixed%ab(mixed%nlam, mixed%nradius), &
           mixed%sc(mixed%nlam, mixed%nradius), &
           mixed%g(mixed%nlam,  mixed%nradius))
  !
  mixed%r = rawdusts(1)%r
  mixed%w = rawdusts(1)%w
  mixed%ab = 0D0
  mixed%sc = 0D0
  mixed%g = 0D0
  !
  sumw = 0D0
  do i=1, nrawdust
    if ((maxval(abs(rawdusts(i)%r - mixed%r)) .gt. (0.1D0*mixed%radmin)) .or. &
        (maxval(abs(rawdusts(i)%w - mixed%w)) .gt. (0.1D0*mixed%wmin))) then
      write(*, '(A)') 'In mix_rawdusts:'
      write(*, '(A)') 'Dust data inconsistent!'
      write(*, '(A, I4)') 'iDust = ', i
      write(*, '(A)') 'Stop.'
      stop
    end if
    mixed%ab = mixed%ab + wei(i) * rawdusts(i)%ab
    mixed%sc = mixed%sc + wei(i) * rawdusts(i)%sc
    mixed%g  = mixed%g + wei(i) * rawdusts(i)%g
    sumw = sumw + wei(i)
  end do
  mixed%ab = mixed%ab / sumw
  mixed%sc = mixed%sc / sumw
  mixed%g  = mixed%g  / sumw
end subroutine mix_rawdusts


subroutine reorder_dust_data(d)
  type(type_dust_data), intent(inout) :: d
  integer i
  !
  if (d%w(2) .ge. d%w(1)) then
    ! Already in ascending order
    return
  end if
  !
  d%w = d%w(d%nlam:1:-1)
  do i=1, d%nradius
    d%ab(:, i) = d%ab(d%nlam:1:-1, i)
    d%sc(:, i) = d%sc(d%nlam:1:-1, i)
    d%g(:, i) = d%g(d%nlam:1:-1, i)
  end do
end subroutine reorder_dust_data



subroutine clip_dust_data(d, lammin, lammax)
  type(type_dust_data), intent(inout) :: d
  double precision, intent(in) :: lammin, lammax
  integer i, i1, i2, n
  double precision, dimension(:), allocatable :: t
  double precision, dimension(:,:), allocatable :: tt
  i1 = 1
  i2 = d%nlam
  do i=1, d%nlam-1
    if ((d%w(i) .le. lammin) .and. (d%w(i+1) .ge. lammin)) then
      i1 = i
    end if
    if ((d%w(i) .le. lammax) .and. (d%w(i+1) .ge. lammax)) then
      i2 = i+1
    end if
  end do
  if ((i1 .eq. 1) .and. (i2 .eq. d%nlam)) then
    return
  end if
  !
  n = i2 - i1 + 1
  allocate(t(n))
  !
  t = d%w(i1:i2)
  deallocate(d%w)
  allocate(d%w(n))
  d%w = t
  !
  deallocate(t)
  !
  allocate(tt(n, d%nradius))
  tt = d%ab(i1:i2, :)
  deallocate(d%ab)
  allocate(d%ab(n, d%nradius))
  d%ab = tt
  !
  tt = d%sc(i1:i2, :)
  deallocate(d%sc)
  allocate(d%sc(n, d%nradius))
  d%sc = tt
  !
  tt = d%g(i1:i2, :)
  deallocate(d%g)
  allocate(d%g(n, d%nradius))
  d%g = tt
  !
  deallocate(tt)
  !
  d%nlam = n
  d%wmin = d%w(1)
  d%wmax = d%w(n)
end subroutine clip_dust_data


subroutine load_dusts(rawdustinfo, raw_dust_data)
  type(type_dust_composition), intent(in) :: rawdustinfo
  type(type_dust_data), dimension(:), intent(out) :: raw_dust_data
  integer i
  !
  !if (.not. allocated(raw_dust_data)) then
  !  allocate(raw_dust_data(rawdustinfo%nrawdust))
  !end if
  do i=1, rawdustinfo%nrawdust
    call load_Draine_dust( &
      raw_dust_data(i), &
      trim(combine_dir_filename(rawdustinfo%dir, &
           rawdustinfo%filenames(i))))
  end do
end subroutine load_dusts


subroutine load_Draine_dust(dust, filename)
  type(type_dust_data), intent(inout) :: dust
  character(len=*), intent(in) :: filename
  integer i, j, fU
  double precision t1
  !
  call openFileSequentialRead(fU, filename, 128)
  !
  read(fU, *)
  read(fU, '(A)') dust%dustname
  read(fU, *)
  read(fU, '(I4, X, F9.1, X, F9.1)') dust%nradius, dust%radmin, dust%radmax
  read(fU, '(I4, X, F9.1, X, F9.1)') dust%nlam,    dust%wmin,   dust%wmax
  !
  if (allocated(dust%r)) then
    deallocate(dust%r, dust%w, dust%ab, dust%sc, dust%g)
  end if
  allocate(dust%r(dust%nradius), &
           dust%w(dust%nlam), &
           dust%ab(dust%nlam, dust%nradius), &
           dust%sc(dust%nlam, dust%nradius), &
           dust%g(dust%nlam,  dust%nradius))
  do i=1, dust%nradius
    read(fU, *)
    read(fU, '(F9.1)') dust%r(i)
    read(fU, *)
    do j=1, dust%nlam
      read(fU, '(F9.1, X, F9.1, X, F9.1, X, F9.1)') &
        t1, dust%ab(j, i), dust%sc(j, i), dust%g(j, i)
      if (i .eq. 1) then
        dust%w(j) = t1
      else if (abs(t1 - dust%w(j)) .gt. &
               (1D-3 * (t1 + dust%w(j)))) then
        write(*, '(A)')  'In load_Draine_dust:'
        write(*, '(A)')  'Wavelengths for different radius do not match:'
        write(*, '(2I4, 2ES12.4)')  i, j, dust%w(j), t1
        write(*, '(A/)')  'Will continue anyway.'
      end if
      !
      dust%ab(j, i) = dust%ab(j, i) * (phy_pi * dust%r(i) * dust%r(i))
      dust%sc(j, i) = dust%sc(j, i) * (phy_pi * dust%r(i) * dust%r(i))
    end do
  end do
  close(fU)
end subroutine load_Draine_dust



end module load_Draine_dusts