; AVR Assembly for ATmega328P: Soil-Based Logic Gates Control
; Equivalent to Arduino C++ code for XOR/AND half-adder
; Configures pins, applies inputs, reads analog outputs, and sends results via serial

; Register definitions
.equ XOR_INPUT_A, 1      ; PB1 (Pin 9)
.equ XOR_INPUT_B, 2      ; PB2 (Pin 10)
.equ AND_INPUT_A, 3      ; PB3 (Pin 11)
.equ AND_INPUT_B, 4      ; PB4 (Pin 12)
.equ XOR_OUTPUT, 0       ; PC0 (A0)
.equ AND_OUTPUT, 1       ; PC1 (A1)
.equ BAUD_PRESCALE, 103  ; (16MHz / (16 * 9600)) - 1 = 103 for 9600 baud

; String constants in program memory
.section .text
msg_sum:   .asciz "Sum (XOR): "
msg_carry: .asciz "Carry (AND): "
msg_zero:  .asciz "0\n"
msg_one:   .asciz "1\n"

.global main
main:
    ; Initialize stack
    ldi r16, low(RAMEND)
    out SPL, r16
    ldi r16, high(RAMEND)
    out SPH, r16

    ; Setup pins as outputs (PB1, PB2, PB3, PB4)
    ldi r16, (1<<XOR_INPUT_A) | (1<<XOR_INPUT_B) | (1<<AND_INPUT_A) | (1<<AND_INPUT_B)
    out DDRB, r16

    ; Setup serial communication (9600 baud)
    ldi r16, 0
    sts UCSR0A, r16
    ldi r16, (1<<TXEN0)         ; Enable transmitter
    sts UCSR0B, r16
    ldi r16, (1<<UCSZ01) | (1<<UCSZ00) ; 8-bit data
    sts UCSR0C, r16
    ldi r16, low(BAUD_PRESCALE)
    sts UBRR0L, r16
    ldi r16, high(BAUD_PRESCALE)
    sts UBRR0H, r16

    ; Setup ADC (AVCC reference, ADC enabled, prescaler 128)
    ldi r16, (1<<REFS0)         ; AVCC reference
    sts ADMUX, r16
    ldi r16, (1<<ADEN) | (1<<ADPS2) | (1<<ADPS1) | (1<<ADPS0) ; Enable ADC, /128
    sts ADCSRA, r16

    ; Setup Timer1 for 1000ms delay
    ldi r16, (1<<WGM12)         ; CTC mode
    sts TCCR1B, r16
    ldi r16, high(15625)        ; 16MHz / 1024 / 1000ms = 15625
    sts OCR1AH, r16
    ldi r16, low(15625)
    sts OCR1AL, r16

loop:
    ; Set inputs: A=0 (LOW), B=1 (HIGH) for XOR and AND
    cbi PORTB, XOR_INPUT_A      ; Set PB1 low (0V)
    sbi PORTB, XOR_INPUT_B      ; Set PB2 high (5V)
    cbi PORTB, AND_INPUT_A      ; Set PB3 low (0V)
    sbi PORTB, AND_INPUT_B      ; Set PB4 high (5V)

    ; Delay 1000ms for soil response
    rcall delay_1000ms

    ; Read XOR output (A0/PC0)
    ldi r16, (1<<REFS0) | XOR_OUTPUT ; Select ADC0
    sts ADMUX, r16
    ldi r16, (1<<ADEN) | (1<<ADSC) | (1<<ADPS2) | (1<<ADPS1) | (1<<ADPS0)
    sts ADCSRA, r16
wait_adc_xor:
    sbis ADCSRA, ADSC
    rjmp adc_xor_done
    rjmp wait_adc_xor
adc_xor_done:
    lds r16, ADCL
    lds r17, ADCH               ; r17:r16 = ADC result
    ldi r18, low(512)           ; Threshold = 512
    ldi r19, high(512)
    cp r16, r18
    cpc r17, r19
    brlo xor_zero
    ldi r20, 1                  ; r20 = xorResult (1)
    rjmp xor_done
xor_zero:
    ldi r20, 0                  ; r20 = xorResult (0)
xor_done:

    ; Read AND output (A1/PC1)
    ldi r16, (1<<REFS0) | AND_OUTPUT ; Select ADC1
    sts ADMUX, r16
    ldi r16, (1<<ADEN) | (1<<ADSC) | (1<<ADPS2) | (1<<ADPS1) | (1<<ADPS0)
    sts ADCSRA, r16
wait_adc_and:
    sbis ADCSRA, ADSC
    rjmp adc_and_done
    rjmp wait_adc_and
adc_and_done:
    lds r16, ADCL
    lds r17, ADCH               ; r17:r16 = ADC result
    ldi r18, low(614)           ; Threshold = 614
    ldi r19, high(614)
    cp r16, r18
    cpc r17, r19
    brlo and_zero
    ldi r21, 1                  ; r21 = andResult (1)
    rjmp and_done
and_zero:
    ldi r21, 0                  ; r21 = andResult (0)
and_done:

    ; Print "Sum (XOR): "
    ldi r30, low(2*msg_sum)     ; Z = msg_sum address
    ldi r31, high(2*msg_sum)
    rcall print_string

    ; Print xorResult (0 or 1)
    cpi r20, 0
    breq print_xor_zero
    ldi r30, low(2*msg_one)
    ldi r31, high(2*msg_one)
    rjmp print_xor
print_xor_zero:
    ldi r30, low(2*msg_zero)
    ldi r31, high(2*msg_zero)
print_xor:
    rcall print_string

    ; Print "Carry (AND): "
    ldi r30, low(2*msg_carry)
    ldi r31, high(2*msg_carry)
    rcall print_string

    ; Print andResult (0 or 1)
    cpi r21, 0
    breq print_and_zero
    ldi r30, low(2*msg_one)
    ldi r31, high(2*msg_one)
    rjmp print_and
print_and_zero:
    ldi r30, low(2*msg_zero)
    ldi r31, high(2*msg_zero)
print_and:
    rcall print_string

    ; Delay 1000ms for cycle
    rcall delay_1000ms

    rjmp loop

; Subroutine: Print string via UART
print_string:
    lpm r16, Z+                 ; Load byte from program memory
    cpi r16, 0                  ; Check for null terminator
    breq print_done
wait_tx:
    sbis UCSR0A, UDRE0          ; Wait for transmit buffer empty
    rjmp wait_tx
    sts UDR0, r16               ; Send byte
    rjmp print_string
print_done:
    ret

; Subroutine: 1000ms delay using Timer1
delay_1000ms:
    ldi r16, 0
    sts TCNT1H, r16             ; Clear timer
    sts TCNT1L, r16
    ldi r16, (1<<CS12) | (1<<CS10) ; Start timer, prescaler 1024
    sts TCCR1B, r16
wait_timer:
    sbis TIFR1, OCF1A           ; Wait for compare match
    rjmp wait_timer
    sbi TIFR1, OCF1A            ; Clear flag
    ldi r16, (1<<WGM12)         ; Stop timer, keep CTC
    sts TCCR1B, r16
    ret

.section .data
; No SRAM data needed
