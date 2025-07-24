; Xtensa Assembly for ESP32: Soil-Based Logic Gates Control
; Equivalent to Arduino C++ code for XOR/AND half-adder on ESP32
; Uses GPIO4 (XOR_INPUT_A), GPIO5 (XOR_INPUT_B), GPIO18 (AND_INPUT_A), GPIO19 (AND_INPUT_B) as outputs
; Uses GPIO34 (ADC1_CH6) for XOR_OUTPUT, GPIO35 (ADC1_CH7) for AND_OUTPUT
; UART0 for serial output at 9600 baud
; Assumes 80MHz APB clock for UART baud rate calculation
; Uses busy-loop for approximate 1000ms delay (calibrated for 240MHz CPU clock)

; Register definitions (bit positions)
.equ XOR_INPUT_A_BIT, 4      ; GPIO4
.equ XOR_INPUT_B_BIT, 5      ; GPIO5
.equ AND_INPUT_A_BIT, 18     ; GPIO18
.equ AND_INPUT_B_BIT, 19     ; GPIO19

; GPIO register addresses (from ESP32 TRM)
.equ GPIO_OUT_W1TS_REG, 0x3FF44008   ; Set bits for GPIO 0-31
.equ GPIO_OUT_W1TC_REG, 0x3FF4400C   ; Clear bits for GPIO 0-31
.equ GPIO_ENABLE_W1TS_REG, 0x3FF44024 ; Enable output for GPIO 0-31

; ADC register addresses (SAR ADC1 for simplicity)
.equ APB_SARADC_CTRL_REG, 0x3FF48800  ; ADC control
.equ SENS_SAR_MEAS_START1_REG, 0x3FF48854 ; ADC1 start
.equ SENS_SAR_READ_CTRL_REG, 0x3FF48804  ; ADC read control

; UART0 register addresses
.equ UART0_FIFO_REG, 0x3FF40000      ; FIFO for data
.equ UART0_CONF0_REG, 0x3FF40020     ; Configuration 0 (parity, bits, etc.)
.equ UART0_CONF1_REG, 0x3FF40024     ; Configuration 1 (flow control)
.equ UART0_BAUD_REG, 0x3FF4000C      ; Baud rate divisor
.equ UART0_STATUS_REG, 0x3FF4001C    ; Status (TX FIFO empty)

; Constants
.equ BAUD_DIV, 520                   ; 80MHz / (16 * 9600) ≈ 520
.equ DELAY_LOOP_COUNT, 0x1000000     ; Approximate loop for 1000ms at 240MHz (adjust as needed)

; String constants in program memory
.section .text
msg_sum:   .asciz "Sum (XOR): "
msg_carry: .asciz "Carry (AND): "
msg_zero:  .asciz "0\n"
msg_one:   .asciz "1\n"

.global _start
_start:
    ; Enable GPIO outputs (set bits in GPIO_ENABLE_W1TS_REG)
    movi a2, GPIO_ENABLE_W1TS_REG
    movi a3, (1 << XOR_INPUT_A_BIT) | (1 << XOR_INPUT_B_BIT) | (1 << AND_INPUT_A_BIT) | (1 << AND_INPUT_B_BIT)
    s32i a3, a2, 0

    ; Setup UART0 (9600 baud, 8N1)
    movi a2, UART0_CONF0_REG
    movi a3, 0x03 << 0 | 0x00 << 2 | 0x00 << 4 | 0x00 << 6  ; 8 bits, no parity, 1 stop, no invert
    s32i a3, a2, 0
    movi a2, UART0_BAUD_REG
    movi a3, BAUD_DIV
    s32i a3, a2, 0
    movi a2, UART0_CONF1_REG
    movi a3, 0x00  ; Disable flow control
    s32i a3, a2, 0

    ; Setup ADC (SAR ADC1, 12-bit, enable)
    movi a2, SENS_SAR_READ_CTRL_REG
    movi a3, 0x02 << 28 | 0x01 << 27  ; 12-bit, enable ADC1
    s32i a3, a2, 0
    movi a2, APB_SARADC_CTRL_REG
    movi a3, 0x01 << 24 | 0x00 << 11  ; Continuous mode off, single conversion
    s32i a3, a2, 0

