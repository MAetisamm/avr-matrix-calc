.include "m328pdef.inc"

; register aliases
.def tmp      = r16
.def tmp2     = r17
.def key      = r18
.def bit_ctr  = r19
.def data     = r20
.def col_idx  = r21
.def row_ctr  = r22

; SRAM layout 
.dseg
.org 0x0100
display_buffer:   .byte 16	; each byte for each slot
current_pos:      .byte 1
key_pressed_flag: .byte 1
debounce_timer:   .byte 1
row_timer:        .byte 1
row_counter:      .byte 1

.org 0x0120
num_stack:        .byte 32
op_stack:         .byte 8
num_sp:           .byte 1
op_sp:            .byte 1
accum_b0:         .byte	1	; 32-bit accumulator, LSB first
accum_b1:         .byte 1
accum_b2:         .byte 1
accum_b3:         .byte 1
accum_nonzero:    .byte 1
incoming_op:      .byte 1

.org 0x0160
digit_buf:        .byte 12          ; scratch for NUM_TO_DISPLAY digit reversal

; reset / interrupt vectors
.cseg
.org 0x0000
    rjmp MAIN_RESET

.org 0x001C
    rjmp TIMER_TICK

; initialisation
.org 0x0034
MAIN_RESET:
    ldi  tmp, high(RAMEND)
    out  SPH, tmp
    ldi  tmp, low(RAMEND)
    out  SPL, tmp
    clr  r1

    ldi  tmp, (1<<PB3)|(1<<PB4)|(1<<PB5)
    out  DDRB, tmp
    sbi  PORTB, PB2
    sbi  PORTB, PB4

    ldi  tmp, 0xF0
    out  DDRD, tmp
    ldi  tmp, 0xFF
    out  PORTD, tmp

    ldi  tmp, (1<<WGM01)
    out  TCCR0A, tmp
    ldi  tmp, (1<<CS01)|(1<<CS00)
    out  TCCR0B, tmp
    ldi  tmp, 249
    out  OCR0A, tmp
    ldi  tmp, (1<<OCIE0A)
    sts  TIMSK0, tmp

    rcall CLEAR_DISPLAY_BUFFER
    clr   tmp
    sts   current_pos,      tmp
    sts   key_pressed_flag, tmp
    sts   debounce_timer,   tmp
    sts   row_timer,        tmp
    sts   row_counter,      tmp
    rcall CALC_INIT
    sei

MAIN_LOOP:
	; if PB2 is pressed clear the display
    sbis PINB, PB2
    rcall FULL_CLEAR

    rcall SCAN_KEYBOARD

    tst  key
    breq NO_KEY_PRESSED

    lds  tmp, key_pressed_flag
    tst  tmp
    brne MAIN_LOOP

    lds  tmp, debounce_timer
    tst  tmp
    brne MAIN_LOOP

    ldi  tmp, 1
    sts  key_pressed_flag, tmp
    rcall PROCESS_KEY
    rjmp MAIN_LOOP

NO_KEY_PRESSED:
    clr  tmp
    sts  key_pressed_flag, tmp
    ldi  tmp, 20
    sts  debounce_timer, tmp
    rjmp MAIN_LOOP

; =========================================================
; PROCESS_KEY
; This checks which key is pressed.
;
; It decides if the key is:
; number, +, -, *, /, %, or =
; =========================================================
PROCESS_KEY:
    cpi  key, 13
    breq PK_MOD

    cpi  key, 15
    breq PK_EQUALS

    cpi  key, 4
    breq PK_PLUS

    cpi  key, 8
    breq PK_MINUS

    cpi  key, 12
    breq PK_MUL

    cpi  key, 16
    breq PK_DIV

    rcall KEY_TO_DIGIT
    rcall PROCESS_DIGIT
    ret
PK_MOD:
    ldi  tmp, 16
    rcall PROCESS_OPERATOR
    ret

PK_EQUALS:
    rcall PROCESS_EQUALS
    ret

PK_PLUS:
    ldi  tmp, 4
    rcall PROCESS_OPERATOR
    ret

PK_MINUS:
    ldi  tmp, 8
    rcall PROCESS_OPERATOR
    ret

PK_MUL:
    ldi  tmp, 12
    rcall PROCESS_OPERATOR
    ret

PK_DIV:
    ldi  tmp, 14
    rcall PROCESS_OPERATOR
    ret

; =========================================================
; KEY_TO_DIGIT
; This converts keypad key value into normal digit.
;
; Example:
; keypad key becomes digit 0 to 9.
; =========================================================
KEY_TO_DIGIT:
    cpi  key, 14	;check if is 0 is pressed
    brne KTD_NOT14
    ldi  tmp, 0
    ret

