*==============================================================================
* xHD serial driver
* By John Brooks 10/28/2015
* Virtual disk drive based on ideas from Terence J. Boldt
*
* Bodged into a GSOS Driver by Jason Andersen 10/10/2020
*
* Note from Jason:
* 	Uses Merlin 1.1.10, and CADIUS
*
*  See GSOS / Driver Driver Reference Manual
*
*  Brutal Deluxe also as an example Device Driver in their MountIt Project!
* 
*==============================================================================
			lst		off
										h

maxDRIVES	equ		2

			typ		$BB				; DVR -  Apple IIgs Device Driver File
			aux		$0102			; Active + GSOS Driver + Max 2 Device
			rel						; OMF Code

			dsk		xHD.driver


*------------------------------------------------------------------------------

nullptr equ 0

;
; $$JGA TODO, fix these 
;
;ZpPageNum	=		$3a
;ZpChecksum	=		$3b
;ZpReadEnd	=		$3c
;ZpTemp		=		$3e
;
;ZpDrvrCmd	=		$42
;ZpDrvrUnit	=		$43
;ZpDrvrBufPtr =		$44
;ZpDrvrBlk	=		$46
;
;P8ErrIoErr	=		$27
;
;TxtLight	=		$e00427
;
;
;P8CmdQuit	=		$65
;
;P8Mli		=		$BF00
;P8DevCnt	=		$BF31
;P8DevLst	=		$BF32
;
;IoSccCmdB	=		$C038
;IoSccCmdA	=		$C039
;IoSccDataB	=		$C03A

;IoSccDataA	=		$C03B
;
;IoRomIn		=		$C081
;
;RomStrOut	=		$DB3A		;YA=C string

*------------------------------------------------------------------------------

Header		mx %00
			da		FirstDIB-Header
			dw		maxDRIVES
			da		ConfigurationList0-Header
			da		ConfigurationList1-Header

;
; $$JGA TODO - Support Configuration, for now empty
;
ConfigurationList0
			dw		0	; Live Configuration
			dw		0	; Default Configuration

ConfigurationList1
			dw		0	; Live Configuration
			dw		0	; Default Configuration

;
; Device Information Blocks
;
FirstDIB
DIB0
			adrl	DIB1			; Pointer to next DIB
			adrl	DriverEntry
			dw		$00E0			; Speed = SLOW + Block + Read + Write
			adrl	$0000FFFF  		; Blocks on Device
			str		'SCCxHD1'
			dw		$8001			; Slot 1, doesn't need Slot HW
			dw		$0001			; Unit #
			dw		$000D			; Version Development
			dw		$0013			; Device ID = Generic HDD
			dw		$0000			; Head Link
			dw		$0000			; Forward Link
			adrl	nullptr			; ExtendedDIB - User Data Pointer
			dw		$0000			; DIB DevNum

DIB1
			adrl	nullptr			; Pointer to the next DIB
			adrl	DriverEntry
			dw		$00E0			; Speed = SLOW + Block + Read + Write
			adrl	$0000FFFF  		; Blocks on Device
			str		'SCCxHD2'
			dw		$8001			; Slot 1, doesn't need Slot HW
			dw		$0002			; Unit #
			dw		$000D			; Version Development
			dw		$0013			; Device ID = Generic HDD
			dw		$0000			; Head Link
			dw		$0000			; Forward Link
			adrl	nullptr			; ExtendedDIB - User Data Pointer
			dw		$0000			; DIB DevNum

DriverEntry mx %00
			cmp		#JUMP_TABLE_SIZE
			bcs		:error_rtl

			phk
			plb 	; needed so (jmp,x) will load from this bank

			asl
			tax

			jmp		(:dispatch,x)

:dispatch	da		Driver_Startup
			da    	Driver_Open
			da    	Driver_Read
			da		Driver_Write
			da		Driver_Close
			da		Driver_Status
			da		Driver_Control
			da		Driver_Flush
			da		Driver_Shutdown

