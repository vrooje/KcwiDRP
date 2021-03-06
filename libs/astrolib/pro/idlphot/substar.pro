pro substar,image,x,y,mag,id,psfname,VERBOSE = verbose	;Subtract scaled PSF stars
;+
; NAME:
;	SUBSTAR
; PURPOSE:
;	Subtract a scaled point spread function at specified star position(s).
; EXPLANATION:
;	Part of the IDL-DAOPHOT photometry sequence
;
; CALLING SEQUENCE:
;	SUBSTAR, image, x, y, mag, [ id, psfname, /VERBOSE] 
;
; INPUT-OUTPUT:
;	IMAGE -  On input, IMAGE is the original image array.  A scaled
;		PSF will be subtracted from IMAGE at specified star positions.
;		Make a copy of IMAGE before calling SUBSTAR, if you want to
;		keep a copy of the unsubtracted image array
;
; INPUTS:
;	X -   REAL Vector of X positions found by NSTAR (or FIND)
;	Y -   REAL Vector of Y positions found by NSTAR (or FIND)        
;	MAG - REAL Vector of stellar magnitudes found by NSTAR (or APER)
;		Used to scale the PSF to match intensity at star position.
;		Stars with magnitude values of 0.0 are assumed missing and 
;		ignored in the subtraction.
;
; OPTIONAL INPUTS:
;	ID -  Index vector indicating which stars are to be subtracted.  If
;		omitted, (or set equal to -1), then stars will be subtracted 
;		at all positions specified by the X and Y vectors.
;
;	PSFNAME - Name of the FITS file containing the PSF residuals, as
;		generated by GETPSF.  SUBSTAR will prompt for this parameter
;		if not supplied.      
;
; OPTIONAL INPUT KEYWORD:
;	VERBOSE - If this keyword is set and nonzero, then SUBSTAR will 
;		display the star that it is currently processing      
;
; COMMON BLOCKS:
;	The RINTER common block is used (see RINTER.PRO) to save time in the
;	PSF calculations
;
; PROCEDURES CALLED:
;	DAO_VALUE(), READFITS(), REMOVE, SXOPEN, SXPAR(), SXREAD()
; REVISION HISTORY:
;	Written, W. Landsman                      August, 1988
;	Added VERBOSE keyword                     January, 1992
;	Fix star subtraction near edges, W. Landsman    May, 1996
;	Assume the PSF file is in FITS format  W. Landsman   July, 1997
;	Converted to IDL V5.0   W. Landsman   September 1997
;-
 common rinter,c1,c2,c3,init                  ;Save time in RINTER
 if N_params() LT 4 then begin
    print,'Syntax - SUBSTAR, image, x, y, mag,[ id, psfname, /VERBOSE]'
    return
 endif 

 s = size(image)
 if s[0] NE 2 then $
    message, 'ERROR - Input array (first parameter) must be 2 dimensions'
 npts = N_elements(image)

 if N_elements(psfname) NE 1 then begin
     psfname = ''
     read, 'Enter name of the FITS file containing PSF residuals: ', psfname
 endif

 if N_params() LT 5 then id = indgen( N_elements(x) ) else begin
    if min(id) LT 0 then id = indgen( N_elements(x) )    ;Subtract all stars?
 endelse

 psf = readfits(psfname, hpsf)
 nstar = N_elements(id)            ;Number of stars to subtract
 gauss = sxpar( hpsf, 'GAUSS*' )
 psfmag = sxpar( hpsf, 'PSFMAG' )
 psfrad = sxpar( hpsf, 'PSFRAD' )
 fitrad = sxpar( hpsf, 'FITRAD' ) 
 npsf = sxpar( hpsf, 'NAXIS1' )

 nbox = ( 2*fix( psfrad + 0.5 ) + 1) > ((npsf-7)/2)
 nhalf = (nbox-1)/2
 psfrsq = psfrad^2
 lx = fix( x[id] + 0.5 ) - nhalf
 ly = fix( y[id] + 0.5 ) - nhalf
 smag = mag[id]
 scale = 10^(-0.4*(smag- psfmag))
 xx = x[id] - lx
 yy = y[id] - ly 
 bad = where( (smag EQ 0.0), Nbad)        ;Any stars with missing magnitudes?
 if Nbad GT 0 then begin
	nstar = nstar - Nbad
	remove,bad,lx,ly,xx,yy,scale
 endif
 rsq = fltarr( nbox, nbox)
 boxgen = indgen(nbox)

;     Compute RINTER common block arrays

 p_1 = shift(psf,1,0) & p1 = shift(psf,-1,0) & p2 = shift(psf,-2,0)
 c1 = 0.5*(p1-p_1)
 c2 = 2.*p1 + p_1 - 0.5*(5.*psf + p2)
 c3 = 0.5 *(3.*(psf-p1) + p2 - p_1)
 init = 1

 verbose = keyword_set(VERBOSE)
 cr = string("15b)
 for i = 0L,nstar-1 do begin                                 
   dx = boxgen - xx[i]
   dy = boxgen - yy[i]
   dx2 = dx^2 & dy2 = dy^2
   for j = 0,nbox-1 do rsq[0,j] = dx2 + dy2[j]
   good = where( rsq LT psfrsq)
   xgood = good mod nbox      &  ygood = good/nbox
   dx = dx[xgood]             &  dy = dy[ygood]
   goodbig = ( xgood + lx[i] ) + ( ygood + ly[i] )*s[1]
   bad = where( (goodbig LT 0) or (goodbig GE npts), Nbad)
   if nbad GT 0 then remove,bad,goodbig,dx,dy
   image[goodbig] = image[goodbig] - scale[i] * dao_value( dx,dy,gauss,psf )
   if VERBOSE then  $
             print,f="($,'SUBSTAR: Processing Star',I5,A)",id[i],cr
endfor                                                 
return
end
