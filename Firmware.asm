;===============================================================================
;     _                                            _____                
;    / \   _ __  _ __   ___  _   _        __ _    |_   _| __ ___  _ __  
;   / _ \ | '_ \| '_ \ / _ \| | | |_____ / _` |_____| || '__/ _ \| '_ \ 
;  / ___ \| | | | | | | (_) | |_| |_____| (_| |_____| || | | (_) | | | |
; /_/   \_\_| |_|_| |_|\___/ \__, |      \__,_|     |_||_|  \___/|_| |_|
;                            |___/                                      
; An Annoy-a-tron
;-------------------------------------------------------------------------------
; Copyright (C)2012-2019 Andrew John Jacobs
; All rights reserved.
;
; This work is made available under the terms of the Creative Commons
; Zero Universal (1.0) license. Open the following URL to see the
; details.
;
; http://creativecommons.org/publicdomain/zero/1.0/
;===============================================================================
; Revision History:
;
; 2012-06-03 Initial version
;-------------------------------------------------------------------------------

                errorlevel -302
                errorlevel -312

;===============================================================================
; Fuse Configuration
;-------------------------------------------------------------------------------

                ifdef   __12F683
                include P12F683.inc

CONFIG_STD      equ     _FCMEN_OFF & _IESO_OFF & _BOREN_OFF & _MCLRE_ON & _INTOSCIO & _WDT_OFF
                ifdef   __DEBUG
CONFIG_BUILD    equ     _CPD_OFF & _CP_OFF & _PWRTE_OFF
                else
CONFIG_BUILD    equ     _CPD_ON & _CP_ON & _PWRTE_ON
                endif

                endif

                __config CONFIG_STD & CONFIG_BUILD

;===============================================================================
; Hardware Configuration
;-------------------------------------------------------------------------------

OSC             equ     .4000000

TMR0_HZ         equ     .100
TMR0_PRESCALE   equ     .64

TMR0_INCREMENT  equ     OSC / (.4 * TMR0_PRESCALE * TMR0_HZ)

                if      TMR0_INCREMENT > .255
                error   "TMR0 increment is bigger than 8-bits"
                endif

;===============================================================================
; Data Areas
;-------------------------------------------------------------------------------

                udata_shr

TICKS           res     .1                      ; 100Hz tick counter

VERSION         res     .1                      ; Data version number
OFFSET          res     .1                      ; Next write offset

LFSR            res     .2                      ; Current LFSR value

BEEPS           res     .1                      ; Number of beeps
SLEEPS          res     .1                      ; Number of sleep periods

SCRATCH         res     .1

;===============================================================================
; Power On Reset
;-------------------------------------------------------------------------------

.ResetVector    code    h'000'

PowerOnReset:
                banksel GPIO
                clrf    GPIO                    ; Set all pins low
                movlw   b'00000111'
;                         -----111              ; Disable comparators
                movwf   CMCON0
                banksel TRISIO
                clrf    ANSEL                   ; Disable analog features
                clrf    TRISIO                  ; Make all pins outputs

;-------------------------------------------------------------------------------

                clrf    VERSION                 ; Initialise randomise values
                clrf    LFSR+.0
                clrf    LFSR+.1
                clrw
FindLast:
                movwf   OFFSET 
                call    EepromSetAddr           ; Set offset of next data block
                call    EepromRead              ; Read the version bytes
                movwf   SCRATCH
                call    EepromRead
                xorlw   h'ff'
                xorwf   SCRATCH,W               ; And see if they are valid              
                btfss   STATUS,Z
                goto    NoMoreData              

                movf    OFFSET,W                ; Is this the first entry?
                btfsc   STATUS,Z
                goto    SaveData                ; Yes, save as best so far

                incf    VERSION,W               ; Matches expected version?
                xorwf   SCRATCH,W
                btfss   STATUS,Z
                goto    NoMoreData              ; No, last entry was the last
                
SaveData:
                movf    SCRATCH,W               ; Save the version number
                movwf   VERSION
                call    EepromRead              ; And read the LFSR state
                movwf   LFSR+.0
                call    EepromRead
                movwf   LFSR+.1

                movf    OFFSET,W                ; Try the next block
                addlw   .4
                goto    FindLast

NoMoreData:
                movf    LFSR+.0,W               ; Is the initial LFSR value
                iorwf   LFSR+.1,W               ; .. zero?
                btfsc   STATUS,Z
                incf    LFSR+.0,F               ; Yes, force a one bit

                call    Shift                   ; Generate the next value

                movf    OFFSET,W                ; Set offset to next block
                call    EepromSetAddr
                incf    VERSION,W               ; Write version header
                movwf   VERSION
                call    EepromWrite
                comf    VERSION,W
                call    EepromWrite
                movf    LFSR+.0,W               ; Followed by LFSR value
                call    EepromWrite
                movf    LFSR+.1,W
                call    EepromWrite

;===============================================================================
; Main Task
;-------------------------------------------------------------------------------

MainTask:
                banksel OPTION_REG              ; Set prescaler for TMR0
                movlw   b'10000101'
;                         1-------              ; Pullups not enabled
;                         -x------              ; Interrupt edge select
;                         --0-----              ; TMR0 source internal
;                         ---x----              ; TMR0 source edge
;                         ----0---              ; Prescaler assigned to TMR0
;                         -----101              ; Prescaler /64
                movwf   OPTION_REG

                call    Random                  ; Generate next random number

                movf    LFSR+.0,W               ; Extract the beep count
                andlw   h'03'
                movwf   BEEPS
                incf    BEEPS,F

                movf    LFSR+.1,W               ; Extract the sleep count
                andlw   h'1f'
                movwf   SLEEPS
                incf    SLEEPS,F

Beep:
                banksel GPIO                    ; Generate 1-4 short beeps
                bsf     GPIO,.2
                call    Delay
                bcf     GPIO,.2
                call    Delay
                decfsz  BEEPS,F
                goto    Beep

;-------------------------------------------------------------------------------

                clrwdt
                banksel OPTION_REG              ; Set prescaler for WDT
                movlw   b'10001111'
;                         1-------              ; Pullups not enabled
;                         -x------              ; Interrupt edge select
;                         --0-----              ; TMR0 source internal
;                         ---x----              ; TMR0 source edge
;                         ----1---              ; Prescaler assigned to WDT
;                         -----111              ; Prescaler /128
                movwf   OPTION_REG

                banksel WDTCON                  ; Configure and start watchdog
                movlw   b'00010001'
;                         ---1000-              ; /8192
                movwf   WDTCON
                clrwdt
                bsf     WDTCON,SWDTEN

Snore:
                sleep                           ; Sleep for 1-32 WDT periods
                nop
                nop
                clrwdt
                decfsz  SLEEPS,F
                goto    Snore

                bcf     WDTCON,SWDTEN           ; Disable watchdog

                goto    MainTask                ; Then do it all again

;-------------------------------------------------------------------------------

Delay:
                movlw   .25                     ; Set tick count for 25 periods
                movwf   TICKS
                banksel TMR0
DelayReset:
                movlw   low -TMR0_INCREMENT     ; Reset TMR0 for 1/100sec
                movwf   TMR0
DelayWait:
                movf    TMR0,W                  ; Wait for period to elapse
                btfss   STATUS,Z
                goto    DelayWait
                decfsz  TICKS,F                 ; Repeat for each tick
                goto    DelayReset
                return                          ; Done

;-------------------------------------------------------------------------------

Random:
                call    $+.1                    ; Shift the LFSR by 8 bits
                call    $+.1
                call    $+.1

Shift:
                bcf     STATUS,C                ; Shift the LFSR one bit
                rrf     LFSR+.1,F
                rrf     LFSR+.0,F
                btfss   STATUS,C
                return
                movlw   h'b4'                   ; And XOR back it dropped bits
                xorwf   LFSR+.1,F
                return

;===============================================================================
; EEPROM Access Routines
;-------------------------------------------------------------------------------

; Set the EEPROM memory address in WREG as the address for the next EEPROM read
; or write operation.

EepromSetAddr:
                banksel EEADR
                movwf   EEADR                   ; Set target EEPROM address
                return

; Trigger a read from the EEPROM memory and returns the value in WREG. The
; address is moved on by one ready to read the following byte.

EepromRead:
                banksel EECON1
                bsf     EECON1,RD               ; Trigger an EEPROM read
                incf    EEADR,F                 ; Bump address by one
                movf    EEDATA,W                ; And fetch the recovered data
                return

; Write the value in WREG to the current target address and then bump the
; address by one.

EepromWrite:
                banksel EEDAT                   ; Save the data byte to write
                movwf   EEDAT
                BSF     EECON1,WREN             ; Enable writing to EEPROM
                MOVLW   h'55'                   ; Perform unlock sequence
                MOVWF   EECON2
                MOVLW   h'AA'
                MOVWF   EECON2
                BSF     EECON1,WR               ; Start a data write
                BCF     EECON1,WREN
WriteWait:
                btfsc   EECON1,WR               ; Wait for write to complete
                goto    WriteWait
                incf    EEADR,F                 ; Bump address by one
                return

                end