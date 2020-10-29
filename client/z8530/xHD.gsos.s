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


maxDRIVES	equ		2
JUMP_TABLE_SIZE equ 9				; GSOS Drive Jump Table Size

			typ		$BB				; DVR -  Apple IIgs Device Driver File
;			aux		$0102			; Active + GSOS Driver + Max 2 Device
			rel						; OMF Code

			dsk		xHD.gsos


*------------------------------------------------------------------------------

; $C022 TBCOLOR		(could use as RAM), 1 byte / must restore, could be ugly
; $C033 = clock data reg  ; seems to work
; $C037 DMAREG		; maybe gets trashed during DMA, need to test to see
					; if the CPU can R/W
; $C03E SOUNDADRL	; DOC RAM Address, could change during interrupts
; $C03F SOUNDADRH

; $C03A/B = SCC data regs (maybe if in right mode)

*------------------------------------------------------------------------------

nullptr		equ		0

; Block Driver ZP Defines

deviceNum	equ		$0
callNum		equ		$2
bufferPtr	equ		$4
requestCount equ	$8
transferCount equ	$C
blockNum	equ		$10
blockSize	equ		$14
fstNum		equ		$16
volumeID	equ		$18
cachePriority equ	$1A
cachePointer equ	$1C
dibPointer	equ		$20

; Driver Status
statusListPtr equ	$4
statusCode equ		$16

;
; $$JGA TODO, fix these 
;
;ZpPageNum	=		$3a
;ZpChecksum	=		$3b
ZpReadEnd	=		$c03e	; use the SOUNDADRL+SOUNDADRH
;ZpTemp		=		$3e
;
;ZpDrvrCmd	=		$42
;ZpDrvrUnit	=		$43
;ZpDrvrBufPtr =		$44
;ZpDrvrBlk	=		$46
;
P8ErrIoErr	=		$27
;

SET_DISKSW EQU $01FC90

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
			da		nullptr		; nullptr ok, if you have no config data
			da		nullptr

*			da		ConfigurationList0-Header
*			da		ConfigurationList1-Header
*
*;
*; $$JGA TODO - Support Configuration, for now empty
*;
*ConfigurationList0
*			dw		0	; Live Configuration
*			dw		0	; Default Configuration
*
*ConfigurationList1
*			dw		0	; Live Configuration
*			dw		0	; Default Configuration

;
; Device Information Blocks
;

devCHAR = $03E0 ; default characteristics
devSLOT = $8001
devVER  = $100D ;  1.0 Development


FirstDIB
DIB0
			adrl	DIB1			; Pointer to next DIB
			adrl	DriverEntry
			dw		devCHAR			; Speed = FAST + Block + Read + Write
			adrl	$0000FFFF  		; Blocks on Device
			str		'SCC.HD1'		; Pro Tip, no lowercase in these strings!
			asc		'        '
			asc		'        '
			asc		'        '
			dw		devSLOT			; Slot 1, doesn't need Slot HW
			dw		$0001			; Unit #
			dw		devVER			; Version Development
			dw		$0013			; Device ID = Generic HDD
			dw		$0000			; Head Link
			dw		$0000			; Forward Link
			adrl	nullptr			; ExtendedDIB - User Data Pointer
			dw		$0000			; DIB DevNum

DIB1
			adrl	nullptr			; Pointer to the next DIB
			adrl	DriverEntry
			dw		devCHAR			; Speed = FAST + Block + Read + Write
			adrl	$0000FFFF  		; Blocks on Device
			str		'SCC.HD2'       ; Pro Tip, no lowercase in these strings! 
			asc		'        '
			asc		'        '
			asc		'        '
			dw		devSLOT			; Slot 1, doesn't need Slot HW
			dw		$0002			; Unit #
			dw		devVER			; Version Development
			dw		$0013			; Device ID = Generic HDD
			dw		$0000			; Head Link
			dw		$0000			; Forward Link
			adrl	nullptr			; ExtendedDIB - User Data Pointer
			dw		$0000			; DIB DevNum

DriverEntry mx %00

;			bra		DriverEntry

			nop
			nop
			nop

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
			; c=1
			lda 	#32		; Brutal Deluxe Returns this, invalid Driver Call
			rtl

*------------------------------------------------------------------------------

Driver_Open mx %00
Driver_Close mx %00
Driver_Shutdown mx %00
Driver_Flush mx %00
			lda		#0
			; c=0
Driver_Startup mx %00
			; A=0
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

			;bra		Driver_Read
			;nop
			;nop

			;stz		<transferCount
			;stz		<transferCount+2
			;lda		#$11
			;sec
			;rtl
;----------------------------------