KTD_NOT14:
    cpi  key, 4
    brlt KTD_LOW	;check if <4 is pressed
    cpi  key, 8
    brlt KTD_MID	;check if <7 is pressed
    mov  tmp, key

    subi tmp, 2		;check if <=9 is pressed                             
					; key 9  becomes digit 7
                    ; key 10 becomes digit 8
                    ; key 11 becomes digit 9
    ret
KTD_LOW:
	;move number as it is
    mov  tmp, key
    ret
KTD_MID:
    mov  tmp, key
	; subtract 1
	; key 5 becomes digit 4
	; key 6 becomes digit 5
	; key 7 becomes digit 6
    dec  tmp
    ret

; =========================================================
; PROCESS_DIGIT
; This runs when user presses a number.
; It builds multi-digit numbers.
;
; Example:
; press 1 then 2 then 3
; calculator makes 123.
;
; Formula:
; number = number * 10 + new digit
; =========================================================
PROCESS_DIGIT:
    push tmp

	;load the 
    lds  r24, accum_b0
    lds  r25, accum_b1
    lds  r26, accum_b2
    lds  r27, accum_b3

    rcall MUL32_BY_10           ; r24:r25:r26:r27 = accum × 10

    pop  tmp                    ; restore digit
    clr  tmp2
    add  r24, tmp               ; add digit into low byte
    adc  r25, tmp2              ; propagate carry
    adc  r26, tmp2
    adc  r27, tmp2

    ; store all 4 bytes back
    sts  accum_b0, r24
    sts  accum_b1, r25
    sts  accum_b2, r26
    sts  accum_b3, r27

    ldi  tmp2, 1
    sts  accum_nonzero, tmp2	; tell program that number is entered

    rcall KEY_TO_DIGIT
    rcall DIGIT_TO_SLOT
    rcall DISP_WRITE_SLOT
    ret

; =========================================================
; MUL32_BY_10
; This multiplies current number by 10.
;
; It uses:
; number * 10 = number * 8 + number * 2
;
; Shifting left is used for multiplication.
; =========================================================
MUL32_BY_10:
    push r2
    push r3
    push r4
    push r5

    ; ?? compute (input × 8) and save in r2:r3:r4:r5 ??
    ; copy input to scratch
    mov  r2, r24
    mov  r3, r25
    mov  r4, r26
    mov  r5, r27

    lsl  r2		; shift left once, multiplied by 2
    rol  r3
    rol  r4
    rol  r5

    lsl  r2		; shift left again, multiplied by 4
    rol  r3
    rol  r4
    rol  r5

    lsl  r2		;shift left again, multiplied by 8
    rol  r3
    rol  r4
    rol  r5

    lsl  r24	; shift left original number, multiplied by 2
    rol  r25
    rol  r26
    rol  r27

    add  r24, r2	;byte 0: add number*2 + number*8
    adc  r25, r3
    adc  r26, r4
    adc  r27, r5

    pop  r5
    pop  r4
    pop  r3
    pop  r2
    ret

; =========================================================
; DIGIT_TO_SLOT
; This converts digit into display code.
;
; Display uses character codes, not direct numbers.
; =========================================================
DIGIT_TO_SLOT:
    cpi  tmp, 0
    breq DTS_0
    cpi  tmp, 4
    brlt DTS_1_3
    cpi  tmp, 7
    brlt DTS_4_6
    subi tmp, -2
    ret
DTS_0:
    ldi  tmp, 13	; digit 0 uses display code 13
    ret
DTS_1_3:
    ret				; digit 1,2,3 already correct
DTS_4_6:
    inc  tmp		; digit 4,5,6 become 5,6,7
    ret

; =========================================================
; GET_PREC
; This gives priority to operators.
;
; + and - have priority 1.
; *, /, % have priority 2.
;
; Higher priority is solved first.
; =========================================================
GET_PREC:
    cpi  tmp, 12
    breq GP_HIGH	; set the priority 2 if is x,/,%
    cpi  tmp, 14
    breq GP_HIGH
    cpi  tmp, 16
    breq GP_HIGH
    ldi  r23, 1		; else the priority will be 1 for +,-
    ret
GP_HIGH:
    ldi  r23, 2
    ret

; =========================================================
; PROCESS_OPERATOR
; This runs when user presses an operator.
;
; It stores the typed number.
; Then it checks operator priority.
;
; This is where shunting-yard logic is used.
; =========================================================
PROCESS_OPERATOR:
    push tmp
    lds  r23, accum_nonzero ; check if user typed a number
    tst  r23
    breq PO_SKIP_PUSH		; if no number typed, skip pushing number

	; load current number 
    lds  r24, accum_b0
    lds  r25, accum_b1
    lds  r26, accum_b2
    lds  r27, accum_b3
    rcall PUSH_NUM

    clr  tmp2
	; clear accumulator byte 
    sts  accum_b0,      tmp2
    sts  accum_b1,      tmp2
    sts  accum_b2,      tmp2
    sts  accum_b3,      tmp2
    sts  accum_nonzero, tmp2

