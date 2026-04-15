.include "m328pdef.inc"

.def tmp      = r16
.def tmp2     = r17
.def key      = r18
.def bit_ctr  = r19
.def data     = r20
.def col_idx  = r21
.def row_ctr  = r22

.dseg
.org 0x0100
display_buffer:   .byte 16
current_pos:      .byte 1
key_pressed_flag: .byte 1
debounce_timer:   .byte 1
row_timer:        .byte 1
row_counter:      .byte 1

.org 0x0120
num_stack:        .byte 16
op_stack:         .byte 8
num_sp:           .byte 1
op_sp:            .byte 1
accum_lo:         .byte 1
accum_hi:         .byte 1
accum_nonzero:    .byte 1
incoming_op:      .byte 1

.cseg
.org 0x0000
    rjmp MAIN_RESET

.org 0x001C
    rjmp TIMER_TICK

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

KEY_TO_DIGIT:
    cpi  key, 14
    brne KTD_NOT14
    ldi  tmp, 0
    ret
KTD_NOT14:
    cpi  key, 4
    brlt KTD_LOW
    cpi  key, 8
    brlt KTD_MID
    mov  tmp, key
    subi tmp, 2
    ret
KTD_LOW:
    mov  tmp, key
    ret
KTD_MID:
    mov  tmp, key
    dec  tmp
    ret

PROCESS_DIGIT:
    push tmp
    lds  r24, accum_lo
    lds  r25, accum_hi
    rcall MUL16_BY_10
    pop  tmp
    clr  tmp2
    add  r24, tmp
    adc  r25, tmp2
    sts  accum_lo, r24
    sts  accum_hi, r25
    ldi  tmp2, 1
    sts  accum_nonzero, tmp2
    rcall KEY_TO_DIGIT
    rcall DIGIT_TO_SLOT
    rcall DISP_WRITE_SLOT
    ret

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
    ldi  tmp, 13
    ret
DTS_1_3:
    ret
DTS_4_6:
    inc  tmp
    ret

GET_PREC:
    cpi  tmp, 12
    breq GP_HIGH
    cpi  tmp, 14
    breq GP_HIGH
    cpi  tmp, 16
    breq GP_HIGH
    ldi  r23, 1
    ret
GP_HIGH:
    ldi  r23, 2
    ret

PROCESS_OPERATOR:
    push tmp

    lds  r23, accum_nonzero
    tst  r23
    breq PO_SKIP_PUSH
    lds  r24, accum_lo
    lds  r25, accum_hi
    rcall PUSH_NUM
    clr  tmp2
    sts  accum_lo,      tmp2
    sts  accum_hi,      tmp2
    sts  accum_nonzero, tmp2

PO_SKIP_PUSH:
    pop  tmp
    mov  r22, tmp

PO_LOOP:
    lds  r27, op_sp
    tst  r27
    breq PO_DONE

    dec  r27
    ldi  XL, low(op_stack)
    ldi  XH, high(op_stack)
    add  XL, r27
    adc  XH, r1
    ld   tmp, X
    rcall GET_PREC
    mov  r26, r23

    mov  tmp, r22
    rcall GET_PREC

    cp   r26, r23
    brlo PO_DONE
    mov  tmp, r22

    rcall POP_OP_SLOT
    mov  r28, tmp
    rcall POP_NUM
    mov  r30, r24
    mov  r31, r25
    rcall POP_NUM
	push r22
    rcall APPLY_OP
	pop r22
    rcall PUSH_NUM
    rjmp PO_LOOP

PO_DONE:
    mov  tmp, r22
    rcall PUSH_OP_SLOT
    rcall DISP_WRITE_SLOT
    ret

APPLY_OP:
    push tmp
    mov  tmp, r28
    rcall GET_OP_CODE
    pop  tmp
    tst  r23
    breq AO_ADD
    cpi  r23, 1
    breq AO_SUB
    cpi  r23, 2
    breq AO_MUL
    cpi  r23, 3
    breq AO_DIV
    rjmp AO_MOD

AO_ADD:
    add  r24, r30
    adc  r25, r31
    ret

AO_SUB:
    sub  r24, r30
    sbc  r25, r31
    ret

AO_MUL:
    mul  r24, r30
    movw r2, r0
    mul  r24, r31
    add  r3, r0
    mul  r25, r30
    add  r3, r0
    movw r24, r2
    clr  r1
    ret

AO_DIV:
    mov  tmp, r30
    or   tmp, r31
    breq AO_DIV_ZERO
    clr  r2
    clr  r3
    clr  r28
    clr  r29
    ldi  tmp, 16
AO_DIV_LOOP:
    lsl  r24
    rol  r25
    rol  r28
    rol  r2
    rol  r3
    cp   r28, r30
    cpc  r29, r31
    brlt AO_DIV_NOSUB
    sub  r28, r30
    sbc  r29, r31
    inc  r2
