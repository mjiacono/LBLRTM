!<f90File>**************************************************************
!
!                  The MT_CKD Water Vapor Continuum
!
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
  
!    This code calculates self and foreign water vapor continuum coefficients
!    from the MT_CKD water vapor continuum model for a given pressure,
!    temperature, fraction of water vapor, and a specified wavenumber range and spacing. 

!    The MT_CKD reference continuum coefficients are read from the netCDF file absco-ref_mt_ckd_h2o.nc. 
!    The coefficients have units cm^2/molecule/cm^-1 and are normalized to a reference density
!    (P=1013 mb, T=296K) of the relevant collisional partner (self - water vapor, foreign - all
!    gases except water vapor). The radiation field (units of cm-1), must be applied to these
!    coefficients if optical depths are computed -- this operation is optional in this routine
!    (depends on radflag).  Once the radiation term is applied, optical depths can be obtained by
!    multiplying the continuum coefficients by the water vapor column amount (molecules/cm^2). (This
!    final step is not performed in this routine.)
!
!    Description of input variables.
!    p_atm - atmospheric pressure for the calculation of continuum coefficients  (mbar)
!    t_atm - atmospheric temperature for the calculation of continuum coefficients (K)
!    h2o_frac - fraction of the total number of molecules that are water vapor
!    wv1abs - initial wavenumber for which continuum coefficients will be computed (cm-1)
!    wv2abs - final wavenumber for which continuum coefficients will be computed (cm-1)
!    dvabs - wavenumber spacing for the continuum coefficient calculation (cm-1)
!    radflag - (optional) if true, multiply by radiation term (default); if false, do not 
!
!    Description of output variables.
!    self_absco - computed water vapor self continuum absorption coefficients
!    for_absco - computed water vapor foreign continuum absorption coefficients
!    for_closure_absco - same as above, but allows for closure
!    Units of the output variables are cm2/molec if radflag = 1; otherwise the units are cm2/molec/cm-1
Module mt_ckd_h2o
   
     USE lblparams, only: n_absrb
     USE read_file
     USE phys_consts,only: RADCN2
!                                                                       
      IMPLICIT none
      private 
      public mt_ckd_h2o_absco
!              
      type(data2read),save  :: dat
      character(len=*), parameter :: fDataname = "absco-ref_wv-mt-ckd.nc"

      real,parameter :: xlosmt=2.68675E+19
      real ::onepl = 1.001,onemi = 0.999 

      real,parameter :: c1_b = 4.7856e-04
      real,parameter :: c2_b = 1580.7467
      real,parameter :: c3_b = 4.88e-03
      real,parameter :: Ei = 350.
      real,parameter :: q_const = 1.5

   contains
   subroutine mt_ckd_h2o_absco(p_atm,t_atm,h2o_vmr,wv1abs,wv2abs,dvabs,self_absco,for_absco, &
      FRGNX,radflag,mt_version) 

! Inputs
   real,dimension(:),intent(inout)  :: self_absco,for_absco
   real, intent(in) :: p_atm,t_atm,h2o_vmr
   double precision, intent(in):: wv1abs,wv2abs
   real, intent(in):: dvabs
   character, intent(in):: FRGNX
   logical,optional :: radflag
   character(len=*),optional :: mt_version 

! Local variables
   real :: bdimer_absco(n_absrb)
   integer :: ncoeff,nptabs,i1,i2,ist,lst,i
   integer :: ncoeff_bdimer,i1_bdimer,i2_bdimer
   real :: xkt,dvc,rho_rat
   real :: dvc_bdimer,rho_rat_bdimer

   integer,save :: ncoeffin
   real,dimension(:), allocatable,save :: wvn
   !real,dimension(:,:), allocatable,save :: coeff
   integer,save :: ncoeffin_bdimer
   real,dimension(:), allocatable,save :: wvn_bdimer

   real,dimension(:), allocatable :: sh2o_coeff,fh2o_coeff,rad
   real,dimension(:), allocatable :: dh2o_coeff,rad_bdimer
   real :: tref_bdimer,k_b_eq
   integer :: iret,vlen
   logical,save :: lread=.False.
   character(len=85) :: version
   
   if (.not. present(radflag)) then
      radflag = .TRUE.
   endif

! Read in spectral range and coefficients 
   if (.not. lread) then
      lread = .True.
      if (getData(fDataname,FRGNX,dat,version)) STOP   
   if ( present(mt_version)) then
      vlen = len(version)
      mt_version=version(4:50)
   endif

      ncoeffin = size(dat%wavenumber)
      if (allocated(wvn)) deallocate(wvn)
      allocate (wvn(ncoeffin))
      wvn = dat%wavenumber(:)

      ncoeffin_bdimer = size(dat%wavenumber_wv_bdimer)
      if (allocated(wvn_bdimer)) deallocate(wvn_bdimer)
      allocate (wvn_bdimer(ncoeffin_bdimer))
      wvn_bdimer = dat%wavenumber_wv_bdimer(:)
   endif