:error_rtl
			lda 	#32		; Brutal Deluxe Returns this, invalid Driver Call
			rtl

*------------------------------------------------------------------------------

Driver_Startup mx %00
Driver_Open mx %00
Driver_Close mx %00
Driver_Shutdown mx %00
Driver_Flush mx %00
			lda		#0
			clc
			rtl

Driver_Read mx %00
Driver_Write mx %00
Driver_Status mx %00
Driver_Control mx %00


CmdHdr		;asc		"E"
CurCmd		db		0
HdrBlk		dw		0
HdrChecksum	db		0
HdrCopy		ds		4-1
;TempDate	ds		4
HdrCopyCksum dw		1
			
*-------------------------------------------------

E0Driver
			jmp		(GSCmd,x)
GSCmd
			dw		xHdClient

xHdClient
			lda		#2
			bit		ZpDrvrUnit
			bpl		:GotZpDrvrUnit
			asl
:GotZpDrvrUnit
			sta		CurCmd			;2=Drive1, 4=Drive2

			lda		#15				;Are 8530 interrupts disabled?
			sta		IoSccCmdB
			lda		IoSccCmdB
			beq		:ConfigOK		;If not then SCC is set up by firmware, so reset it

			bit		$c030
			ldx		#-SccInitLen
:InitSCC	
			ldal	SccInitTblEnd-$100,x
			sta		IoSccCmdB
			inx
			bne		:InitSCC

:ConfigOK
			lda		ZpDrvrCmd
			beq		:DoStatus		;0=status
			dec
			beq		ReadBlock		;1=read block
			dec
			bne		:NoCmd			;2=write block
			jmp		WriteBlock
:DoStatus
			ldx		#$ff			;TODO - returns 32MB HD regardless of image size
			txy
:NoCmd
			lda		#0				; no error
			clc
			rtl

;230k baud
SccInitTbl
			db		4,	%01000100	; 4: x16 clock, 1 stop, no parity
			db		3,	%11000000	; 3: 8 data bits, auto enables off, Rx off
			db		5,	%01100010	; 5: DTR on, 8 data bits, no break, Tx off, RTS off
			db		11,	%00000000	;11: external clock
			db		14,	%00000000	;14: no loopback
			db		3,	%11000001	; 3: 8 data bits, Rx on
			db		5,	%01101010	; 5: DTR on; Tx on
			db		15,	%00000000	;15: no interrupts
SccInitTblEnd
SccInitLen	=		SccInitTblEnd-SccInitTbl

*-------------------------------------------------
			mx		%11
ReadBlock
			rep		#$10
			xba						;ah=0
			lda		CurCmd
			lsr
			ora		#$30
			stal	TxtLight
			inc		CurCmd			;3=drive1, 5=drive2
			ldx		ZpDrvrBlk
			stx		HdrBlk
			jsr		ClearRx
			jsr		SendCmd
			stz		ZpChecksum

		do	1
			ldy		#HdrCopy
			ldx		#HdrCopy+5-1
;			ldx		#HdrCopy+9
			stx		ZpReadEnd
			jsr		ReadBytes
			bcc		ReadError
			lda		ZpChecksum
			bne		ReadError
			
			ldy		#2
:ErrChk		lda		CmdHdr,y
			cmp		HdrCopy,y
			bne		ReadError
			dey
			bpl		:ErrChk
			
		fin

			rep		#$21
			ldy		ZpDrvrBufPtr
			tya
			adc		#$200
			sta		ZpReadEnd
			lda		#0
			sep		#$20
			jsr		ReadBytes
			bcc		ReadError

			jsr		ReadOneByte		;Read checksum
			bcc		ReadError		;Err if P8Timeout
			lda		ZpChecksum		;Chksum==0?
			bne		ReadError		;Err if bad chksum

			tsb		TxtLight
			sep		#$10
			clc
			rtl

*-------------------------------------------------
			mx		%10