AO_DIV_NOSUB:
    dec  tmp
    brne AO_DIV_LOOP
    movw r24, r2
    clr  r1
    ret
AO_DIV_ZERO:
    ldi  r24, 0xFF
    ldi  r25, 0xFF
    ret

AO_MOD:
    mov  tmp, r30
    or   tmp, r31
    breq AO_DIV_ZERO
    clr  r2
    clr  r3
    clr  r28
    clr  r29
    ldi  tmp, 16
AO_MOD_LOOP:
    lsl  r24
    rol  r25
    rol  r28
    rol  r2
    rol  r3
    cp   r28, r30
    cpc  r29, r31
    brlt AO_MOD_NOSUB
    sub  r28, r30
    sbc  r29, r31
    inc  r2
AO_MOD_NOSUB:
    dec  tmp
    brne AO_MOD_LOOP
    movw r24, r28
    clr  r1
	ret

GET_OP_CODE:
    cpi  tmp, 4
    breq GOC_ADD
    cpi  tmp, 8
    breq GOC_SUB
    cpi  tmp, 12
    breq GOC_MUL
    cpi  tmp, 14
    breq GOC_DIV
    ldi  r23, 4
    ret
GOC_ADD: ldi r23, 0
    ret
GOC_SUB: ldi r23, 1
    ret
GOC_MUL: ldi r23, 2
    ret
GOC_DIV: ldi r23, 3
    ret

PROCESS_EQUALS:
    lds  r23, accum_nonzero
    tst  r23
    breq PE_DRAIN
    lds  r24, accum_lo
    lds  r25, accum_hi
    rcall PUSH_NUM
    clr  tmp
    sts  accum_lo,      tmp
    sts  accum_hi,      tmp
    sts  accum_nonzero, tmp

PE_DRAIN:
    ldi  tmp, 15
    rcall DISP_WRITE_SLOT

PE_DRAIN_LOOP:
    lds  tmp2, op_sp
    tst  tmp2
    breq PE_RESULT

    rcall POP_OP_SLOT
    mov  r28, tmp
    rcall POP_NUM
    mov  r30, r24
    mov  r31, r25
    rcall POP_NUM
	push r22
    rcall APPLY_OP
	pop r22
    rcall PUSH_NUM
    rjmp PE_DRAIN_LOOP

PE_RESULT:
    rcall POP_NUM

    cpi  r24, 0xFF
    brne PE_OK
    cpi  r25, 0xFF
    brne PE_OK
    ldi  tmp, 16
    rcall DISP_WRITE_SLOT
    ret

PE_OK:
    rcall CLEAR_DISPLAY_BUFFER
    clr   tmp
    sts   current_pos, tmp
    rcall NUM_TO_DISPLAY
    rcall CALC_INIT
    ret
FULL_CLEAR:
    rcall CLEAR_DISPLAY_BUFFER
    clr  tmp
    sts  current_pos, tmp
    rcall CALC_INIT
    ret

CALC_INIT:
    clr  tmp
    sts  num_sp,        tmp
    sts  op_sp,         tmp
    sts  accum_lo,      tmp
    sts  accum_hi,      tmp
    sts  accum_nonzero, tmp
    ret

MUL16_BY_10:
    movw r2, r24
    lsl  r24
    rol  r25
    lsl  r24
    rol  r25
    lsl  r24
    rol  r25
    movw r4, r24
    movw r24, r2
    lsl  r24
    rol  r25
    add  r24, r4
    adc  r25, r5
    ret

PUSH_NUM:
    lds  tmp, num_sp
    ldi  XL, low(num_stack)
    ldi  XH, high(num_stack)
    lsl  tmp
    add  XL, tmp
    adc  XH, r1
    st   X+, r24
    st   X,  r25
    lds  tmp, num_sp
    inc  tmp
    sts  num_sp, tmp
    ret

POP_NUM:
    lds  tmp, num_sp
    tst  tmp
    breq POP_NUM_EMPTY
    dec  tmp
    sts  num_sp, tmp
    ldi  XL, low(num_stack)
    ldi  XH, high(num_stack)
    lsl  tmp
    add  XL, tmp
    adc  XH, r1
    ld   r24, X+
    ld   r25, X
    ret
POP_NUM_EMPTY:
    clr  r24
    clr  r25
    ret

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

POP_OP_SLOT:
    lds  tmp2, op_sp
    tst  tmp2
    breq POP_OP_EMPTY
    dec  tmp2
    sts  op_sp, tmp2
    ldi  XL, low(op_stack)
    ldi  XH, high(op_stack)
    add  XL, tmp2
    adc  XH, r1
    ld   tmp, X
    ret
POP_OP_EMPTY:
    ldi  tmp, 0xFF
    ret