! Find coeff wavenumber range that brackets [wv1abs,wv2abs].
   dvc = dat%wavenumber(2)-dat%wavenumber(1)
   i=1
   do while (wvn(i) <= (wv1abs-2*dvc))
      i = i+1
   enddo
   i1=i-1 
   if(i1.eq.0) i1=1
   do while (wvn(i) < (wv2abs+2*dvc))
      i = i+1
   enddo
   i2=i
   ncoeff = i2-i1+1

! Find bound dimer coeff wavenumber range that brackets [wv1abs,wv2abs].
   dvc_bdimer = dat%wavenumber_wv_bdimer(2)-dat%wavenumber_wv_bdimer(1)
   i=1
   do while (wvn_bdimer(i) <= (wv1abs-2*dvc_bdimer))
      i = i+1
   enddo
   i1_bdimer=i-1 
   if(i1_bdimer.eq.0) i1_bdimer=1
   do while (wvn_bdimer(i) < (wv2abs+2*dvc_bdimer))
      i = i+1
   enddo
   i2_bdimer=i
   ncoeff_bdimer = i2_bdimer-i1_bdimer+1

! Set up arrays.
   if (allocated (sh2o_coeff)) deallocate (sh2o_coeff)
   if (allocated (fh2o_coeff)) deallocate (fh2o_coeff)
   if (allocated (dh2o_coeff)) deallocate (dh2o_coeff)
   if (allocated (rad)) deallocate (rad)
   if (allocated (rad_bdimer)) deallocate (rad_bdimer)
   allocate (sh2o_coeff(ncoeff))
   allocate (fh2o_coeff(ncoeff))
   allocate (dh2o_coeff(ncoeff_bdimer))
   allocate (rad(ncoeff))
   allocate (rad_bdimer(ncoeff_bdimer))
   
! Define some atmospheric parameters
   xkt = t_atm/radcn2 
! The continuum coefficients stored in the netCDF are valid for a reference density and must be 
! be scaled by this factor to accout for the given atmospheric density.
! ref_press (1013 mb) and ref_temp (296K) are read in from absco-ref_wv-mt-ckd.nc
   rho_rat = (p_atm/dat%ref_press)*(dat%ref_temp/t_atm)
   rho_rat_bdimer = (p_atm/dat%ref_press)*(dat%ref_temp_wv_bdimer/t_atm)

