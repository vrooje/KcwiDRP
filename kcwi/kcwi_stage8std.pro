;
; Copyright (c) 2014, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	KCWI_STAGE8STD
;
; PURPOSE:
;	This procedure uses a standard star observation to derive
;	a calibration of the related object data cubes.
;
; CATEGORY:
;	Data reduction for the Keck Cosmic Web Imager (KCWI).
;
; CALLING SEQUENCE:
;	KCWI_STAGE8STD, Procfname, Pparfname
;
; OPTIONAL INPUTS:
;	Procfname - input proc filename generated by KCWI_PREP
;			defaults to './redux/kcwi.proc'
;	Pparfname - input ppar filename generated by KCWI_PREP
;			defaults to './redux/kcwi.ppar'
;
; KEYWORDS:
;	VERBOSE	- set to verbosity level to override value in ppar file
;	DISPLAY - set to display level to override value in ppar file
;
; OUTPUTS:
;	None
;
; SIDE EFFECTS:
;	Outputs processed files in output directory specified by the
;	KCWI_PPAR struct read in from Pparfname.
;
; PROCEDURE:
;	Reads Pparfname to derive input/output directories and reads the
;	corresponding '*.proc' file in output directory to derive the list
;	of input files and their associated std files.  Each input
;	file is read in and the required calibration is generated and 
;	applied to the observation.
;
; EXAMPLE:
;	Perform stage8std reductions on the images in 'night1' directory and 
;	put results in 'night1/redux':
;
;	KCWI_STAGE8STD,'night1/redux/kcwi.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2014-APR-22	Initial version
;	2014-MAY-13	Include calibration image numbers in headers
;	2014-SEP-23	Added extinction correction
;	2014-SEP-29	Added infrastructure to handle selected processing
;	2017-MAY-24	Changed to proc control file and removed link file
;-
pro kcwi_stage8std,procfname,ppfname,help=help,verbose=verbose, display=display
	;
	; setup
	pre = 'KCWI_STAGE8STD'
	startime=systime(1)
	q = ''	; for queries
	;
	; help request
	if keyword_set(help) then begin
		print,pre+': Info - Usage: '+pre+', Proc_filespec, Ppar_filespec'
		print,pre+': Info - default filespecs usually work (i.e., leave them off)'
		return
	endif
	;
	; get ppar struct
	ppar = kcwi_read_ppar(ppfname)
	;
	; verify ppar
	if kcwi_verify_ppar(ppar,/init) ne 0 then begin
		print,pre+': Error - pipeline parameter file not initialized: ',ppfname
		return
	endif
	;
	; directories
	if kcwi_verify_dirs(ppar,rawdir,reddir,cdir,ddir,/nocreate) ne 0 then begin
		kcwi_print_info,ppar,pre,'Directory error, returning',/error
		return
	endif
	;
	; check keyword overrides
	if n_elements(verbose) eq 1 then $
		ppar.verbose = verbose
	if n_elements(display) eq 1 then $
		ppar.display = display
	;
	; log file
	lgfil = reddir + 'kcwi_stage8std.log'
	filestamp,lgfil,/arch
	openw,ll,lgfil,/get_lun
	ppar.loglun = ll
	printf,ll,'Log file for run of '+pre+' on '+systime(0)
	printf,ll,'DRP Ver: '+kcwi_drp_version()
	printf,ll,'Raw dir: '+rawdir
	printf,ll,'Reduced dir: '+reddir
	printf,ll,'Calib dir: '+cdir
	printf,ll,'Data dir: '+ddir
	printf,ll,'Filespec: '+ppar.filespec
	printf,ll,'Ppar file: '+ppfname
	if ppar.clobber then $
		printf,ll,'Clobbering existing images'
	printf,ll,'Verbosity level   : ',ppar.verbose
	printf,ll,'Plot display level: ',ppar.display
	;
	; read proc file
	kpars = kcwi_read_proc(ppar,procfname,imgnum,count=nproc)
	;
	; gather configuration data on each observation in reddireddir
	kcwi_print_info,ppar,pre,'Number of input images',nproc
	;
	; loop over images
	for i=0,nproc-1 do begin
		;
		; image to process
		;
		; require output from kcwi_stage7dar
		obfil = kcwi_get_imname(kpars[i],imgnum[i],'_icubed',/reduced)
		;
		; check if input file exists
		if file_test(obfil) then begin
			;
			; read configuration
			kcfg = kcwi_read_cfg(obfil)
			;
			; final output file
			ofil = kcwi_get_imname(kpars[i],imgnum[i],'_icubes',/reduced)
			;
			; trim image type
			kcfg.imgtype = strtrim(kcfg.imgtype,2)
			;
			; check if output file exists already
			if kpars[i].clobber eq 1 or not file_test(ofil) then begin
				;
				; print image summary
				kcwi_print_cfgs,kcfg,imsum,/silent
				if strlen(imsum) gt 0 then begin
					for k=0,1 do junk = gettok(imsum,' ')
					imsum = string(i+1,'/',nproc,format='(i3,a1,i3)')+' '+imsum
				endif
				print,""
				print,imsum
				printf,ll,""
				printf,ll,imsum
				flush,ll
				;
				; report input file
				kcwi_print_info,ppar,pre,'input cube',obfil,format='(a,a)'
				;
				; do we have a std file?
				do_std = (1 eq 0)
				if strtrim(kpars[i].masterstd,2) ne '' then begin
					;
					; master std file name
					msfile = kpars[i].masterstd
					;
					; is std file already built?
					if file_test(msfile) then begin
						do_std = (1 eq 1)
						;
						; log that we got it
						kcwi_print_info,ppar,pre,'std file = '+msfile
					endif else begin
						;
						; does input std image exist?
						sinfile = repstr(msfile,'_invsens','_icubed')
						if file_test(sinfile) then begin
							do_std = (1 eq 1)
							kcwi_print_info,ppar,pre,'building std file = '+msfile
						endif else begin
							;
							; log that we haven't got it
							kcwi_print_info,ppar,pre,'std input file not found: '+sinfile,/warning
						endelse
					endelse
				endif
				;
				; let's read in or create master std
				if do_std then begin
					;
					; build master std if necessary
					if not file_test(msfile) then begin
						;
						; get observation info
						scfg = kcwi_read_cfg(sinfile)
						;
						; build master std
						kcwi_make_std,scfg,kpars[i]
					endif
					;
					; read in master calibration (inverse sensitivity)
					mcal = mrdfits(msfile,0,mchdr,/fscale,/silent)
					mcal = reform(mcal[*,1])
					;
					; get dimensions
					mcsz = size(mcal,/dimension)
					;
					; get master std waves
					mcw0 = sxpar(mchdr,'crval1')
					mcdw = sxpar(mchdr,'cdelt1')
					mcwav = mcw0 + findgen(mcsz[0]) * mcdw
					;
					; get master std image number
					msimgno = sxpar(mchdr,'FRAMENO')
					;
					; read in image
					img = mrdfits(obfil,0,hdr,/fscale,/silent)
					;
					; get dimensions
					sz = size(img,/dimension)
					;
					; get object waves
					w0 = sxpar(hdr,'crval3')
					dw = sxpar(hdr,'cd3_3')
					wav = w0 + findgen(sz[2]) * dw
					;
					; resample onto object waves, if needed
					if w0 ne mcw0 or dw ne mcdw or wav[sz[2]-1] ne mcwav[mcsz[0]-1] or $
						sz[2] ne mcsz[0] then begin
						kcwi_print_info,ppar,pre, $
							'wavelengths scales not identical, resampling standard',/warn
						linterp,mcwav,mcal,wav,mscal
					endif else mscal = mcal
					;
					; get exposure time
					expt = sxpar(hdr,'XPOSURE')
					;
					; read variance, mask images
					vfil = repstr(obfil,'_icube','_vcube')
					if file_test(vfil) then begin
						var = mrdfits(vfil,0,varhdr,/fscale,/silent)
					endif else begin
						var = fltarr(sz)
						var[0] = 1.	; give var value range
						varhdr = hdr
						kcwi_print_info,ppar,pre,'variance image not found for: '+obfil,/warning
					endelse
					mfil = repstr(obfil,'_icube','_mcube')
					if file_test(mfil) then begin
						msk = mrdfits(mfil,0,mskhdr,/silent)
					endif else begin
						msk = bytarr(sz)
						msk[0] = 1b	; give mask value range
						mskhdr = hdr
						kcwi_print_info,ppar,pre,'mask image not found for: '+obfil,/warning
					endelse
					;
					; correct extinction
					kcwi_correct_extin,img,hdr,kpars[i]
					;
					; do calibration
					for is=0,sz[0]-1 do begin
						for ix = 0, sz[1]-1 do begin
							img[is,ix,*] = (img[is,ix,*]/expt) * mscal
							;
							; convert variance to flux units (squared)
							var[is,ix,*] = (var[is,ix,*]/expt^2) * mscal^2
						endfor
					endfor
					;
					; update header
					sxaddpar,mskhdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,mskhdr,'STDCOR','T',' std corrected?'
					sxaddpar,mskhdr,'MSFILE',msfile,' master std file applied'
					sxaddpar,mskhdr,'MSIMNO',msimgno,' master std image number'
					sxaddpar,mskhdr,'BUNIT','FLAM',' brightness units'
					;
					; write out flux calibrated mask image
					ofil = kcwi_get_imname(kpars[i],imgnum[i],'_mcubes',/nodir)
					kcwi_write_image,msk,mskhdr,ofil,kpars[i]
					;
					; update header
					sxaddpar,varhdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,varhdr,'STDCOR','T',' std corrected?'
					sxaddpar,varhdr,'MSFILE',msfile,' master std file applied'
					sxaddpar,varhdr,'MSIMNO',msimgno,' master std image number'
					sxaddpar,varhdr,'BUNIT','FLAM',' brightness units'
					;
					; write out flux calibrated variance image
					ofil = kcwi_get_imname(kpars[i],imgnum[i],'_vcubes',/nodir)
					kcwi_write_image,var,varhdr,ofil,kpars[i]
					;
					; update header
					sxaddpar,hdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,hdr,'STDCOR','T',' std corrected?'
					sxaddpar,hdr,'MSFILE',msfile,' master std file applied'
					sxaddpar,hdr,'MSIMNO',msimgno,' master std image number'
					sxaddpar,hdr,'BUNIT','FLAM',' brightness units'
					;
					; write out flux calibrated intensity image
					ofil = kcwi_get_imname(kpars[i],imgnum[i],'_icubes',/nodir)
					kcwi_write_image,img,hdr,ofil,kpars[i]
					;
					; check for nod-and-shuffle sky image
					sfil = repstr(obfil,'_icube','_scube')
					if file_test(sfil) then begin
						sky = mrdfits(sfil,0,skyhdr,/fscale,/silent)
						;
						; correct extinction
						kcwi_correct_extin,sky,skyhdr,kpars[i]
						;
						; do correction
						for is=0,sz[0]-1 do for ix = 0, sz[1]-1 do $
							sky[is,ix,*] = (sky[is,ix,*]/expt) * mscal
						;
						; update header
						sxaddpar,skyhdr,'HISTORY','  '+pre+' '+systime(0)
						sxaddpar,skyhdr,'STDCOR','T',' std corrected?'
						sxaddpar,skyhdr,'MSFILE',msfile,' master std file applied'
						sxaddpar,skyhdr,'MSIMNO',msimgno,' master std image number'
						sxaddpar,skyhdr,'BUNIT','FLAM',' brightness units'
						;
						; write out flux calibrated sky panel image
						ofil = kcwi_get_imname(kpars[i],imgnum[i],'_scubes',/nodir)
						kcwi_write_image,sky,hdr,ofil,kpars[i]
					endif
					;
					; check for nod-and-shuffle obj image
					nfil = repstr(obfil,'_icube','_ocube')
					if file_test(nfil) then begin
						obj = mrdfits(nfil,0,objhdr,/fscale,/silent)
						;
						; correct extinction
						kcwi_correct_extin,obj,objhdr,kpars[i]
						;
						; do correction
						for is=0,sz[0]-1 do for ix = 0, sz[1]-1 do $
							obj[is,ix,*] = (obj[is,ix,*]/expt) * mscal
						;
						; update header
						sxaddpar,objhdr,'HISTORY','  '+pre+' '+systime(0)
						sxaddpar,objhdr,'STDCOR','T',' std corrected?'
						sxaddpar,objhdr,'MSFILE',msfile,' master std file applied'
						sxaddpar,objhdr,'MSIMNO',msimgno,' master std image number'
						sxaddpar,objhdr,'BUNIT','FLAM',' brightness units'
						;
						; write out flux calibrated obj panel image
						ofil = kcwi_get_imname(kpars[i],imgnum[i],'_ocubes',/nodir)
						kcwi_write_image,obj,hdr,ofil,kpars[i]
					endif
					;
					; handle the case when no std frames were taken
				endif else begin
					kcwi_print_info,ppar,pre,'cannot associate with any master std: '+ $
						kcfg.obsfname,/warning
				endelse
			;
			; end check if output file exists already
			endif else begin
				kcwi_print_info,ppar,pre,'file not processed: '+obfil+' type: '+kcfg.imgtype,/warning
				if kpars[i].clobber eq 0 and file_test(ofil) then $
					kcwi_print_info,ppar,pre,'processed file exists already',/warning
			endelse
		;
		; end check if input file exists
		endif else $
			kcwi_print_info,ppar,pre,'input file not found: '+obfil,/info
	endfor	; loop over images
	;
	; report
	eltime = systime(1) - startime
	print,''
	printf,ll,''
	kcwi_print_info,ppar,pre,'run time in seconds',eltime
	kcwi_print_info,ppar,pre,'finished on '+systime(0)
	;
	; close log file
	free_lun,ll
	;
	return
end	; kcwi_stage8std