DISP_WRITE_SLOT:
    lds  tmp2, current_pos
    cpi  tmp2, 16
    brge DWS_FULL
    ldi  ZH, high(display_buffer)
    ldi  ZL, low(display_buffer)
    add  ZL, tmp2
    st   Z, tmp
    inc  tmp2
    andi tmp2, 0x0F
    sts  current_pos, tmp2
DWS_FULL:
    ret

NUM_TO_DISPLAY:
    ldi  r26, 0
    ldi  YL, low(0x0140)
    ldi  YH, high(0x0140)

NTD_LOOP:
    rcall DIV16_BY_10
    push r24
    push r25
    rcall DIGIT_TO_SLOT
    st   Y+, tmp
    inc  r26
    pop  r25
    pop  r24
    mov  tmp, r24
    or   tmp, r25
    brne NTD_LOOP

NTD_OUTPUT:
    tst  r26
    breq NTD_DONE
    sbiw YL, 1
    ld   tmp, Y
    rcall DISP_WRITE_SLOT
    dec  r26
    rjmp NTD_OUTPUT

NTD_DONE:
    ret

DIV16_BY_10:
    push r26
    push r27
    push r28
    push r29
    push r30
    push r31
    clr  r26
    clr  r27
    clr  r28
    clr  r29
    ldi  tmp, 16
D10_LOOP:
    lsl  r24
    rol  r25
    rol  r28
    rol  r26
    rol  r27
    cpi  r28, 10
    brlt D10_NOSUB
    subi r28, 10
    ori  r26, 1
D10_NOSUB:
    dec  tmp
    brne D10_LOOP
    movw r24, r26
    mov  tmp, r28
    pop  r31
    pop  r30
    pop  r29
    pop  r28
    pop  r27
    pop  r26
    ret

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

TIMER_TICK:
    push  tmp
    in    tmp, SREG
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

    lds  tmp, debounce_timer
    tst  tmp
    breq TT_DISPLAY
    dec  tmp
    sts  debounce_timer, tmp

TT_DISPLAY:
    lds  tmp, row_timer
    tst  tmp
    breq TT_NEXT_ROW
    dec  tmp
    sts  row_timer, tmp
    rjmp TT_DONE

TT_NEXT_ROW:
    sbi  PORTB, PB4
    lds  row_ctr, row_counter
    ldi  col_idx, 16

TT_SHIFT_LOOP:
    ldi  ZH, high(display_buffer)
    ldi  ZL, low(display_buffer)
    mov  tmp, col_idx
    dec  tmp
    add  ZL, tmp
    ld   tmp, Z
    rcall GET_LED_PATTERN
    rcall SHIFT_OUT_5_BITS
    dec  col_idx
    brne TT_SHIFT_LOOP

    ldi  data, 0x01
    mov  tmp, row_ctr
    tst  tmp
    breq TT_SHIFT_ROW
TT_ROW_SHIFT:
    lsl  data
    dec  tmp
    brne TT_ROW_SHIFT

TT_SHIFT_ROW:
    rcall SHIFT_OUT_8_BITS
    sbi  PORTB, PB4
    nop
    nop
    cbi  PORTB, PB4
    ldi  tmp, 2
    sts  row_timer, tmp
    inc  row_ctr
    cpi  row_ctr, 7
    brne TT_SAVE_ROW
    clr  row_ctr
TT_SAVE_ROW:
    sts  row_counter, row_ctr

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

GET_LED_PATTERN:
    tst  tmp
    breq GLP_BLANK
    dec  tmp
    lsl  tmp
    lsl  tmp
    lsl  tmp
    lds  row_ctr, row_counter
    add  tmp, row_ctr
    ldi  ZH, high(char_table<<1)
    ldi  ZL, low(char_table<<1)
    add  ZL, tmp
    brcc GLP_NO_CARRY
    inc  ZH
GLP_NO_CARRY:
    lpm  data, Z
    ret
GLP_BLANK:
    clr  data
    ret

SHIFT_OUT_5_BITS:
    lsl  data
    lsl  data
    lsl  data
    ldi  bit_ctr, 5
    rjmp SHIFT_LOOP

SHIFT_OUT_8_BITS:
    ldi  bit_ctr, 8
SHIFT_LOOP:
    rol  data
    brcc SL_LOW
    sbi  PORTB, PB3
    rjmp SL_CLK
SL_LOW:
    cbi  PORTB, PB3
SL_CLK:
    sbi  PORTB, PB5
    nop
    cbi  PORTB, PB5
    dec  bit_ctr
    brne SHIFT_LOOP
    cbi  PORTB, PB3
    ret

SCAN_KEYBOARD:
    clr  key
    ldi  tmp, 0b01111111
    out  PORTD, tmp
    nop
    in   tmp, PIND
    rcall CHECK_COLUMNS
    tst  key
    brne SK_DONE

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

CHECK_COLUMNS:
    clr  key
    sbrc tmp, PD3
    rjmp CC_COL2
    ldi  key, 1
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