PO_SKIP_PUSH:
    pop  tmp				; get incoming operator back
    mov  r22, tmp           ; new incoming operator

PO_LOOP:
    lds  tmp2, op_sp		; load operator stack pointer
    tst  tmp2				; check if stack is empty
    breq PO_DONE			; if empty, push incoming operator

    dec  tmp2
    ldi  XL, low(op_stack)
    ldi  XH, high(op_stack)
    add  XL, tmp2			; move X pointer to top operator address
    adc  XH, r1				; add carry to high byte, r1 is zero

    ld   tmp, X				; top operator from stack

    ; Get precedence of top operator
	rcall GET_PREC
    mov  r29, r23           ; precedence

    ; Get precedence of incoming operator
    mov  tmp, r22
    rcall GET_PREC

    cp   r29, r23			;compare old priority with new priority
    brlo PO_DONE			;if old priority < new priority, do not solve old one

    rcall POP_OP_SLOT		;else pop old operator from operator stack
    mov  r28, tmp           ; r28 = operator to apply

    rcall POP_NUM           ; right operand -> r24:r25:r26:r27
    push r27
    push r26
    push r25
    push r24

    rcall POP_NUM           ; left operand -> r24:r25:r26:r27

    pop  r30                ; right byte0
    pop  r31                ; right byte1
    pop  r8                 ; right byte2
    pop  r9                 ; right byte3

    push r22                ; save incoming operator
    rcall APPLY_OP			; calculate left operator right
    pop  r22                ; restore incoming operator

    rcall PUSH_NUM          ; push calculation result back to number stack
    rjmp PO_LOOP			; repeat, maybe more old operators need solving

PO_DONE:
    ; Push incoming operator to operator stack
    mov  tmp, r22
    rcall PUSH_OP_SLOT		; push operator into op_stack

    rcall DISP_WRITE_SLOT	; write operator to display buffer
    ret

; =========================================================
; APPLY_OP
; This performs the selected operation.
;
; It can do:
; addition, subtraction, multiplication,
; division, or modulo.
; =========================================================
APPLY_OP:
    push tmp
    mov  tmp, r28			;r28 -> operator to apply
    rcall GET_OP_CODE		; convert operator to simple code in r23
    pop  tmp
	; check which operation to apply: 0->'+', 1->'-', 2->'x', 3->'/',else->'%'
    tst  r23
    breq AO_ADD
    cpi  r23, 1
    breq AO_SUB
    cpi  r23, 2
    breq AO_MUL
    cpi  r23, 3
    breq AO_DIV
    rjmp AO_MOD

; =========================================================
; AO_ADD
; This adds two 32-bit numbers.
; Result is stored in r24:r25:r26:r27.
; =========================================================
AO_ADD:
    add  r24, r30
    adc  r25, r31
    adc  r26, r8
    adc  r27, r9
    ret

; =========================================================
; AO_SUB
; This subtracts two 32-bit numbers.
; Result is stored in r24:r25:r26:r27.
; =========================================================
AO_SUB:
    sub  r24, r30
    sbc  r25, r31
    sbc  r26, r8
    sbc  r27, r9
    ret

; =========================================================
; AO_MUL
; This multiplies two 32-bit numbers.
;
; AVR can multiply only small 8-bit values,
; so the code multiplies byte by byte.
; =========================================================
AO_MUL:
    push r2
    push r3
    push r4
    push r5

    clr  r2
    clr  r3
    clr  r4
    clr  r5

    ; sum=0 : b0L × b0R
    mul  r24, r30
    add  r2, r0
    adc  r3, r1

    ; sum=1 : b0L × b1R
    mul  r24, r31
    add  r3, r0
    adc  r4, r1
    brcc AOM_S1B
    inc  r5                 ; carry into byte3
AOM_S1B:
    ; sum=1 : b1L × b0R
    mul  r25, r30
    add  r3, r0
    adc  r4, r1
    brcc AOM_S2A
    inc  r5
AOM_S2A:
    ; sum=2 : b0L × b2R
    mul  r24, r8
    add  r4, r0
    adc  r5, r1

    ; sum=2 : b2L × b0R
    mul  r26, r30
    add  r4, r0
    adc  r5, r1

    ; sum=2 : b1L × b1R
    mul  r25, r31
    add  r4, r0
    adc  r5, r1

    ; sum=3 : only low byte of each product ? byte3 ?
    mul  r24, r9            ; b0L × b3R
    add  r5, r0
    mul  r27, r30           ; b3L × b0R
    add  r5, r0
    mul  r25, r8            ; b1L × b2R
    add  r5, r0
    mul  r26, r31           ; b2L × b1R
    add  r5, r0

    ; move result into r24:r25:r26:r27
    mov  r24, r2
    mov  r25, r3
    mov  r26, r4
    mov  r27, r5

    clr  r1                 ; restore r1=0 (AVR mul convention)
    pop  r5
    pop  r4
    pop  r3
    pop  r2
    ret