! *****************
! Compute water vapor self continuum absorption coefficient. This includes:
!  - contributions from other than bound dimer (sh2o_coeff, stored every 10 cm-1)
!  - bound dimer (dh2o_coeff, stored every 1 cm-1
! These two self continuum components have different dependence on temperature.

! Apply temperature dependence to reference water vapor self continuum coefficients
! and scale to given density.
    sh2o_coeff = dat%self_absco_ref(i1:i2) * (dat%ref_temp/t_atm)**dat%self_texp(i1:i2)
    sh2o_coeff = sh2o_coeff * h2o_vmr * rho_rat

! Multiply by radiation term if requested
    if (radflag) then 
       iret = myradfn(wvn(i1:i2),xkt,ncoeff,rad)
       sh2o_coeff = sh2o_coeff * rad
    endif

! Interpolate coefficients to output spectral grid.
   nptabs = (wv2abs-wv1abs)/dvabs+1
   call pre_xint(wvn(1),wvn(ncoeffin),wv1abs,dvabs,nptabs,ist,lst)
   call myxint(wvn(i1),wvn(i2),dvc,sh2o_coeff,1.0,wv1abs,dvabs,self_absco,ist,lst)


! Compute water vapor bound dimer continuum absorption coefficient.

! Convert input bound dimer cross-section data to absorption coefficient (following
! Simonova et al. (2024) Eq. B-1 and B-2), apply temperature dependence to reference
! water vapor bound dimer continuum coefficients, and scale to given density.
    tref_bdimer = dat%ref_temp_wv_bdimer
    k_b_eq = c1_b * exp(c2_b/t_atm - c3_b*t_atm)
    dh2o_coeff = k_b_eq * dat%wv_bdimer_xs_ref * &
                 (tref_bdimer/t_atm)**q_const * &
                 (exp(-radcn2*Ei/t_atm) / exp(-radcn2*Ei/tref_bdimer))

    dh2o_coeff = dh2o_coeff * h2o_vmr * rho_rat_bdimer

! Multiply by radiation term if requested
    if (radflag) then 
       iret = myradfn(wvn_bdimer(i1_bdimer:i2_bdimer),xkt,ncoeff_bdimer,rad_bdimer)
       dh2o_coeff = dh2o_coeff * rad_bdimer
    endif

! Interpolate coefficients to output spectral grid.
   nptabs = (wv2abs-wv1abs)/dvabs+1
   call pre_xint(wvn_bdimer(1),wvn_bdimer(ncoeffin_bdimer),wv1abs,dvabs,nptabs,ist,lst)
   call myxint(wvn_bdimer(i1_bdimer),wvn_bdimer(i2_bdimer),dvc_bdimer,dh2o_coeff,1.0,wv1abs, &
               dvabs,bdimer_absco,ist,lst)

! Combine self continuum contributions from both sources.
   self_absco = self_absco + bdimer_absco

! *****************
! Compute water vapor foreign continuum absorption coefficient.
   fh2o_coeff = dat%for_absco_ref(i1:i2)
   fh2o_coeff = fh2o_coeff * (1-h2o_vmr) * rho_rat
   
! Multiply by radiation term if requested
    if (radflag) then 
       fh2o_coeff= fh2o_coeff * rad
    endif

! Interpolate coefficients to output spectral grid.
   call myxint(wvn(i1),wvn(i2),dvc,fh2o_coeff,1.0,wv1abs,dvabs,for_absco,ist,lst)
! *****************

   end subroutine mt_ckd_h2o_absco

!=======================================================================
!
   integer function myradfn(vi,xkt,nvi,rad)
!
!     FUNCTION RADFN CALCULATES THE RADIATION TERM FOR THE LINE SHAPE
!
!                     ATMOSPHERIC AND ENVIRONMENTAL RESEARCH INC.
!
!      SOURCE OF ORIGINAL ROUTINE:    AFGL LINE-BY-LINE MODEL (FASCOD3)
!
!
! Input variables
   real, dimension(:),intent(in) :: vi
   real, intent(in) :: xkt
   integer,intent(in) :: nvi

! Output variable
  real, dimension(:),intent(out) :: rad

! Local variables
   real :: xvi(nvi), xviokt(nvi),expvkt(nvi)
!
!      Note:  IN THE SMALL XVIOKT REGION 0.5 IS REQUIRED
!
   xvi = vi
   rad = xvi
   xviokt = xvi/xkt
!
   where (xviokt.le.0.01) 
      rad = 0.5*xviokt*xvi
   elsewhere (xviokt.le.10.)
      expvkt = exp(-xviokt)
      rad = xvi*(1-expvkt)/(1.+expvkt)
   endwhere

   myradfn=1
!
   RETURN
!
   end function myradfn
!=======================================================================
!
   subroutine myxint (v1a,v2a,dva,a,afact,vft,dvr3,r3,n1r3,n2r3)
!
!
!     THIS SUBROUTINE INTERPOLATES THE A ARRAY STORED
!     FROM V1A TO V2A IN INCREMENTS OF DVA USING A MULTIPLICATIVE
!     FACTOR AFACT, INTO THE R3 ARRAY FROM LOCATION N1R3 TO N2R3 IN
!     INCREMENTS OF DVR3
!
! Input variables
   real,dimension(:),intent(in) :: a
   double precision,intent(in) :: vft
   real, intent(in) :: v1a,v2a,dva,afact,dvr3
   integer, intent(in) :: n1r3,n2r3
 
! Input/output variables
   real,dimension(:),intent(inout) :: r3

! Local variables
   real :: recdva,p,c,b,b1,b2,conti
   integer :: i,j
   integer :: ilo,ihi
   real :: vi,vj

!
   RECDVA = 1./DVA
   ILO = (V1A+DVA-VFT)/DVR3+1.+ONEMI
   ILO = MAX(ILO,N1R3)
   IHI = (V2A-DVA-VFT)/DVR3+ONEMI
   IHI = MIN(IHI,N2R3)
!
   DO 10 I = ILO, IHI
      VI = VFT+DVR3* REAL(I-1)
      J = (VI-V1A)*RECDVA+ONEPL
      VJ = V1A+DVA* REAL(J-1)
      P = RECDVA*(VI-VJ)
      C = (3.-2.*P)*P*P
      B = 0.5*P*(1.-P)
      B1 = B*(1.-P)
      B2 = B*P 
      CONTI = -A(J-1)*B1+A(J)*(1.-C+B2)+A(J+1)*(C+B1)-A(J+2)*B2
      R3(I) = R3(I)+CONTI*AFACT
10 END DO
!
   RETURN
!
   end subroutine myxint
!=======================================================================
!
   subroutine pre_xint(v1ss,v2ss,v1abs,dvabs,nptabs,ist,lst)
!
!   Sets up needed variables for call to XINT.
!
! Input variables
   double precision,intent(in) :: v1abs
   real, intent(in) :: v1ss,v2ss
   integer, intent(in) :: nptabs
   real, intent(in) :: dvabs

! Output variables
   integer, intent(out) :: ist,lst

! Local variables
   integer :: nbnd_v1c,nbnd_v2c
   real :: v1abs_loc

!   Output variables
!     ist - index of first value to be processed in XINT
!     lst - index of last value to be processed in XINT

   nbnd_v1c =  2 +  (v1ss-v1abs)/dvabs + 1.e-5
   ist = max(1,nbnd_v1c)
   v1abs_loc = v1abs + dvabs * float(ist-1)

   nbnd_v2c = 1 + (v2ss-v1abs)/dvabs + 1.e-5
   lst = min(nptabs,nbnd_v2c)

   return
  
   end subroutine pre_xint
!=======================================================================

end module mt_ckd_h2o
