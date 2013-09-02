module configure

use trivials
use data_struct
use grid
use disk
use chemistry
use heating_cooling

implicit none

character(len=128) :: filename_config = ''


contains


subroutine config_do
  use my_timer
  integer fU
  logical flag_exist
  type(date_time) a_date_time

  !if (.NOT. IsWordChar(filename_config(1:1))) then
  !  write(*,*) 'Configure file name invalid!'
  !  stop
  !end if
  !
  if (.NOT. getFileUnit(fU)) then
    write(*,*) 'Cannot get a file unit!'
    stop
  end if

  call openFileSequentialRead(fU, filename_config, 999)
  !
  read(fU, nml=grid_configure)
  read(fU, nml=chemistry_configure)
  read(fU, nml=heating_cooling_configure)
  read(fU, nml=disk_configure)
  read(fU, nml=cell_configure)
  read(fU, nml=analyse_configure)
  read(fU, nml=iteration_configure)
  !
  close(fU, status='KEEP')
  !

  if (.NOT. dir_exist(a_disk_iter_params%iter_files_dir)) then
    call my_mkdir(a_disk_iter_params%iter_files_dir)
  end if
  a_book_keeping%dir = trim(combine_dir_filename(a_disk_iter_params%iter_files_dir, 'logs/'))
  a_book_keeping%filename_log = 'log.dat'
  if (.NOT. dir_exist(a_book_keeping%dir)) then
    call my_mkdir(a_book_keeping%dir)
  end if
  ! Make a backup of the configure file.
  if (file_exist(trim(combine_dir_filename(a_book_keeping%dir, a_book_keeping%filename_log)))) then
    write(*,*) trim(a_book_keeping%dir), ' is not empty!'
    write(*,*) 'I would rather not overwrite it.'
    stop
  else
    call my_cp_to_dir(filename_config, a_book_keeping%dir)
  end if
  !
  if (.NOT. getFileUnit(a_book_keeping%fU)) then
    write(*,*) 'Cannot get a file unit for logging.'
  end if
  call openFileSequentialWrite(a_book_keeping%fU, &
    trim(combine_dir_filename(a_book_keeping%dir, a_book_keeping%filename_log)), 9999)
  write(a_book_keeping%fU, '(A)') '! Current time: ' // trim(a_date_time%date_time_str())
  write(a_book_keeping%fU, '("! The content of your original configure file.")')
  write(a_book_keeping%fU, nml=grid_configure)
  write(a_book_keeping%fU, nml=chemistry_configure)
  write(a_book_keeping%fU, nml=disk_configure)
  write(a_book_keeping%fU, nml=cell_configure)
  write(a_book_keeping%fU, nml=iteration_configure)
  write(a_book_keeping%fU, '("! End of the content of your original configure file.")')
  write(a_book_keeping%fU, '("! The following content are for book-keeping purposes.")')
  flush(a_book_keeping%fU)
  !
  if (disk_params_ini%backup_src) then
    write(*,*) 'Backing up your source code...'
    call my_cp_to_dir(disk_params_ini%filename_exe, a_book_keeping%dir)
    call system(trim(disk_params_ini%backup_src_cmd) // ' ' // trim(a_book_keeping%dir))
    write(*,*) 'Source code backup finished.'
  end if
end subroutine config_do

end module configure