loop:
    ; Set inputs: A=0 (LOW), B=1 (HIGH) for XOR and AND
    movi a2, GPIO_OUT_W1TC_REG
    movi a3, (1 << XOR_INPUT_A_BIT) | (1 << AND_INPUT_A_BIT)  ; Clear A bits (LOW)
    s32i a3, a2, 0
    movi a2, GPIO_OUT_W1TS_REG
    movi a3, (1 << XOR_INPUT_B_BIT) | (1 << AND_INPUT_B_BIT)  ; Set B bits (HIGH)
    s32i a3, a2, 0

    ; Delay ~1000ms (busy loop)
    movi a15, DELAY_LOOP_COUNT
delay_loop1:
    addi a15, a15, -1
    bnez a15, delay_loop1

    ; Read XOR output (GPIO34, ADC1_CH6)
    movi a2, SENS_SAR_MEAS_START1_REG
    movi a3, 0x01 << 31 | 0x06 << 27  ; Start, channel 6
    s32i a3, a2, 0
wait_adc_xor:
    l32i a4, a2, 0
    bbci a4, 31, adc_xor_done  ; Check done bit
    j wait_adc_xor
adc_xor_done:
    extui a5, a4, 0, 12  ; Extract 12-bit value
    movi a6, 2048        ; Threshold 2048 (adjusted for 12-bit ADC)
    blt a5, a6, xor_zero
    movi a7, 1           ; xorResult = 1
    j xor_done
xor_zero:
    movi a7, 0           ; xorResult = 0
xor_done:

    ; Read AND output (GPIO35, ADC1_CH7)
    movi a2, SENS_SAR_MEAS_START1_REG
    movi a3, 0x01 << 31 | 0x07 << 27  ; Start, channel 7
    s32i a3, a2, 0
wait_adc_and:
    l32i a4, a2, 0
    bbci a4, 31, adc_and_done
    j wait_adc_and
adc_and_done:
    extui a5, a4, 0, 12  ; Extract 12-bit value
    movi a6, 2456        ; Threshold 2456 (adjusted for 12-bit ADC)
    blt a5, a6, and_zero
    movi a8, 1           ; andResult = 1
    j and_done
and_zero:
    movi a8, 0           ; andResult = 0
and_done:

    ; Print "Sum (XOR): "
    l32r a9, msg_sum
    call0 print_string

    ; Print xorResult
    beqz a7, print_xor_zero
    l32r a9, msg_one
    j print_xor
print_xor_zero:
    l32r a9, msg_zero
print_xor:
    call0 print_string

    ; Print "Carry (AND): "
    l32r a9, msg_carry
    call0 print_string

    ; Print andResult
    beqz a8, print_and_zero
    l32r a9, msg_one
    j print_and
print_and_zero:
    l32r a9, msg_zero
print_and:
    call0 print_string

    ; Delay ~1000ms (busy loop)
    movi a15, DELAY_LOOP_COUNT
delay_loop2:
    addi a15, a15, -1
    bnez a15, delay_loop2

    j loop

; Subroutine: Print string via UART0
print_string:
    l8ui a10, a9, 0      ; Load byte
    beqz a10, print_done ; Null terminator
wait_tx:
    movi a11, UART0_STATUS_REG
    l32i a12, a11, 0
    extui a12, a12, 24, 8  ; TX FIFO count
    bgei a12, 128, wait_tx ; Wait if full
    movi a11, UART0_FIFO_REG
    s8i a10, a11, 0      ; Send byte
    addi a9, a9, 1       ; Next byte
    j print_string
print_done:
    ret

; String addresses (l32r needs relative addressing, assume placed appropriately)
msg_sum_addr:   .word msg_sum
msg_carry_addr: .word msg_carry
msg_zero_addr:  .word msg_zero
msg_one_addr:   .word msg_one