; =========================================================
; AO_DIV
; This divides two 32-bit numbers.
;
; It uses 32 steps because number is 32-bit.
;
; Quotient is the answer.
; Remainder is also saved for modulo.
; =========================================================
AO_DIV:
    mov  tmp, r30
    or   tmp, r31
    or   tmp, r8
    or   tmp, r9
    breq AO_DIV_ZERO

    push r2
    push r3
    push r4
    push r5
    clr  r2
    clr  r3
    clr  r4
    clr  r5
    clr  r10
    clr  r11
    clr  r12
    clr  r13
    ldi  tmp, 32

AO_DIV_LOOP:
    ; shift quotient accumulator left
    lsl  r2
    rol  r3
    rol  r4
    rol  r5
    ; shift MSB of dividend into remainder LSB
    lsl  r24
    rol  r25
    rol  r26
    rol  r27
    rol  r10
    rol  r11
    rol  r12
    rol  r13
    ; remainder >= divisor?
    cp   r10, r30
    cpc  r11, r31
    cpc  r12, r8
    cpc  r13, r9
    brlo AO_DIV_NOSUB
    sub  r10, r30
    sbc  r11, r31
    sbc  r12, r8
    sbc  r13, r9
    inc  r2                 ; set quotient bit (bit0 always 0 after lsl)
AO_DIV_NOSUB:
    dec  tmp
    brne AO_DIV_LOOP

    mov  r24, r2
    mov  r25, r3
    mov  r26, r4
    mov  r27, r5
    clr  r1
    pop  r5
    pop  r4
    pop  r3
    pop  r2
    ret

; =========================================================
; AO_DIV_ZERO
; This runs if user divides by zero.
;
; It returns special value 0xFFFFFFFF.
; This means error.
; =========================================================
AO_DIV_ZERO:
    ser  r24
    ser  r25
    ser  r26
    ser  r27
    ret

; =========================================================
; AO_MOD
; This gives remainder after division.
;
; Example:
; 10 % 3 = 1
; =========================================================
AO_MOD:
    mov  tmp, r30
    or   tmp, r31
    or   tmp, r8
    or   tmp, r9
    breq AO_DIV_ZERO
    rcall AO_DIV
    mov  r24, r10
    mov  r25, r11
    mov  r26, r12
    mov  r27, r13
    ret

; =========================================================
; GET_OP_CODE
; This converts operator key into operation number.
;
; 0 = +
; 1 = -
; 2 = *
; 3 = /
; 4 = %
; =========================================================
GET_OP_CODE:
    cpi  tmp, 4
    breq GOC_ADD
    cpi  tmp, 8
    breq GOC_SUB
    cpi  tmp, 12
    breq GOC_MUL
    cpi  tmp, 14
    breq GOC_DIV
    ldi  r23, 4             ; MOD
    ret
GOC_ADD: 
	ldi r23, 0 
	ret
GOC_SUB: 
	ldi r23, 1 
	ret
GOC_MUL: 
	ldi r23, 2 
	ret
GOC_DIV: 
	ldi r23, 3 
	ret

; =========================================================
; PROCESS_EQUALS
; This runs when user presses equals.
;
; It solves all remaining operations.
; Then it shows the final result.
; =========================================================
PROCESS_EQUALS:
    lds  r23, accum_nonzero
    tst  r23
    breq PE_DRAIN			; if no number typed, skip pushing number

    lds  r24, accum_b0		; load current number
    lds  r25, accum_b1
    lds  r26, accum_b2
    lds  r27, accum_b3

    rcall PUSH_NUM			; push last typed number to number stack

    clr  tmp
    sts  accum_b0,      tmp	; clear accumulator
    sts  accum_b1,      tmp
    sts  accum_b2,      tmp
    sts  accum_b3,      tmp
    sts  accum_nonzero, tmp	; mark accumulator as empty

PE_DRAIN:
    ldi  tmp, 15			; display code for equals
    rcall DISP_WRITE_SLOT	; write equals symbol on display

