# 🧮 AVR Matrix Calculator

A hardware calculator built on the **ATmega328P** microcontroller, written entirely in AVR Assembly. It features a 4×4 matrix keypad for input and a multiplexed 7-row LED matrix display for output — no operating system, no libraries, just bare-metal assembly.

---

## ✨ Features

- Basic arithmetic: **Addition, Subtraction, Multiplication, Division, Modulo**
- Correct **operator precedence** — `3 + 4 * 2 = 11`
- 16-character **LED matrix display** driven by shift registers
- **Debounced keypad** scanning — no ghost presses
- **Timer-driven** display multiplexing via Timer0 interrupt
- **Stack-based expression evaluator** (shunting-yard algorithm)
- **Full clear** via dedicated reset button

---

## 🔧 Hardware

| Component | Details |
|-----------|---------|
| MCU | ATmega328P |
| Input | 4×4 matrix keypad |
| Display | 7-row × 16-col LED matrix |
| Drive | Shift registers (SPI-style via PORTB) |
| Clock | Timer0, CTC mode, 1ms tick |

---

## ⌨️ Keypad Layout
[ 1 ] [ 2 ] [ 3 ] [ + ]
[ 4 ] [ 5 ] [ 6 ] [ - ]
[ 7 ] [ 8 ] [ 9 ] [ × ]
[ % ] [ 0 ] [ = ] [ ÷ ]
