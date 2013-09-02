module quick_sort
implicit none

public :: quick_sort_array
private :: partition, LE_vec, GE_vec

contains


recursive subroutine quick_sort_array(a, n, m, ncmp, icmp)
  ! Array to be sorted: a
  ! Array a has n columns and m rows.
  ! The sorting is performed along the column direction, namely,
  ! each row is treated as a whole.
  ! icmp contains the indices of the columns to be compared.
  ! ncmp = len(icmp)
  integer, intent(in) :: n, m, ncmp
  double precision, dimension(n, m), intent(inout) :: a
  integer, dimension(ncmp), intent(in) :: icmp
  integer ip
  if (m > 1) then
    call partition(a, n, m, ncmp, icmp, ip)
    if (ip > 2) then
      call quick_sort_array(A(:, 1:ip-1), n, ip-1, ncmp, icmp)
    end if
    if (m-ip > 0) then
      call quick_sort_array(A(:, ip:m), n, m-ip+1, ncmp, icmp)
    end if
  end if
end subroutine quick_sort_array


subroutine partition(a, n, m, ncmp, icmp, marker)
  integer, intent(in) :: n, m, ncmp
  double precision, dimension(n, m), intent(inout) :: a
  integer, dimension(ncmp), intent(in) :: icmp
  integer, intent(out) :: marker
  integer i, j
  double precision, dimension(n) :: x, tmp
  x = a(:, 1)
  i = 0
  j = m + 1
  do
    i = i + 1
    do
      if (GE_vec(a(:, i), x, ncmp, icmp)) then
        exit
      else
        i = i + 1
      end if
    end do
    j = j - 1
    do
      if (LE_vec(a(:, j), x, ncmp, icmp)) then
        exit
      else
        j = j - 1
      end if
    end do
    if (i < j) then
      tmp = a(:, i)
      a(:, i) = a(:, j)
      a(:, j) = tmp
    else if (i == j) then
      marker = i + 1
      return
    else
      marker = i
      return
    end if
  end do
end subroutine partition


function LE_vec(x, y, ncmp, icmp)
  ! Return true if x <= y in the lexical sense
  logical LE_vec
  double precision, dimension(:), intent(in) :: x, y
  integer ncmp
  integer, dimension(:), intent(in) :: icmp
  integer i, j
  do i=1, ncmp
    j = icmp(i)
    if (x(j) .lt. y(j)) then
      LE_vec = .true.
      return
    else if (x(j) .gt. y(j)) then
      LE_vec = .false.
      return
    else
      LE_vec = .true.
    end if
  end do
end function LE_vec


function GE_vec(x, y, ncmp, icmp)
  logical GE_vec
  double precision, dimension(:), intent(in) :: x, y
  integer ncmp
  integer, dimension(:), intent(in) :: icmp
  integer i, j
  do i=1, ncmp
    j = icmp(i)
    if (x(j) .gt. y(j)) then
      GE_vec = .true.
      return
    else if (x(j) .lt. y(j)) then
      GE_vec = .false.
      return
    else
      GE_vec = .true.
    end if
  end do
end function GE_vec

end module quick_sort