PE_DRAIN_LOOP:
    lds  tmp2, op_sp		; load operator stack pointer
    tst  tmp2
    breq PE_RESULT			; if empty, final result is ready

    rcall POP_OP_SLOT
    mov  r28, tmp			; save operator in r28

    rcall POP_NUM           ; right operand
    push r27				; save right op
    push r26
    push r25
    push r24

    rcall POP_NUM           ; left operand
    pop  r30				; restore right op
    pop  r31
    pop  r8
    pop  r9

    push r22
    rcall APPLY_OP			; calculate left operator right
    pop  r22
    rcall PUSH_NUM			; push result back to number stack
    rjmp PE_DRAIN_LOOP		; repeat until all operators are solved

PE_RESULT:
    rcall POP_NUM           ; final result r24:r25:r26:r27

    ; detect divide-by-zero sentinel 0xFFFFFFFF
    mov  tmp, r24			; result byte 
    and  tmp, r25
    and  tmp, r26
    and  tmp, r27
    cpi  tmp, 0xFF			; check if all bytes were 0xFF
    breq PE_ERR				; if yes, it means error

    rcall CLEAR_DISPLAY_BUFFER
    clr   tmp
    sts   current_pos, tmp	; start display writing from position 0
    rcall NUM_TO_DISPLAY	; convert result number to display digits
    rcall CALC_INIT			; reset calculator memory
    ret

PE_ERR:
    ldi  tmp, 16			; display code for error symbol
    rcall DISP_WRITE_SLOT	; write error symbol to display
    rcall CALC_INIT			; reset calculator memory
    ret

; =========================================================
; FULL_CLEAR
; This clears the calculator.
;
; It clears display, numbers, operators,
; and current typed number.
; =========================================================
FULL_CLEAR:
    rcall CLEAR_DISPLAY_BUFFER
    clr  tmp
    sts  current_pos, tmp
    rcall CALC_INIT
    ret

; =========================================================
; CALC_INIT
; This resets calculator memory.
;
; It clears stacks and current number.
; =========================================================
CALC_INIT:
    clr  tmp
    sts  num_sp,        tmp
    sts  op_sp,         tmp
    sts  accum_b0,      tmp
    sts  accum_b1,      tmp
    sts  accum_b2,      tmp
    sts  accum_b3,      tmp
    sts  accum_nonzero, tmp
    ret

; =========================================================
; PUSH_NUM
; This stores one number in number stack.
;
; One number uses 4 bytes.
; =========================================================
PUSH_NUM:
    push r26				; save r26 (byte2 of value) — also XL
    push r27				; save r27 (byte3 of value) — also XH
    lds  tmp, num_sp		; load number stack pointer
    ldi  XL, low(num_stack)	; X = start address of num_stack
    ldi  XH, high(num_stack)
    lsl  tmp               ; offset = sp × 4
    lsl  tmp

    add  XL, tmp		   ; move X to correct stack position
    adc  XH, r1			   ; add carry to high address

    st   X+, r24           ; store byte0
    st   X+, r25           ; store byte1

    pop  tmp2              ; retrieve byte3 (was r27)
    pop  tmp               ; retrieve byte2 (was r26)

    st   X+, tmp           ; store byte2
    st   X,  tmp2          ; store byte3

    lds  tmp, num_sp
    inc  tmp
    sts  num_sp, tmp

    ret

; =========================================================
; POP_NUM
; This takes one number from number stack.
;
; Output number goes into r24:r25:r26:r27.
; =========================================================
POP_NUM:
    lds  tmp, num_sp		; tmp = number stack pointer
    tst  tmp				; check if num_sp is 0
    breq POP_NUM_EMPTY		; if stack empty, return 0

    dec  tmp				; num_sp--
    sts  num_sp, tmp		
    ; Compute address into tmp (reuse), then use Z pointer (r30:r31)
    ; to avoid the r26/r27 = XL/XH conflict.
    push r30               ; save Z registers
    push r31
    lsl  tmp               ; offset = sp × 4 because each number uses 4 bytes
    lsl  tmp
    ldi  r30, low(num_stack)
    ldi  r31, high(num_stack)

    add  r30, tmp			; Z = num_stack + offset
    adc  r31, r1

    ld   r24, Z+			; load byte0
    ld   r25, Z+			; load byte1
    ld   r26, Z+			; load byte2
    ld   r27, Z				; load byte3
    pop  r31				; restore Z
    pop  r30
    ret
POP_NUM_EMPTY:              ; 0 all the op when num stack is empty
    clr  r24
    clr  r25
    clr  r26
    clr  r27
    ret

; =========================================================
; PUSH_OP_SLOT
; This stores one operator in operator stack.
; =========================================================
PUSH_OP_SLOT:
    lds  tmp2, op_sp
    ldi  XL, low(op_stack)
    ldi  XH, high(op_stack)
    add  XL, tmp2
    adc  XH, r1
    st   X, tmp
    inc  tmp2
    sts  op_sp, tmp2
    ret