;sBlockNum   = 3
;sBlockCount = 1

			lda		<blockNum		  ; current block number on the stack
			sta		|HdrBlk			  ; packet header, block #		

			lda		<requestCount+1
			lsr
			tax					      ; number of blocks to transfer

			sep 	#$20
			mx  %10

			ldy		#$30		; UnitNum

			;lda		<deviceNum ; This is GSOS Device num, not what I want
			lda		[dibPointer],y ; volume 1 or 2
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

			bcs		:error

			dex
			bne		]readloop

			rep		#$31
			mx		%00

			lda		<requestCount
			sta		<transferCount
			lda		<requestCount+2
			sta		<transferCount+2

			; c = 0
			lda		#0
			rtl
:error  	
			rep		#$30

			stz		<transferCount
			stz		<transferCount+2

			sec
			lda 	#1
			rtl

*------------------------------------------------------------------------------

Driver_Write mx %00
;			bra		Driver_Write
;			nop
;			nop
			
;			stz		<transferCount
;			stz		<transferCount+2
;			lda		#$11
;			sec
;			rtl
			
;-------------------------------------------------

			lda		<blockNum  			; current block number
			sta		|HdrBlk 			; packet header, block #
			
			lda		<requestCount+1
			lsr
			tax							; number of blocks to transfer
			
			sep		#$20
			mx	%10
			
			ldy		#$30				; UnitNum (DIB Offset)
			lda		[dibPointer],y		; volume 1 or 2
			asl
			; 2 = drive 1, 4 = drive 2
			sta		|CurCmd
			
			lda		<bufferPtr+2
			pha
			plb 		  				; Current DB is Source of Data
			
			ldy		<bufferPtr			; Y is Address to copy from
			
]writeloop
			phx							; preserve num blocks
			
			jsr		WriteBlock
			
			plx
			
			bcs		:error
			
			dex
			bne		]writeloop
			
			rep		#$31
			mx		%00
			
			lda		<requestCount
			sta		<transferCount
			lda		<requestCount+2
			sta		<transferCount+2
			
			; c = 0
			lda		#0
			rtl
:error
			rep		#$30
			
			stz		<transferCount
			stz		<transferCount+2
			
			sec
			lda		#1
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

			; Going to transfer at least 2 bytes
			; $$TODO, double check that at least 2 were requested
			lda		#2
			sta		<transferCount
			stz		<transferCount+2

;			lda		#$0014  	; +Disk in Drive + readonly
			lda		#$0010  	; +Disk in Drive
			sta		[statusListPtr]

			lda		<requestCount
			cmp		#6
			bcc		:doneGetDStatus

			; 6 or more requested, so include blocks count
			lda		#$0006
			sta		<transferCount

			; Copy in the number of blocks
			
			ldy		#2
			lda		#$FFFF
			sta		[statusListPtr],y
			iny
			iny
			lda		#$0000
			sta		[statusListPtr],y

:doneGetDStatus
			; a = 0
			; c = 0
			lda		#0     				; GetConfigParameters
			clc
			rtl

:GetConfigParameters
:GetWaitStatus
			;$$TODO, double check the requestCount 
			lda		#2
			sta		<transferCount
			stz		<transferCount+2
			lda		#0
			sta		[statusListPtr]
			rtl


:GetFormatOptions
:GetPartitionMap
			stz		<transferCount
			stz		<transferCount+2
			; c = 0
			lda		#0
			rtl

*------------------------------------------------------------------------------

Driver_Control mx %00

			lda		#$21
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
			ldx		#0
:InitSCC	
			lda		>SccInitTbl,x
			sta		<IoSccCmdB
			inx
			cpx		#SccInitLen
			bne		:InitSCC

:ConfigOK
			rts

;230k baud
SccInitTbl
			db		4,	%01000100	; 4: x16 clock, 1 stop, no parity, 230400
; Back of the envelope math suggests 1Mhz is not fast enough for these speeds
;			db		4,	%10000100	; 4: x32 clock, 1 stop, no parity, 460800
;			db		4,	%11000100	; 4: x64 clock, 1 stop, no parity, 921600
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
; CurCmd, already 3 = read drive 1, or 5 = read drive 2
; DP = need to preserve
; HdrBlk, already has the 16 bit block number
;
			mx		%10
ReadBlock
			phd						; preserve DP
			php
			sei

			pea		#$C000
			pld			            ; DP on IO

			jsr		InitSCC

			; Legacy Support for the TxtLight
			; $$JGA Todo (we could have a "light" on the menu bar)
			lda		>CurCmd
			lsr
			ora		#$30
			sta		>TxtLight

			;ldx		ZpDrvrBlk  ; better already be in there
			;stx		HdrBlk
			jsr		ClearRx

			phy
			jsr		SendCmd

			lda		#0		; ZpChecksum

			ldy		#HdrCopy
			ldx		#HdrCopy+5-1

			phb
			phk
			plb

			jsr		ReadBytes

			plb
			ply

			bcc		ReadError0

			cmp		#0		; ZpChecksum
			bne		ReadError1
			
			ldx		#2
