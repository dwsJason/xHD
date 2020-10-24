;
; xHD.GSOS -  Merlin32 linker file
;
	dsk xHD.gsos
	typ $bb			; dvt - Apple IIgs Device Driver
	aux $0102		; Active + GSOS Driver + Max 2 device
;	xpl				; Add ExpressLoad
	
*----------------------------------------------	
	asm xHD.gsos.s
	ds 0            ; padding
	knd #$1000      ; kind
	ali None		; alignment
	lna xHD.gsos	; load name
	sna xHD.gsos	; segment name
*----------------------------------------------

