# 🧮 AVR Matrix Calculator

A hardware calculator built on the **ATmega328P** microcontroller, written entirely
in AVR Assembly. It features a 4×4 matrix keypad for input and a multiplexed 
7×5 LED matrix display for output — no operating system, no libraries, just 
bare-metal assembly.

---

## ✨ Features

- Basic arithmetic: **Addition, Subtraction, Multiplication, Division, Modulo**
- Correct **operator precedence** — `3 + 4 * 2 = 11`
- 16-character **7×5 LED matrix display** driven by shift registers
- **Debounced keypad** scanning — no ghost presses
- **Timer-driven** display multiplexing via Timer0 interrupt
- **Stack-based expression evaluator** (shunting-yard algorithm)
- **Full clear** via dedicated reset button (PB2)

---

## 🔧 Hardware Components

| Component       | Details                        |
|-----------------|--------------------------------|
| MCU             | ATmega328P                     |
| Input           | 4×4 matrix keypad              |
| Display         | 7×5 LED matrix (16 characters) |
| Display Driver  | Shift Register                 |
| Clock           | Timer0, CTC mode, 1ms tick     |

---

## 📌 Pin Mapping

### 4×4 Matrix Keypad — PORTD

| Pin  | Function        |
|------|-----------------|
| PD7  | Row 1 (output)  |
| PD6  | Row 2 (output)  |
| PD5  | Row 3 (output)  |
| PD4  | Row 4 (output)  |
| PD3  | Column 1 (input)|
| PD2  | Column 2 (input)|
| PD1  | Column 3 (input)|
| PD0  | Column 4 (input)|

### 7×5 LED Matrix (via Shift Register) — PORTB

| Pin  | Function                  |
|------|---------------------------|
| PB3  | SDI — Serial Data Input   |
| PB4  | MOSI — Data               |
| PB5  | Latch — Storage Clock     |

### Other

| Pin  | Function            |
|------|---------------------|
| PB2  | Clear / Reset Button|

---