; =========================================================
; POP_OP_SLOT
; This takes one operator from operator stack.
; =========================================================
POP_OP_SLOT:
    lds  tmp2, op_sp	; operator stack pointer
    tst  tmp2			; check if op_sp is 0
    breq POP_OP_EMPTY	; if empty, return 0xFF
    dec  tmp2			; op_sp--

    sts  op_sp, tmp2	; save updated op_sp

    ldi  XL, low(op_stack)
    ldi  XH, high(op_stack)

    add  XL, tmp2		; X = op_stack + op_sp
    adc  XH, r1			; add carry to high byte
    ld   tmp, X			; op_stack[op_sp]
    ret
POP_OP_EMPTY:
    ldi  tmp, 0xFF		; return 0xFF if stack is empty
    ret

; =========================================================
; DISP_WRITE_SLOT
; This writes one character to display buffer.
;
; It writes at current_pos.
; Then current_pos is increased.
; =========================================================
DISP_WRITE_SLOT:
    lds  tmp2, current_pos				//writing current slot position
    cpi  tmp2, 16						// checking if we reach the last slot
    brge DWS_FULL						// if full then return
    ldi  ZH, high(display_buffer)		// Bring Z pointer to start
    ldi  ZL, low(display_buffer)
    add  ZL, tmp2						// move Z pointer to the current slot, like display_buffer+current_pos
    st   Z, tmp							// load the character code in the Z pointers current slot like, display_slot[current_pos] = tmp
    inc  tmp2							// increment the current_pos
    andi tmp2, 0x0F						// safe masking to check the if it is beyond 15 or not
    sts  current_pos, tmp2				// storing the updated number into tmp2
DWS_FULL:
    ret

; =========================================================
; NUM_TO_DISPLAY
; This converts final number into display digits.
;
; Example:
; number 123 becomes digits 1, 2, 3.
; =========================================================
NUM_TO_DISPLAY:
    clr  r23                ; r23 = digit count = 0
    ldi  YL, low(digit_buf)		; Y points to digit_buf
    ldi  YH, high(digit_buf)

NTD_LOOP:
    rcall DIV32_BY_10       ; divide number by 10
                            ; quotient stays in r24:r25:r26:r27
                            ; remainder digit comes in tmp
    push r24
    push r25
    push r26
    push r27
    rcall DIGIT_TO_SLOT     ; convert remainder digit to display code
    st   Y+, tmp			; store digit display code in digit_buf
                            ; then move Y to next location
    inc  r23				; digit count++

    pop  r27
    pop  r26
    pop  r25
    pop  r24

    ; loop while quotient ? 0
    mov  tmp, r24
    or   tmp, r25
    or   tmp, r26
    or   tmp, r27

    brne NTD_LOOP			; if quotient is not zero, continue

NTD_OUTPUT:
    tst  r23
    breq NTD_DONE
    ld   tmp, -Y            ; read digits in reverse (most-significant first)
    rcall DISP_WRITE_SLOT
    dec  r23
    rjmp NTD_OUTPUT
NTD_DONE:
    ret

; =========================================================
; DIV32_BY_10
; This divides a 32-bit number by 10.
;
; It is used to get decimal digits for display.
; =========================================================
DIV32_BY_10:
    push r2
    push r3
    push r4
    push r5
    push r23               ; save r23 (used as remainder register)

    clr  r2
    clr  r3
    clr  r4
    clr  r5
    clr  r23               ; remainder starts at 0
    ldi  tmp, 32           ; loop 32 times because number is 32-bit

D32_LOOP:
    ; shift quotient accumulator left
    lsl  r2
    rol  r3
    rol  r4
    rol  r5

    ; shift MSB of dividend into remainder (r23)
    lsl  r24
    rol  r25
    rol  r26
    rol  r27
    rol  r23				; remainder bit shifted in from dividend MSB

    cpi  r23, 10
    brlt D32_NOSUB			; check if remainder >= 10
    subi r23, 10			; remainder = remainder - 10
    inc  r2					; set quotient bit (bit0 is always 0 after lsl)
D32_NOSUB:
    dec  tmp				; loop counter--
    brne D32_LOOP

    mov  r24, r2
    mov  r25, r3
    mov  r26, r4
    mov  r27, r5

    mov  tmp, r23          ; remainder digit

    pop  r23               ; restore r23
    pop  r5
    pop  r4
    pop  r3
    pop  r2
    ret

; =========================================================
; CLEAR_DISPLAY_BUFFER
; This clears all 16 display slots.
; =========================================================
CLEAR_DISPLAY_BUFFER:
    ldi  ZH, high(display_buffer)
    ldi  ZL, low(display_buffer)
    ldi  tmp, 16
    clr  tmp2
CDB_LOOP:
    st   Z+, tmp2
    dec  tmp
    brne CDB_LOOP
    ret