ReadError
			jsr		ClearRx
			lda		#0
			tsb		TxtLight
			sep		#$10
			lda		#P8ErrIoErr
			sec
			rtl


*-------------------------------------------------
			mx		%11
WriteBlock
			rep		#$10
			xba						;ah=0
			lda		#$17
			stal	TxtLight
			ldx		ZpDrvrBlk
			stx		HdrBlk
			jsr		ClearRx
			jsr		SendCmd
			stz		ZpChecksum

			ldy		ZpDrvrBufPtr
			sty		ZpReadEnd
			inc		ZpReadEnd+1
			inc		ZpReadEnd+1		;Send 2x pages = 512 bytes
			jsr		WriteBytes

			sta		ZpPageNum		;Save block checksum

			ldy		#ZpChecksum
			sty		ZpReadEnd
			jsr		WriteBytes

		do	1
			ldy		#HdrCopy
			ldx		#HdrCopy+5-1
;			ldx		#HdrCopy+9
			stx		ZpReadEnd
			jsr		ReadBytes
			bcc		ReadError

			cmp		ZpPageNum		;block ZpChecksum
			bne		ReadError
			
			ldy		#2
:ErrChk		lda		CmdHdr,y
			cmp		HdrCopy,y
			bne		ReadError
			dey
			bpl		:ErrChk
			
		fin
		
			tsb		TxtLight

			sep		#$10
			clc
			rtl

*-------------------------------------------------
			mx		%10
WriteError
			jsr		ClearRx
			lda		#0
			tsb		TxtLight
			sep		#$10
			lda		#P8ErrIoErr
			sec
			rtl

*-------------------------------------------------
			mx		%10
SendCmd
			inc		$c034
			stz		ZpChecksum
		
			ldy		#CmdHdr
			ldx		#HdrChecksum
			stx		ZpReadEnd
			jsr		WriteBytes
			sta		HdrChecksum
			dec		$c034
			;Fall through to send checksum byte
			
*-------------------------------------------------
			mx		%10
WriteBytes
			tsx						;Init timeout
			clc
:Loop
			inx						;P8Timeout++
			bmi		:Exit
			lda		IoSccCmdB		;Reg 0
			and		#%00100100		;Chk bit 5 (ready to send) & bit 2 (HW handshake)
			eor		#%00100100
			bne		:Loop

			lda		0,y				;Get byte
			sta		IoSccDataB		;Tx byte

			eor		ZpChecksum
			sta		ZpChecksum		;Update cksum
			
			iny
			cpy		ZpReadEnd
			bcc		WriteBytes

			rts
			
*-------------------------------------------------
			mx		%10
ReadOneByte
			ldy		#$C07f
			sty		ZpReadEnd
			;fall through to ReadBytes

*-------------------------------------------------
			mx		%10
ReadBytes
:ReadByte
			tsx						;Init timeout
:Loop
			inx						;P8Timeout++
			bmi		:Exit
			lda		IoSccCmdB		;Chk reg 0 bit 0
			lsr
			bcc		:Loop

			lda		IoSccDataB		;Byte received
			sta		0,y				;Store it
			tax						;Save in case this is a 1 byte read
			
			eor		ZpChecksum
			sta		ZpChecksum		;Update cksum
			
			iny
			cpy		ZpReadEnd
			bcc		:ReadByte
			
			txa						;Return last byte read
:Exit		rts

*-------------------------------------------------
			mx		%10
ClearRx

:ClearFifo	
			lda		#1
			bit		IoSccCmdB		;Chk reg 0 bit 0
			beq		:Done

			sta		IoSccCmdB		;Read reg 1
			lda		#$30			;Chk & Clear overrun
			bit		IoSccCmdB		;Chk bit 5 for RX OVERRUN
			beq		:NotOverrun
			sta		IoSccCmdB
			stz		IoSccCmdB
:NotOverrun
			lda		IoSccDataB		;Byte received
			bra		:ClearFifo
:Done
			rts

E0DriverEnd

*-------------------------------------------------

