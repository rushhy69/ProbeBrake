# 🏎️ Rushyy: PROBRAKE LC v4.1

**PROBRAKE LC** is a premium, aerospace-grade load-cell brake pedal tuning and calibration ecosystem. It combines a high-performance Arduino Leonardo firmware with a GPU-accelerated PySide6/QML desktop controller for professional sim-racing hardware.

---

## ✨ Key Features

### 🖥️ Desktop Control Panel (PySide6 / QML)
- **GPU-Accelerated UI**: Fluid, high-refresh-rate interface using Qt Quick.
- **Real-time Telemetry**: Live visual monitoring of Brake, Throttle, and Clutch axes.
- **Visual Curve Editor**: Interactive 10-point LUT (Look-Up Table) editor with real-time feedback.
- **Advanced Presets**: Five mathematical curve presets (Linear, Progressive, Degressive, S-Curve, Custom).
- **Fault Monitoring**: Instant visual alerts for sensor disconnects or overloads.
- **Settings Persistence**: All GUI preferences and last-used settings are automatically saved.
- **Demo Mode**: Full UI simulation for testing without hardware connected.

### 🔌 Arduino Firmware (v4.1 Optimized)
- **High-Speed Hot Path**: 1000Hz update rate with zero floating-point math (optimized Q10/Q16 fixed-point).
- **Advanced Filtering**: Fixed-point Kalman filter for ultra-stable load cell readings.
- **Direct ADC Access**: Bypass Arduino overhead for sub-15µs sensor sampling.
- **Safety First**: CRC16-protected EEPROM profiles, watchdog timer (WDT), and hardware fault detection.
- **Joystick Emulation**: Native USB HID support—works instantly with all major racing sims (iRacing, ACC, etc.).
- **ABS Rumble Support**: PWM output for pedal vibration motors based on brake pressure thresholds.

---

## 🛠️ Hardware Requirements

- **Microcontroller**: Arduino Leonardo or Pro Micro (ATmega32u4).
- **Brake**: Load Cell sensor with an INA333 (or similar) instrumentation amplifier (Analog Pin A0).
- **Throttle/Clutch**: 10K Potentiometers or Hall Effect sensors (Analog Pins A2 and A1).
- **Optional**: 
  - Profile switch button (Pin 7).
  - Status/Brake LEDs (Pins 13 and 9).
  - Rumble Motor (Pin 10).

---

## 🚀 Getting Started

### 1. Flash the Firmware
1. Install the [Arduino IDE](https://www.arduino.cc/en/software).
2. Install the **Joystick** library by Matthew Heironimus.
3. Open `loadcell_brake_leonardo/loadcell_brake_leonardo.ino`.
4. Select **Arduino Leonardo** under *Tools > Board*.
5. Select the correct **COM Port**.
6. Click **Upload**.

### 2. Setup the Desktop App
1. **Python 3.10+** is required.
2. Install dependencies:
   ```bash
   pip install PySide6 pyserial
   ```
3. Launch the application:
   ```bash
   python main.py
   ```

---

## 📂 Project Structure

- `main.py`: Entry point. Initializes the PySide6 application and the Serial-QML bridge.
- `probrake_gui.py`: Legacy CustomTkinter-based GUI (v4.0).
- `qml/`: Contains all QML UI files, including components, pages, and themes.
- `loadcell_brake_leonardo/`: The C++ Arduino firmware source code.
- `build_exe.py`: Script to package the Python app into a standalone Windows executable.
- `probrake_settings.json`: Stores user interface preferences.

---

## 🧠 Technical Overview

### The Serial Bridge
The desktop app uses a threaded `SerialIO` worker to handle high-frequency data without blocking the UI. Telemetry strings are parsed using optimized regex patterns:
`P(Profile) T:(Throttle)% B:(Brake)% C:(Clutch)%`

### Signal Processing
1. **Raw Sampling**: Sensors are oversampled 16x at the hardware level.
2. **Filtering**: A Kalman filter removes electrical noise while maintaining zero latency.
3. **Mapping**: Raw values are normalized and passed through the user-defined LUT curves.
4. **Output**: The final values are sent to the PC via USB HID (Joystick) and to the UI via Serial.

---

## ⚖️ License
This project is provided for personal use. MIT License recommended for open-source distribution.

---

*Developed with ❤️ for the Sim-Racing Community.*