:ErrChk		lda		>CmdHdr,x
			cmp		>HdrCopy,x
			bne		ReadError2
			dex
			bpl		:ErrChk
			
			rep		#$21
			mx		%00
			;ldy		ZpDrvrBufPtr
			tya
			adc		#$200
			tax		;sta  	<ZpReadEnd
			lda		#0
			sep		#$20
			mx		%10
			jsr		ReadBytes_SpanBank
			bcc		ReadError3

			jsr		ReadOneByte		;Read checksum
			bcc		ReadError4		;Err if P8Timeout
			cmp		#0				;Chksum==0?
			bne		ReadError5		;Err if bad chksum

			ora		>TxtLight
			sta		>TxtLight

			plp
			pld
			clc
			rts

*-------------------------------------------------
ReadError0  mx		%10
			jsr		ClearRx

			lda		#0
			sta  	<$C034

			;lda	#P8ErrIoErr
			plp
			pld
			sec
			rts

ReadError1	mx		%10
			jsr		ClearRx

			lda		#1
			sta  	<$C034

			;lda	#P8ErrIoErr
			plp
			pld
			sec
			rts

ReadError2  mx		%10
			jsr		ClearRx

			lda		#2
			sta  	<$C034

			;lda	#P8ErrIoErr
			plp
			pld
			sec
			rts

ReadError3	mx		%10
			jsr		ClearRx

			lda		#3
			sta  	<$C034

			;lda	#P8ErrIoErr
			plp
			pld
			sec
			rts

ReadError4  mx		%10
			jsr		ClearRx

			lda		#4
			sta  	<$C034

			;lda	#P8ErrIoErr
			plp
			pld
			sec
			rts

ReadError5	mx		%10
			jsr		ClearRx

			lda		#5
			sta  	<$C034

			;lda	#P8ErrIoErr
			plp
			pld
			sec
			rts





*-------------------------------------------------
; DB = Target Block Address Bank
;  Y = Pointer to Target Block Address
; CurCmd, already 2 = write drive 1, or 4 = write drive 2
; DP = need to preserve
; HdrBlk, already has the 16 bit block number
;
			mx		%10
WriteBlock
			phd 		  			; preserve DP
			php
			sei
			
			pea		#$C000
			pld						; DP onto IO

			jsr		InitSCC

			lda		#$17
			sta		>TxtLight

			; This better be setup before call
			;ldx		ZpDrvrBlk
			;stx		|HdrBlk

			jsr		ClearRx
			
			phy
			jsr		SendCmd

			rep		#$31
			mx		%00
			ply
			tya
			adc		#$200			; End of Block
			tax
			sep		#$20
			mx		%10

			lda 	#0				;stz ZpChecksum
			jsr		WriteBytes_SpanBank

			phy
			phb
			pha		; Block Checksum
			
			; A = checksum
			; send checksum
			jsr		WriteOneByte
			
			phk
			plb
			
			ldy		#HdrCopy		; start
			ldx		#HdrCopy+5-1	; end
			lda		#0  			; crc
			
			jsr		ReadBytes
			bcs		:sofarsogood
:err			
			pla
			plb
			ply
			bra		WriteError

:sofarsogood
			dey
			lda		|0,y
			cmp		1,s
			bne		:err

			ldy		#2
:ErrChk		lda		|CmdHdr,y
			cmp		|HdrCopy,y
			bne		:err   											    
			dey
			bpl		:ErrChk
		
			sta		>TxtLight
			
			pla 	; block checksum
			plb 	; data bank
			ply		; read address	

			plp 	; restore interrupt status
			pld 	; restore D Page
			clc 	; c=0, no error
			rts

*-------------------------------------------------
			mx		%10
WriteError
			jsr		ClearRx
;			lda		#0
;			tsb		TxtLight
;			sep		#$10
;			lda		#P8ErrIoErr
			plp
			pld
			sec
			rts

*-------------------------------------------------
			mx		%10
SendCmd
			phb

			inc		<$c034 			; Border Color

			;#^CmdHdr
			phk
			plb

			ldy		#CmdHdr
			ldx		#HdrChecksum	; X = End Address

			lda		#0   			; Zero out checksum
			jsr		WriteBytes
			sta		|HdrChecksum

			jsr		WriteBytes   	; writes just 1 more byte, the cksum

			lda		<$c034
			dec
			and		#$0F
			sta		<$c034  		; Border Color Back

			plb
			rts
			
