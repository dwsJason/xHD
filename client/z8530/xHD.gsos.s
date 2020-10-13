*==============================================================================
* xHD serial driver
* By John Brooks 10/28/2015
* Virtual disk drive based on ideas from Terence J. Boldt
*
* Bodged into a GSOS Driver by Jason Andersen 10/10/2020
*
* Note from Jason:
* 	Uses Merlin 1.1.10, and CADIUS

*   This Merlin supports force DP Addressing via <, which is the
*   WDC Standard
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

			dsk		xHD.gsos


*------------------------------------------------------------------------------

; $C022 TBCOLOR		(could use as RAM), 1 byte / must restore, could be ugly
; $C037 DMAREG		; maybe gets trashed during DMA, need to test to see
					; if the CPU can R/W
; $C03E SOUNDADRL	; DOC RAM Address, could change during interrupts
; $C03F SOUNDADRH
; $C040  ; Test this, reserved for expansion

;$C026 = key micro data reg
;$C033 = clock data reg
;$C03A/B = SCC data regs

*------------------------------------------------------------------------------

nullptr		equ		0

; Block Driver ZP Defines

deviceNum	equ		$0
callNum		equ		$2
bufferPtr	equ		$4
requestCount equ	$8
trasnferCount equ	$C
blockNum	equ		$10
blockSize	equ		$14
fstNum		equ		$16
volumeID	equ		$18
cachePriority equ	$1A
cachePointer equ	$1C
dibPointer	equ		$20

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

;
; Status Indicator on the Text Page
;
TxtLight	=		$e00427
;
; Serial Port Addresses
;
IoSccCmdB	=		$C038
IoSccCmdA	=		$C039
IoSccDataB	=		$C03A
IoSccDataA	=		$C03B


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

*------------------------------------------------------------------------------
;
; Possible Error Codes
; $11 Invalid device number
; $23 Device not open
; $2C Invalid byte count
; $2D Invalid block number
; $53 Parameter out of range
; $58 Not a block device
;

Driver_Read mx %00

;sBlockNum   = 3
;sBlockCount = 1

			lda		<blockNum		  ; current block number on the stack
			sta		|HdrBlk			  ; packet header, block #		

			lda		<requestCount+2
			lsr
			tax					      ; number of blocks to transfer

			sep #$20
			mx  %10

			lda		<deviceNum
			asl
			inc		; 3=drive 1, 5=drive2
			sta		|CurCmd

			lda		<bufferPtr+2
			pha
			plb						  ; Current DB is Target for Data

			ldy		<bufferPtr		  ; Y is Address to copy the data into

]readloop	
		    phx						  ; preserve number of blocks to xfer
			jsr		ReadBlock

			plx
			dex
			bne		]readloop

			rep		#$31
			mx		%00

			stz		<transferCount
			lda		<requestCount+2
			sta		<transferCount+2

			; c = 0
			lda		#0
			rtl


*------------------------------------------------------------------------------

Driver_Write mx %00
			lda		#1
			sec
			rtl

*------------------------------------------------------------------------------
;
; Error Codes
; $11 Invalid device number
; $53 Parameter out of range
;
Driver_Status mx %00

			lda		<statusCode
			cmp		#5
			bcs		:errorRange

			asl
			tax

			jmp		(:dispatch,x)

:errorRange
			; c = 1
			lda		#$21	; drvrBadCode
			rtl

:dispatch	da		:GetDeviceStatus
			da		:GetConfigParameters
			da		:GetWaitStatus
			da		:GetFormatOptions
			da		:GetPartitionMap

:GetDeviceStatus

:GetConfigParameters
:GetWaitStatus
			lda		#2
			sta		<transferCount
			stz		<transferCount+2

			lda		#0     				; GetConfigParameters
			sta		[statusListPtr]  	; GetWaitStatus
			; a = 0
			; c = 0
			rtl



:GetFormatOptions
:GetParitionMap
			stz		<transferCount
			stz		<transferCount+2
			lda		#0
			rtl


Driver_Control mx %00
			lda		#1
			sec
			rtl


CmdHdr		;asc		"E"
CurCmd		db		0
HdrBlk		dw		0
HdrChecksum	db		0
HdrCopy		ds		4-1
HdrCopyCksum dw		1
			
*------------------------------------------------------------------------------
; Initialize the Serialport HW
;
; D = $C000
; Preserves Y
; B unknown
;
InitSCC		mx		%10
;			sta		CurCmd			;2=Drive1, 4=Drive2

			lda		#15				;Are 8530 interrupts disabled?
			sta		<IoSccCmdB
			lda		<IoSccCmdB
			beq		:ConfigOK		;If not then SCC is set up by firmware,
									; so reset it
			bit		<$c030
			ldx		#-SccInitLen
:InitSCC	
			lda		>SccInitTblEnd-$100,x
			sta		<IoSccCmdB
			inx
			bne		:InitSCC

:ConfigOK
			rts

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


