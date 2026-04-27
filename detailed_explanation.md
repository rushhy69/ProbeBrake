# 🧠 Rushyy PROBRAKE LC: Technical Deep Dive

The **PROBRAKE LC** system is a sophisticated bridge between precision hardware sensors and high-fidelity sim-racing software. This document provides a detailed explanation of the core technical concepts, optimizations, and architectural decisions.

---

## 🏗️ System Architecture

The project follows a hybrid architecture consisting of three main layers:

1.  **Hardware Layer (Firmware)**: An Arduino Leonardo (ATmega32u4) handles real-time sensor sampling, filtering, and USB HID joystick emulation.
2.  **Bridge Layer (Serial)**: A bidirectional serial communication protocol connects the hardware to the desktop software.
3.  **UI Layer (PySide6 / QML)**: A GPU-accelerated desktop application for calibration, tuning, and real-time visualization.

---

## ⚡ Firmware Optimizations (v4.1)

The firmware is designed for extreme responsiveness and stability. In sim-racing, even a few milliseconds of latency can affect muscle memory.

### 1. Zero Floating-Point Math (Fixed-Point Q10/Q16)
Standard floating-point operations on an 8-bit AVR processor (like the ATmega32u4) are extremely slow because they are emulated in software. 
- **Q10 format**: Used for general scaling (1.0 = 1024).
- **Q16 format**: Used for high-precision Kalman filtering (1.0 = 65536).
- **Result**: The main loop runs significantly faster, consistently maintaining a 1000Hz update rate.

### 2. Direct ADC Manipulation
The firmware bypasses the standard Arduino `analogRead()` function.
- **Standard `analogRead()`**: ~112µs (includes overhead and safety checks).
- **Direct Register Access**: ~13µs to 15µs.
- **Impact**: Allows for higher oversampling rates (16x) without sacrificing loop frequency.

### 3. Kalman Filtering for Load Cells
Load cells produce very low-voltage signals that are susceptible to electrical noise.
- The firmware implements a **fixed-point Kalman filter**.
- It predicts the next sensor state and adjusts based on the measured value, effectively removing "jitter" while keeping the signal responsive to rapid pressure changes.

### 4. CRC16 Protected Profiles
To prevent settings corruption, all profiles stored in the EEPROM are protected by a **CRC16-CCITT checksum**. If a profile fails validation, the firmware safely reverts to defaults rather than using corrupt calibration data.

---

## 🌉 The Serial Protocol

The desktop app and hardware communicate over a high-speed 115200 baud serial link.

### Telemetry String Format (Outbound)
Every ~7ms, the Arduino sends a telemetry packet:
`P1 T:0% B:45% C:0%`
- `P1`: Active Profile (1-3).
- `T`: Throttle Percentage.
- `B`: Brake Percentage.
- `C`: Clutch Percentage.

### Command Format (Inbound)
The desktop app sends commands to tune the hardware on the fly:
- `tmin`, `tmax`: Set throttle calibration limits.
- `bcurve 1`: Set brake curve to Progressive.
- `blut 0 10 25...`: Set a custom 10-point Look-Up Table for the brake.

---

## 🎨 Desktop Integration (PySide6 + QML)

The desktop application uses **PySide6** (Qt for Python) to leverage the power of **QML** for the interface.

### The Backend Bridge (`SerialBackend`)
The `SerialBackend` class (in `main.py`) acts as the "Controller" in the MVC pattern.
- It inherits from `QObject`.
- It uses **Qt Properties** (`@Property`) and **Signals** (`Signal`) to bind Python data (like brake percentage) directly to QML UI components.
- When a new telemetry value arrives from Serial, Python emits a signal, and the QML UI updates automatically via the highly efficient Qt property binding system.

### GPU Acceleration
By setting `QT_QUICK_CONTROLS_STYLE = "Basic"`, the application ensures that complex UI elements like the 10-point LUT editor and high-refresh-rate gauges are rendered via the GPU using OpenGL or Direct3D, resulting in 60+ FPS fluidity.

---

## 📈 Signal Processing Flow

1.  **ADC Sampling**: 16x oversampled raw read.
2.  **Kalman Filter**: Noise removal.
3.  **Normalization**: Raw value scaled to 0.0 - 1.0 range based on `Min/Max` calibration.
4.  **Deadzone**: Application of inner and outer deadzones.
5.  **Curve/LUT**: Transformation of the linear signal into a user-defined response curve.
6.  **HID Output**: Sending the final 10-bit value to the Windows Joystick driver.
7.  **Serial Output**: Sending the percentage to the Control Panel.

---

*This technical documentation is intended for developers and power users looking to understand or modify the Rushyy ecosystem.*