*-------------------------------------------------
*  Return A in A
* 
			mx		%10
WriteOneByte
			pha						;Checksum
			clc
:WriteByte
			ldx		#$0				;Init timeout
:Loop
			inx						;P8Timeout++
			beq		:Exit
			lda		<IoSccCmdB		;Reg 0
			and		#%00100100		;Chk bit 5 (ready to send) & bit 2 (HW handshake)
			eor		#%00100100
			bne		:Loop

			pla						;Get byte
			sta		<IoSccDataB		;Tx byte
			
			sec
			rts
:Exit
			pla
			rts

			
*-------------------------------------------------
;  Checksum in A
;  B in source Bank
;  Y index to source data
;  X index to end of data
;
			mx		%10
WriteBytes
			stx		<ZpReadEnd		;End Read
			pha						;Checksum
			clc
:WriteByte
			ldx		#$0				;Init timeout
:Loop
			inx						;P8Timeout++
			beq		:Exit
			lda		<IoSccCmdB		;Reg 0
			and		#%00100100		;Chk bit 5 (ready to send) & bit 2 (HW handshake)
			eor		#%00100100
			bne		:Loop

			lda		|0,y			;Get byte
			sta		<IoSccDataB		;Tx byte

			eor		1,s				; ZpChecksum
			sta		1,s				; ZpChecksum ;Update cksum
			
			iny						; write index

			cpy		<ZpReadEnd		; EndRead
			bcc		:WriteByte
:Exit
			pla						; checksum in A
			ldx		<ZpReadEnd
			rts

*-------------------------------------------------
;  Checksum in A
;  B in source Bank
;  Y index to source data
;  X index to end of data
;
			mx		%10
WriteBytes_SpanBank
			stx		<ZpReadEnd		;End Read
			pha						;Checksum
:WriteByte
			clc
			ldx		#$0				;Init timeout
:Loop
			inx						;P8Timeout++
			beq		:Exit
			lda		<IoSccCmdB		;Reg 0
			and		#%00100100		;Chk bit 5 (ready to send) & bit 2 (HW handshake)
			eor		#%00100100
			bne		:Loop

			lda		|0,y			;Get byte
			sta		<IoSccDataB		;Tx byte

			eor		1,s				; ZpChecksum
			sta		1,s				; ZpChecksum ;Update cksum
			
			iny						; write index
			bne		:NoWrap

			; Data Bank Change
			phb 	; 3
			pla		; 4
			inc		; 2
			pha 	; 3
			plb 	; 4

:NoWrap
			cpy		<ZpReadEnd		; EndRead
			bne		:WriteByte
			sec
:Exit
			pla						; checksum in A
			ldx		<ZpReadEnd
			rts
			
*-------------------------------------------------
*  Return checksum in A
*  Return Byte in X
* 
			mx		%10
ReadOneByte
			pha						;CheckSum
			clc

			ldx		#0				;Init Timeout
:Loop
			inx
			beq		:Exit

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
			stx		<ZpReadEnd		;EndRead
			pha						;Checksum
			clc
:ReadByte
			ldx		#0				;Init timeout
:Loop
			inx						;P8Timeout++
			beq		:Exit
			lda		<IoSccCmdB		;Chk reg 0 bit 0
			lsr
			bcc		:Loop

			lda		<IoSccDataB		;Byte received
			sta		|0,y			;Store it
			
			eor		1,s				;<ZpChecksum
			sta		1,s				;<ZpChecksum ;Update cksum
			
			iny
			cpy		<ZpReadEnd
			bcc		:ReadByte
:Exit		
			pla 					; checksum
			ldx		<ZpReadEnd		; EndRead
			rts

*-------------------------------------------------
			mx		%10
ReadBytes_SpanBank
			stx		<ZpReadEnd		;EndRead
			pha						;Checksum
:ReadByte
			clc
			ldx		#0				;Init timeout
:Loop
			inx						;P8Timeout++
			beq		:Exit
			lda		<IoSccCmdB		;Chk reg 0 bit 0
			lsr
			bcc		:Loop

			lda		<IoSccDataB		;Byte received
			sta		|0,y			;Store it
			
			eor		1,s				;<ZpChecksum
			sta		1,s				;<ZpChecksum ;Update cksum
			
			iny
			bne		:NoWrap

			; Data Bank Change
			phb
			pla
			inc
			pha
			plb

:NoWrap
			cpy		<ZpReadEnd
			bne		:ReadByte
			sec
:Exit		
			pla 					; checksum
			ldx		<ZpReadEnd		; EndRead
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