;			lda		ZpDrvrCmd
;			beq		:DoStatus		;0=status
;			dec
;			beq		ReadBlock		;1=read block
;			dec
;			bne		:NoCmd			;2=write block
;			jmp		WriteBlock
;:DoStatus
;			ldx		#$ff			;TODO - returns 32MB HD regardless of image size
;			txy
;:NoCmd
;			lda		#0				; no error
;			clc
;			rtl


*-------------------------------------------------
; DB = Target Block Address Bank
;  Y = Pointer to Target Block Address
; CurCmd, already 3 = write drive 1, or 5 = write drive 2
; DP = need to preserve
; HdrBlk, already has the 16 bit block number
;
			mx		%10
ReadBlock
			phd						; preserve DP
			pea		#$C000
			pld			            ; DP on IO

			jsr		InitSCC

			; Legacy Support for the TxtLight
			; $$JGA Todo (we could have a "light" on the menu bar)
			lda		>CurCmd
			lsr
			ora		#$30
			sta		>TxtLight

			;ldx		ZpDrvrBlk
			;stx		HdrBlk
			jsr		ClearRx

			phy
			jsr		SendCmd
			ply

			lda		#0		; ZpChecksum

			ldy		#HdrCopy
			ldx		#HdrCopy+5-1
			;stx		ZpReadEnd
			;phk
			;plb

			jsr		ReadBytes
			bcc		ReadError

			cmp		#0		; ZpChecksum
			bne		ReadError
			
			ldx		#2
:ErrChk		lda		>CmdHdr,x
			cmp		>HdrCopy,x
			bne		ReadError
			dex
			bpl		:ErrChk
			

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
			cmp		#0				;Chksum==0?
			bne		ReadError		;Err if bad chksum

			ora		>TxtLight
			sta		>TxtLight

			clc
			pld
			rts

*-------------------------------------------------
			mx		%10
ReadError
			jsr		ClearRx

			;lda		#0
			;tsb		TxtLight

			lda		#P8ErrIoErr
			sec
			pld
			rts


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
			phb

			inc		<$c034 			; Border Color

			lda		#^CmdHdr
			pha
			plb

			ldy		#CmdHdr
			ldx		#HdrChecksum	; X = End Address

			lda		#0   			; Zero out checksum
			jsr		WriteBytes
			sta		|HdrChecksum

			jsr		WriteBytes

			lda		<$c034
			dec
			and		#$0F
			sta		<$c034  		; Border Color Back

			plb
			rts
			
*-------------------------------------------------
;  Checksum in A
;  B in source Bank
;  Y index to source data
;
			mx		%10
WriteBytes
			phx						;End Read
			pha						;Checksum
:WriteByte
			ldx		#$0				;Init timeout
			clc
:Loop
			inx						;P8Timeout++
			bmi		:Exit
			lda		<IoSccCmdB		;Reg 0
			and		#%00100100		;Chk bit 5 (ready to send) & bit 2 (HW handshake)
			eor		#%00100100
			bne		:Loop

			lda		|0,y			;Get byte
			sta		<IoSccDataB		;Tx byte

			eor		1,s				; ZpChecksum
			sta		1,s				; ZpChecksum ;Update cksum
			
			iny						; write index
			cpy		2,s				; EndRead
			bcc		:WriteByte
:Exit
			pla						; checksum in A
			plx
			rts
			
*-------------------------------------------------
*  Return checksum in A
*  Return Byte in X
* 
			mx		%10
ReadOneByte
			pha						;CheckSum
			ldx		#0				;Init Timeout
:Loop
			inx
			bmi		:Exit

			lda		<IoSccCmdB		;Chk reg 0 bit 0
			lsr
			bcc		:Loop

			lda		<IoSccDataB		;Byte received
			tax 	   				;save result to return
			eor		1,s				;checksum
			sta		1,s				;update checksum
:Exit
			pla
			rts

*-------------------------------------------------
			mx		%10
ReadBytes
			phx						;EndRead
			pha						;Checksum
:ReadByte
			ldx		#0				;Init timeout
:Loop
			inx						;P8Timeout++
			bmi		:Exit
			lda		<IoSccCmdB		;Chk reg 0 bit 0
			lsr
			bcc		:Loop

			lda		<IoSccDataB		;Byte received
			sta		|0,y			;Store it
			
			eor		1,s				;<ZpChecksum
			sta		1,s				;<ZpChecksum ;Update cksum
			
			iny
			cpy		2,s				;ZpReadEnd
			bcc		:ReadByte
:Exit		
			pla 					; checksum
			plx 					; EndRead
			rts

*-------------------------------------------------
			mx		%10
ClearRx

:ClearFifo	
			lda		#1
			bit		<IoSccCmdB		;Chk reg 0 bit 0
			beq		:Done

			sta		<IoSccCmdB		;Read reg 1
			lda		#$30			;Chk & Clear overrun
			bit		<IoSccCmdB		;Chk bit 5 for RX OVERRUN
			beq		:NotOverrun
			sta		<IoSccCmdB
			stz		<IoSccCmdB
:NotOverrun
			lda		<IoSccDataB		;Byte received
			bra		:ClearFifo
:Done
			rts

*-------------------------------------------------

