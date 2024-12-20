!<f90File>**************************************************************
!  --------------------------------------------------------------------------
! |  Copyright �, Atmospheric and Environmental Research, Inc., 2022         |
! |                                                                          |
! |  All rights reserved. This source code was developed as part of the      |
! |  LBLRTM software and is designed for scientific and research purposes.   |
! |  Atmospheric and Environmental Research Inc. (AER) grants USER the right |
! |  to download, install, use and copy this software for scientific and     |
! |  research purposes only. This software may be redistributed as long as   |
! |  this copyright notice is reproduced on any copy made and appropriate    |
! |  acknowledgment is given to AER. This software or any modified version   |
! |  of this software may not be incorporated into proprietary software or   |
! |  commercial software offered for sale without the express written        |
! |  consent of AER.                                                         |
! |                                                                          |
! |  This software is provided as is without any express or implied          |
! |  warranties.                                                             |
!  --------------------------------------------------------------------------
!    Address questions to: aer_contnm@aer.com
!    General reference: Mlawer et al. (2012), doi:10.1098/rsta.2011.0295
!
!*************************************************************</f90File>

MODULE read_file
  implicit none
  include "netcdf.inc"
  !
  ! Module that provides FORTRAN 90 style netCDF reading support
  private
  public getData
  public data2read
  type data2read
     real(kind=8), allocatable, dimension(:) :: wavenumber
     real(kind=8), allocatable, dimension(:) :: for_absco_ref
     real(kind=8), allocatable, dimension(:) :: self_absco_ref
     real(kind=8), allocatable, dimension(:) :: self_texp
     real(kind=8) :: ref_temp
     real(kind=8) :: ref_press
     real(kind=8), allocatable, dimension(:) :: wavenumber_wv_bdimer
     real(kind=8), allocatable, dimension(:) :: wv_bdimer_xs_ref
     real(kind=8) :: ref_temp_wv_bdimer
  end type data2read

  logical, parameter                      :: dbg = .FALSE.
  interface readVarNC
     module procedure readReal1D
     module procedure readDouble1D
     module procedure readDouble
     module procedure readString
  end interface

  contains
  function getData(fname,FRGNX,dat,version) result(isError)
                      
    character(len=*), intent(in)     :: fname
    character, intent(in)            :: FRGNX
    type(data2read),  intent(inout)  :: dat
    character(len=*), intent(inout)  :: version
    logical                          :: isError

    integer(kind=4)   :: ncid
    integer(kind=4)   :: nWavenumbers
    integer(kind=4)   :: nWavenumbers_bdimer
    integer(kind=4)   :: stat

    ! check on the file
    inquire(file = fname, EXIST=isError) 
    isError = .NOT. isError
    if (isError) then
       print '("ERROR::read_file:: file not found ",A)', trim(fname)
       return
    endif

    if (dbg) print *, 'reading: ', trim(fname)
    call check( nf_open(fname, nf_nowrite, ncid) )

    if (.not. inqDim(ncid, "wavenumbers",  dimLen=nWavenumbers)) then
      call check( nf_close(ncid) )
      isError = .false.
      return
    end if
    if (.not. inqDim(ncid, "nwvn_bdimer",  dimLen=nWavenumbers_bdimer)) then
      call check( nf_close(ncid) )
      isError = .false.
      return
    end if
    ! allocate structure
    if (allocated(dat%wavenumber))   deallocate(dat%wavenumber)
    if (allocated(dat%for_absco_ref))    deallocate(dat%for_absco_ref)
    if (allocated(dat%self_absco_ref))   deallocate(dat%self_absco_ref)
    if (allocated(dat%self_texp))   deallocate(dat%self_texp)
    if (allocated(dat%wavenumber_wv_bdimer))   deallocate(dat%wavenumber_wv_bdimer)
    if (allocated(dat%wv_bdimer_xs_ref))    deallocate(dat%wv_bdimer_xs_ref)

    allocate(dat%wavenumber(nWavenumbers), &
             dat%for_absco_ref(nWavenumbers), &
             dat%self_absco_ref(nWavenumbers),   &
             dat%self_texp(nWavenumbers), &
             dat%wavenumber_wv_bdimer(nWavenumbers_bdimer),   &
             dat%wv_bdimer_xs_ref(nWavenumbers_bdimer), STAT= stat)
    isError = stat /= 0
    if (isError) then
       print '("ERROR::read_file:: memory allocation ")'
       return
    endif

    ! read variables
    call readVarNC(ncid,"wavenumbers",   dat%wavenumber)
    if (FRGNX.EQ.'1') then
      call readVarNC(ncid,"for_closure_absco_ref",    dat%for_absco_ref)
    else
      call readVarNC(ncid,"for_absco_ref",    dat%for_absco_ref)
    endif
    call readVarNC(ncid,"self_absco_ref",   dat%self_absco_ref)
    call readVarNC(ncid,"self_texp",   dat%self_texp)
    call readVarNC(ncid,"ref_temp",   dat%ref_temp)
    call readVarNC(ncid,"ref_press",   dat%ref_press)
    call readVarNC(ncid,"wavenumbers_bdimer",   dat%wavenumber_wv_bdimer)
    call readVarNC(ncid,"wv_bdimer_xs_ref",   dat%wv_bdimer_xs_ref)
    call readVarNC(ncid,"ref_temp_wv_bdimer",   dat%ref_temp_wv_bdimer)
    call readVarNC(ncid,"title",   version)
    call check( nf_close(ncid) )

  end function getData


   subroutine check(status, varName, fatal)
     integer,                     intent(in) :: status
     character(len=*),  optional, intent(in) :: varName
     logical,           optional, intent(in) :: fatal

     logical             :: fatalLoc
     if (present(fatal)) then
        fatalLoc = fatal
      else
        fatalLoc = .true.
      end if

     if(status /= nf_noerr) then
       if (present(varName)) print *,'Processing: ', varName
       if (fatalLoc) then
         print *, 'netCDF error: ', status, ' : ', trim(nf_strerror(status))
        call exit(1)
      else
         print *, 'netCDF WARNING: ', status, ' : ', trim(nf_strerror(status))
         print *, 'status', status
    end if
     end if
   end subroutine check

   function inqDim(id, dimName, dimLen)
      integer(kind=4),          intent(in)    :: id
      character(len=*),         intent(in)    :: dimName
      integer(kind=4), optional, intent(inout):: dimLen
      integer(kind=4)                         :: dimId
      logical                                 :: inqDim

      if (dbg) print*, ' ncdfUtil::inqDim '
      inqDim = (nf_noerr == nf_inq_dimid(id, dimName, dimId))
      if (present(dimLen)) then
        if (inqDim) then
          call check( NF_INQ_DIMLEN(id, dimId,dimLen) )
        else
          dimLen = -1
        end if
      end if
   end function inqDim  

   subroutine readReal1D(id, varName, val, fatal)
      integer(kind=4),        intent(in)   :: id
      character(len=*),       intent(in)   :: varName
      real*4, dimension(:),   intent(inout):: val
      integer(kind=4)                      :: varId
      logical,        optional, intent(in) :: fatal
      if (dbg) print*, ' ncdfUtil::readReal1D '
      call check(nf_inq_varid(id, varName, varId), varName, fatal)
      call check(nf_get_var(id, varId, val), varName, fatal)
   end subroutine readReal1D

   subroutine readDouble1D(id, varName, val, fatal)
      integer(kind=4),        intent(in)   :: id
      character(len=*),       intent(in)   :: varName
      real*8, dimension(:),   intent(inout):: val
      integer(kind=4)                      :: varId
      logical,        optional, intent(in) :: fatal
      if (dbg) print*, ' ncdfUtil::readDouble1D '
      call check(nf_inq_varid(id, varName, varId), varName, fatal)
      call check(nf_get_var(id, varId, val), varName, fatal)
   end subroutine readDouble1D

   subroutine readDouble(id, varName, val, fatal)
    integer(kind=4),        intent(in)   :: id
    character(len=*),       intent(in)   :: varName
    real*8,                 intent(inout):: val
    integer(kind=4)                      :: varId
    logical,        optional, intent(in) :: fatal
    if (dbg) print*, ' ncdfUtil::readDouble1D '
    call check(nf_inq_varid(id, varName, varId), varName, fatal)
    call check(nf_get_var(id, varId, val), varName, fatal)
 end subroutine readDouble

  subroutine readString(id, varName, val, fatal)
    integer(kind=4),        intent(in)   :: id
    character(len=*),       intent(in)   :: varName
    character(len=*),      intent(inout):: val
    integer(kind=4)                      :: varId
    logical,        optional, intent(in) :: fatal
    integer                              :: status
  if (dbg) print*, ' ncdfUtil::readString '
  status= nf_get_att(id, NF_GLOBAL, varName, val)
  
  end subroutine readString
end module read_file