; =========================================================
; TIMER_TICK
; This is timer interrupt.
;
; It refreshes the display automatically.
; It runs again and again in background.
; =========================================================
TIMER_TICK:
    push  tmp
    in    tmp, SREG				; copy status register
    push  tmp
    push  tmp2
    push  row_ctr
    push  data
    push  bit_ctr
    push  col_idx
    push  key
    push  r23
    push  r24
    push  r25
    push  r26
    push  r27
    push  r28
    push  r29
    push  r30
    push  r31

    lds  tmp, debounce_timer		; load debounce_timer
    tst  tmp
    breq TT_DISPLAY					; if 0, go to display refresh
    dec  tmp						; debounce_timer--
    sts  debounce_timer, tmp

TT_DISPLAY:
    lds  tmp, row_timer				; load row_timer
    tst  tmp
    breq TT_NEXT_ROW				; if 0, refresh next row
    dec  tmp						; row_timer--
    sts  row_timer, tmp				; save row_timer
    rjmp TT_DONE					; do not refresh row 

TT_NEXT_ROW:
    sbi  PORTB, PB4					; set latch high
    lds  row_ctr, row_counter		; row_ctr = current display row
    ldi  col_idx, 16				; start from display slot 16

TT_SHIFT_LOOP:
    ldi  ZH, high(display_buffer)	; Z points to display_buffer
    ldi  ZL, low(display_buffer)	; Z low byte
    mov  tmp, col_idx				; tmp = current column index
    dec  tmp						; tmp = col_idx - 1
    add  ZL, tmp					; Z = display_buffer + tmp
    ld   tmp, Z						; tmp = character code from display buffer
    rcall GET_LED_PATTERN			; convert character code into LED pattern
    rcall SHIFT_OUT_5_BITS			; send 5 pattern bits to display
    dec  col_idx					; move to previous slot
    brne TT_SHIFT_LOOP				; repeat until all 16 slots sent

    ldi  data, 0x01					; this selects row 0 first
    mov  tmp, row_ctr				; tmp = current row number
    tst  tmp
    breq TT_SHIFT_ROW				; if row 0, no shifting needed
TT_ROW_SHIFT:	
    lsl  data						; move row select bit to next row
    dec  tmp    brne TT_ROW_SHIFT				; repeat until correct row bit is ready

TT_SHIFT_ROW:
    rcall SHIFT_OUT_8_BITS			; send row select byte to display
    sbi  PORTB, PB4					; latch high
    nop
    nop
    cbi  PORTB, PB4
    ldi  tmp, 2
    sts  row_timer, tmp				; row_timer = 2
    inc  row_ctr
    cpi  row_ctr, 7
    brne TT_SAVE_ROW				; if not 7, keep row_ctr
    clr  row_ctr
TT_SAVE_ROW:
    sts  row_counter, row_ctr

; =========================================================
; TT_DONE
; Restore all registers saved at start of interrupt.
; Then return from interrupt using reti.
; =========================================================
TT_DONE:
    pop  r31
    pop  r30
    pop  r29
    pop  r28
    pop  r27
    pop  r26
    pop  r25
    pop  r24
    pop  r23
    pop  key
    pop  col_idx
    pop  bit_ctr
    pop  data
    pop  row_ctr
    pop  tmp2
    pop  tmp
    out  SREG, tmp
    pop  tmp
    reti

; =========================================================
; GET_LED_PATTERN
; This gets LED pattern for one character.
;
; It reads pattern from char_table.
; =========================================================
GET_LED_PATTERN:
    tst  tmp			; check if character code is 0
    breq GLP_BLANK		; if 0, display blank
    
	dec  tmp

    lsl  tmp
    lsl  tmp
    lsl  tmp			;x8
    
	lds  row_ctr, row_counter	; row_ctr = current display row
    add  tmp, row_ctr			; tmp = character offset + row number

    ldi  ZH, high(char_table<<1)	; Z points to char_table in program memory
    ldi  ZL, low(char_table<<1)		; Z low byte

    add  ZL, tmp					; Z = char_table + index
    brcc GLP_NO_CARRY				; if no carry, high byte is okay

    inc  ZH							; if carry happened, increase high byte
GLP_NO_CARRY:
    lpm  data, Z					; read pattern from program memory into data
    ret
GLP_BLANK:
    clr  data						; blank pattern = 0
    ret

; =========================================================
; SHIFT_OUT_5_BITS
; This sends 5 bits to display.
;
; It is used for character pattern.
; =========================================================
SHIFT_OUT_5_BITS:
    lsl  data						; move pattern bits toward carry position
    lsl  data						
    lsl  data

    ldi  bit_ctr, 5					; send only 5 bits
    rjmp SHIFT_LOOP					; go to common shift loop

; =========================================================
; SHIFT_OUT_8_BITS
; This sends 8 bits to display.
;
; It is used for row selection.
; =========================================================
SHIFT_OUT_8_BITS:
    ldi  bit_ctr, 8					; send 8 bits

; =========================================================
; SHIFT_LOOP
; This sends bits one by one.
;
; PB3 sends data.
; PB5 gives clock.
; =========================================================
SHIFT_LOOP:
    rol  data						; rotate data left, next bit goes into carry flag
    brcc SL_LOW						; if carry is 0, send low
    sbi  PORTB, PB3					; carry is 1, so data pin = HIGH
    rjmp SL_CLK						; pulse clock
SL_LOW:
    cbi  PORTB, PB3					; carry is 0, so data pin = LOW
SL_CLK:
    sbi  PORTB, PB5
    nop
    cbi  PORTB, PB5
    dec  bit_ctr					; one bit sent, counter--
    brne SHIFT_LOOP					; if more bits left, send next bit
    cbi  PORTB, PB3					; clear data pin at end
    ret

; =========================================================
; SCAN_KEYBOARD
; This scans keypad rows and columns.
;
; If key is pressed, key register gets value.
; If no key is pressed, key stays zero.
; =========================================================
SCAN_KEYBOARD:
    clr  key
    ldi  tmp, 0b01111111			; activate row 1
    out  PORTD, tmp
    nop
    in   tmp, PIND					; read keypad columns
    rcall CHECK_COLUMNS				; check if any column is pressed
    tst  key
    brne SK_DONE					; if key found, finish

    ldi  tmp, 0b10111111
    out  PORTD, tmp
    nop
    in   tmp, PIND
    rcall CHECK_COLUMNS
    tst  key
    breq SK_ROW3
    subi key, -4
    rjmp SK_DONE

SK_ROW3:
    ldi  tmp, 0b11011111
    out  PORTD, tmp
    nop
    in   tmp, PIND
    rcall CHECK_COLUMNS
    tst  key
    breq SK_ROW4
    subi key, -8
    rjmp SK_DONE

SK_ROW4:
    ldi  tmp, 0b11101111
    out  PORTD, tmp
    nop
    in   tmp, PIND
    rcall CHECK_COLUMNS
    tst  key
    breq SK_DONE
    subi key, -12

SK_DONE:
    ldi  tmp, 0xFF
    out  PORTD, tmp
    ret

; =========================================================
; CHECK_COLUMNS
; This checks which keypad column is pressed.
; =========================================================
CHECK_COLUMNS:
    clr  key
    sbrc tmp, PD3				; skip next line if PD3 is clear
                                ; if PD3 is high, no press on this column
    rjmp CC_COL2				; go check next column
    ldi  key, 1					; PD3 is low, so column 1 is pressed	
    ret
CC_COL2:
    sbrc tmp, PD2
    rjmp CC_COL3
    ldi  key, 2
    ret
CC_COL3:
    sbrc tmp, PD1
    rjmp CC_COL4
    ldi  key, 3
    ret
CC_COL4:
    sbrc tmp, PD0
    ret
    ldi  key, 4
    ret

; =========================================================
; char_table
; This stores display shapes.
;
; Each character has LED pattern data.
; Display uses this table to show digits/operators.
; =========================================================
char_table:
.db 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0x00
.db 0b01110, 0b10000, 0b10000, 0b01110, 0b00010, 0b00010, 0b11110, 0x00
.db 0b01110, 0b10000, 0b10000, 0b01110, 0b10000, 0b10000, 0b01110, 0x00
.db 0b00000, 0b00100, 0b00100, 0b01110, 0b00100, 0b00100, 0b00000, 0x00
.db 0b10001, 0b10001, 0b10001, 0b11111, 0b10000, 0b10000, 0b10000, 0x00
.db 0b11111, 0b00001, 0b00001, 0b01111, 0b10000, 0b10000, 0b01111, 0x00
.db 0b01110, 0b00001, 0b00001, 0b01111, 0b10001, 0b10001, 0b01110, 0x00
.db 0b00000, 0b00000, 0b00000, 0b01110, 0b00000, 0b00000, 0b00000, 0x00
.db 0b11111, 0b10000, 0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0x00
.db 0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110, 0x00
.db 0b01110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b01111, 0x00
.db 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b00000, 0b00000, 0x00
.db 0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110, 0x00
.db 0b10000, 0b01000, 0b00100, 0b00010, 0b00001, 0b00000, 0b00000, 0x00
.db 0b00000, 0b01110, 0b00000, 0b00000, 0b01110, 0b00000, 0b00000, 0x00
.db 0b11000, 0b11010, 0b00100, 0b01000, 0b10110, 0b00110, 0b00000, 0x00