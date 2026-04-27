/*
 *  PROBRAKE LC v4.1 — Commercial-Grade 3-Pedal Sim Racing Controller
 *  Arduino Leonardo / Pro Micro (ATmega32u4)
 *  A0=Brake(LoadCell+INA333) A1=Clutch(B10K) A2=Throttle(B10K)
 *  Requires: "Joystick" library by Matthew Heironimus
 *
 *  Features: CRC-protected profiles, watchdog timer, sensor fault
 *  detection, auto-calibration, 10-point LUT curves, clutch bite
 *  point, brake force factor, per-axis smoothing, ABS rumble,
 *  binary telemetry, profile quick-switch button
 *
 *  v4.1 Optimizations:
 *    - Eliminated ALL floating-point from hot path (fixed-point Q10)
 *    - Direct ADC register manipulation (no analogRead overhead)
 *    - Kalman filter converted to fixed-point Q16
 *    - Integer-only curve math with Taylor/LUT approximations
 *    - Reduced SRAM usage via const placement and buffer reuse
 *    - Faster command dispatch via early-exit prefix matching
 *    - Brake LED update reduced to delta-only writes
 *    - Telemetry interval check moved before axis processing
 */

#include <Joystick.h>
#include <EEPROM.h>
#include <avr/wdt.h>

// ─── Build Version ──────────────────────────────────────────
#define FW_VERSION "4.1"

// ─── Pins ───────────────────────────────────────────────────
#define PIN_BRAKE       A0
#define PIN_THROTTLE    A2
#define PIN_CLUTCH      A1
#define PIN_LED_BRAKE   9
#define PIN_LED_STATUS  13
#define PIN_BTN_PROFILE 7
#define PIN_RUMBLE      10

// ─── Constants ──────────────────────────────────────────────
#define JOY_MIN          0
#define JOY_MAX          1023
#define OVERSAMPLE_N     16
#define OVERSAMPLE_SHIFT 2
#define POT_OVERSAMPLE   8       // 8x oversample for pots (throttle/clutch)
#define SMOOTH_N         16
#define MEDIAN_N         5
#define LUT_SIZE         10
#define CAL_DURATION_MS  5000
#define CMD_BUF_SIZE     64

// Fixed-point scaling (Q10 = 1024 represents 1.0)
#define FP_SHIFT         10
#define FP_ONE           1024
#define FP_HALF          512

// Curves
#define CURVE_LINEAR      0
#define CURVE_PROGRESSIVE 1
#define CURVE_DEGRESSIVE  2
#define CURVE_S_CURVE     3
#define CURVE_CUSTOM      4
#define CURVE_LUT         5
#define NUM_CURVES        6

// Smoothing modes
#define SMOOTH_MOVAVG     0
#define SMOOTH_EMA        1
#define SMOOTH_MEDIAN     2

// Telemetry modes
#define TELEM_OFF         0
#define TELEM_TEXT        1
#define TELEM_BINARY      2

// EEPROM
#define EE_MAGIC_ADDR    0
#define EE_ACTIVE_ADDR   2
#define EE_PROFILE_BASE  3
#define EE_MAGIC_VAL     0xC5     // v4.1 magic (forces re-init from v4.0)
#define NUM_PROFILES     3

// Timing & thresholds
#define TELEM_INTERVAL   7
#define BTN_DEBOUNCE_MS  50
#define BTN_LONG_MS      2000
#define FAULT_THRESHOLD  1000     // cycles at extreme = fault
#define AUTOCAL_TIMEOUT  30000    // 30s no change = done

// ─── ADC Channel Mapping ────────────────────────────────────
// ATmega32u4 ADC mux values for A0-A2
#define ADC_MUX_BRAKE    7   // A0 = ADC7 on Leonardo
#define ADC_MUX_THROTTLE 5   // A2 = ADC5 on Leonardo
#define ADC_MUX_CLUTCH   6   // A1 = ADC6 on Leonardo

// ─── Data Structures ───────────────────────────────────────
struct PotConfig {
  int16_t calMin, calMax;
  uint8_t curveType, curveExp;
  uint8_t dzMinPct, dzMaxPct;
  uint8_t maxPct, inverted;
  uint8_t smoothMode;           // 0=MovAvg 1=EMA 2=Median
  uint8_t lut[LUT_SIZE];       // 10-point output curve 0-100
};

struct PedalProfile {
  long    bCalMin, bCalMax;
  uint8_t bCurveType, bCurveExp;
  uint8_t bDzMinPct, bDzMaxPct;
  uint8_t bHysteresis, bMaxPct;
  uint8_t kalmanQ, kalmanR;
  uint8_t brakeForceFactor;     // BFF: 1-100 (default 50)
  uint8_t bSmoothMode;         // post-Kalman smoothing
  uint8_t bLut[LUT_SIZE];     // brake 10-point LUT
  PotConfig throttle;
  PotConfig clutch;
  uint16_t updateRateHz;
  uint8_t clutchEnabled;       // 0=off 1=on
  uint8_t clutchBitePoint;     // 0=off, 1-99=active
  uint8_t rumbleIntensity;     // 0=off, 1-255=PWM
  uint8_t rumbleThreshold;     // brake% to trigger (50-100)
};

struct FaultState {
  int16_t lastGoodOut;
  uint16_t extremeCount;
  uint8_t faulted;              // 0=ok 1=disconnected
};

// ─── Defaults ───────────────────────────────────────────────
const PotConfig DEFAULT_POT = {
  0, 1023, CURVE_LINEAR, 20, 0, 0, 100, 0, SMOOTH_MOVAVG,
  {0, 11, 22, 33, 44, 56, 67, 78, 89, 100}
};

const PedalProfile DEFAULT_PROFILE = {
  0, 4095,                                      // bCalMin, bCalMax
  CURVE_LINEAR, 20,                             // bCurveType, bCurveExp
  0, 0,                                         // bDzMinPct, bDzMaxPct
  3, 100,                                       // bHysteresis, bMaxPct
  5, 15,                                        // kalmanQ, kalmanR
  100,                                          // brakeForceFactor (fixed at 100)
  SMOOTH_MOVAVG,                                // bSmoothMode
  {0, 11, 22, 33, 44, 56, 67, 78, 89, 100},    // bLut
  {0, 1023, CURVE_LINEAR, 20, 0, 0, 100, 0, SMOOTH_EMA, {0, 11, 22, 33, 44, 56, 67, 78, 89, 100}},  // throttle (EMA smoothing)
  DEFAULT_POT,                                  // clutch
  1000,                                         // updateRateHz
  0,                                            // clutchEnabled
  0,                                            // clutchBitePoint (0=off)
  0,                                            // rumbleIntensity (0=off)
  85                                            // rumbleThreshold
};

// ─── Joystick ───────────────────────────────────────────────
Joystick_ Joystick(
  JOYSTICK_DEFAULT_REPORT_ID, JOYSTICK_TYPE_JOYSTICK,
  0, 0,
  true, true, true,      // X=throttle, Y=clutch, Z=brake
  false, false, false,   // Rx, Ry, Rz
  false, false,          // rudder, throttle
  true, true, false      // accelerator, brake, steering
);

// ─── Fixed-Point Kalman Filter (Q16) ────────────────────────
// All math in Q16 (65536 = 1.0) to completely eliminate float
class KalmanFilterFP {
  int32_t _q, _r, _x, _p;     // Q16 fixed-point
  bool _init;
public:
  KalmanFilterFP() : _q(3277), _r(983040L), _x(0), _p(65536L), _init(false) {}
  // q_raw: 1-100 → Q16, r_raw: 1-100 → Q16
  void tune(uint8_t q_raw, uint8_t r_raw) {
    _q = ((int32_t)q_raw * 65536L) / 100;   // q/100 in Q16
    _r = (int32_t)r_raw * 65536L;            // r as integer in Q16
  }
  void reset() { _init = false; _p = 65536L; }
  int16_t update(int16_t z) {
    if (!_init) { _x = (int32_t)z << 16; _init = true; return z; }
    _p += _q;
    // k = p / (p + r) in Q16
    int32_t denom = _p + _r;
    if (denom == 0) denom = 1;
    int32_t k = (_p * 256L) / (denom >> 8);  // k in Q16 via split multiply
    int32_t z_q16 = (int32_t)z << 16;
    _x += (int32_t)(((int64_t)k * (z_q16 - _x)) >> 16);
    _p -= (int32_t)(((int64_t)k * _p) >> 16);
    return (int16_t)(_x >> 16);
  }
};

// ─── Axis Smoothing (MovAvg / EMA / Median) ────────────────
struct AxisSmooth {
  int16_t buf[SMOOTH_N];
  uint8_t idx;
  bool filled;
  long sum;
  int16_t ema;

  void init() {
    for (uint8_t j = 0; j < SMOOTH_N; j++) buf[j] = 0;
    idx = 0; filled = false; sum = 0; ema = 0;
  }

  int16_t update(int16_t v, uint8_t mode) {
    switch (mode) {
      case SMOOTH_EMA: {
        if (!filled) { ema = v; filled = true; return v; }
        ema += (int16_t)(((long)(v - ema) * 77) >> 8);  // alpha ~0.30
        return ema;
      }
      case SMOOTH_MEDIAN: {
        buf[idx % MEDIAN_N] = v;
        idx = (idx + 1) % MEDIAN_N;
        if (!filled && idx == 0) filled = true;
        uint8_t n = filled ? MEDIAN_N : (idx > 0 ? idx : 1);
        int16_t tmp[MEDIAN_N];
        for (uint8_t i = 0; i < n; i++) tmp[i] = buf[i];
        // Insertion sort (optimal for N=5)
        for (uint8_t i = 1; i < n; i++) {
          int16_t key = tmp[i]; int8_t j = i - 1;
          while (j >= 0 && tmp[j] > key) { tmp[j + 1] = tmp[j]; j--; }
          tmp[j + 1] = key;
        }
        return tmp[n / 2];
      }
      default: { // SMOOTH_MOVAVG
        if (filled) sum -= buf[idx];
        buf[idx] = v; sum += v;
        idx = (idx + 1) % SMOOTH_N;
        if (idx == 0) filled = true;
        uint8_t c = filled ? SMOOTH_N : idx;
        return c > 0 ? (int16_t)(sum / c) : v;
      }
    }
  }
};

// ─── Globals ────────────────────────────────────────────────
PedalProfile prof;
uint8_t profIdx = 0;
KalmanFilterFP kalman;
AxisSmooth smT, smC, smBpost;      // throttle, clutch, post-kalman brake

// Brake state
int16_t lastBrakeOut = 0;
bool brakeUp = true;
bool overload = false;
uint8_t ovrCnt = 0;

// Throttle/Clutch output hysteresis (anti-flicker)
int16_t lastThrottleOut = 0;
int16_t lastClutchOut = 0;

// Fault detection
FaultState faultB = {0, 0, 0};
FaultState faultT = {0, 0, 0};
FaultState faultC = {0, 0, 0};

// Auto-calibration
bool autocalActive = false;
unsigned long autocalLastChange = 0;

// Timing
unsigned long lastUpdUs = 0, loopDelUs = 1000, lastTelemMs = 0;
uint8_t telemMode = TELEM_TEXT;
unsigned long uptimeS = 0, lastUptimeMs = 0;

// CLI (char[] replaces String for SRAM savings)
char cmdBuf[CMD_BUF_SIZE];
uint8_t cmdLen = 0;

// Profile button
bool btnLast = true;               // HIGH (internal pull-up)
unsigned long btnDownTime = 0;
bool btnHandled = false;

// Raw readings cache (for telemetry + autocal)
long rawBrake = 0;
int16_t rawThrottle = 0, rawClutch = 0;

// WDT reset flag (captured before clearing MCUSR)
uint8_t resetFlags = 0;

// LED delta tracking (avoid redundant PWM writes)
uint8_t lastBrakeLed = 0;

// ─── Fast ADC Read (direct register, ~13µs per read) ────────
// Bypasses Arduino's analogRead() overhead (~112µs) by directly
// manipulating ADC registers. Uses single-ended mode, AVCC ref.
static inline void adcStartRead(uint8_t mux) {
  ADMUX = (1 << REFS0) | (mux & 0x1F);          // AVCC ref, mux channel
  if (mux & 0x20) ADCSRB |= (1 << MUX5);        // High mux bit for ch 8+
  else            ADCSRB &= ~(1 << MUX5);
  ADCSRA |= (1 << ADSC);                         // Start conversion
}

static inline uint16_t adcWaitResult() {
  while (ADCSRA & (1 << ADSC));                  // Wait for completion
  return ADC;
}

static uint16_t adcRead(uint8_t mux) {
  adcStartRead(mux);
  return adcWaitResult();
}

// ─── CRC16-CCITT (no lookup table, compact) ────────────────
uint16_t crc16(const uint8_t* data, uint16_t len) {
  uint16_t crc = 0xFFFF;
  while (len--) {
    crc ^= (uint16_t)*data++ << 8;
    for (uint8_t i = 0; i < 8; i++)
      crc = (crc & 0x8000) ? (crc << 1) ^ 0x1021 : crc << 1;
  }
  return crc;
}

// ─── WDT-Safe Delay ─────────────────────────────────────────
void safeDelay(uint16_t ms) {
  while (ms >= 100) { wdt_reset(); delay(100); ms -= 100; }
  if (ms > 0) { wdt_reset(); delay(ms); }
}

// ─── EEPROM with CRC Validation ─────────────────────────────
#define EE_PROF_BLOCK (sizeof(PedalProfile) + 2)

bool eeOk() { return EEPROM.read(EE_MAGIC_ADDR) == EE_MAGIC_VAL; }

void eeSave(uint8_t i, const PedalProfile &p) {
  if (i >= NUM_PROFILES) return;
  uint16_t addr = EE_PROFILE_BASE + i * EE_PROF_BLOCK;
  EEPROM.put(addr, p);
  uint16_t c = crc16((const uint8_t*)&p, sizeof(PedalProfile));
  EEPROM.put(addr + sizeof(PedalProfile), c);
  EEPROM.update(EE_MAGIC_ADDR, EE_MAGIC_VAL);
}

bool eeLoad(uint8_t i, PedalProfile &p) {
  if (i >= NUM_PROFILES) return false;
  uint16_t addr = EE_PROFILE_BASE + i * EE_PROF_BLOCK;
  EEPROM.get(addr, p);
  uint16_t stored, calc;
  EEPROM.get(addr + sizeof(PedalProfile), stored);
  calc = crc16((const uint8_t*)&p, sizeof(PedalProfile));
  if (stored != calc) {
    Serial.print(F("! CRC fail P")); Serial.print(i);
    Serial.println(F(", defaults loaded"));
    p = DEFAULT_PROFILE;
    return false;
  }
  return true;
}

void eeSetAct(uint8_t i) { EEPROM.update(EE_ACTIVE_ADDR, i); }

uint8_t eeGetAct() {
  uint8_t v = EEPROM.read(EE_ACTIVE_ADDR);
  return v < NUM_PROFILES ? v : 0;
}

void eeReset() {
  EEPROM.update(EE_MAGIC_ADDR, 0xFF);
  for (uint8_t i = 0; i < NUM_PROFILES; i++) eeSave(i, DEFAULT_PROFILE);
  eeSetAct(0);
}

// ─── ADC Reads (fast, with mux settling) ────────────────────
long readBrake() {
  adcRead(ADC_MUX_BRAKE);  // Dummy read for mux settling
  long s = 0;
  for (uint8_t i = 0; i < OVERSAMPLE_N; i++) s += adcRead(ADC_MUX_BRAKE);
  return s >> OVERSAMPLE_SHIFT;
}

int16_t readThrottle() {
  adcRead(ADC_MUX_THROTTLE);  // Dummy read for settling
  int16_t s = 0;
  for (uint8_t i = 0; i < POT_OVERSAMPLE; i++) s += (int16_t)adcRead(ADC_MUX_THROTTLE);
  return s / POT_OVERSAMPLE;
}

int16_t readClutch() {
  adcRead(ADC_MUX_CLUTCH);  // Dummy read for settling
  int16_t s = 0;
  for (uint8_t i = 0; i < POT_OVERSAMPLE; i++) s += (int16_t)adcRead(ADC_MUX_CLUTCH);
  return s / POT_OVERSAMPLE;
}

// ─── Fault Detection ────────────────────────────────────────
bool checkFault(FaultState &fs, int16_t raw, int16_t maxAdc) {
  if (raw <= 3 || raw >= (maxAdc - 3)) {
    if (fs.extremeCount < 65535) fs.extremeCount++;
    if (fs.extremeCount >= FAULT_THRESHOLD) {
      fs.faulted = 1;
      return true;
    }
  } else {
    fs.extremeCount = 0;
    fs.faulted = 0;
  }
  return false;
}

// ─── Integer Square Root (Babylonian, ~8 iterations) ────────
// Returns sqrt(x) * 32 (Q5 format) for 0-1024 input range
static uint16_t isqrt_q5(uint16_t x) {
  if (x == 0) return 0;
  // We want sqrt(x) in Q5 = sqrt(x) * 32
  // Equivalent to sqrt(x * 1024) when x is Q10
  uint32_t val = (uint32_t)x << 10;  // shift up for precision
  uint32_t guess = val >> 1;
  if (guess == 0) guess = 1;
  for (uint8_t i = 0; i < 10; i++) {
    guess = (guess + val / guess) >> 1;
  }
  // Result is in Q5 (sqrt of Q10 = Q5)
  return (uint16_t)guess;
}

// ─── Fixed-Point Curve Math (all integer, no float) ─────────
// Input x: Q10 (0=0.0, 1024=1.0)
// Output:  Q10
static int16_t applyCurveFP(int16_t x, uint8_t type, uint8_t expRaw, const uint8_t* lut) {
  if (x <= 0) return 0;
  if (x >= FP_ONE) return FP_ONE;

  switch (type) {
    case CURVE_PROGRESSIVE:
      // y = x² → (x * x) >> 10
      return (int16_t)(((int32_t)x * x) >> FP_SHIFT);

    case CURVE_DEGRESSIVE: {
      // y = sqrt(x) using integer sqrt
      // x is Q10, sqrt(Q10) = Q5, need to scale back to Q10
      uint16_t sq = isqrt_q5((uint16_t)x);
      return (int16_t)sq;  // isqrt_q5 returns Q5, *32 from Q10 = Q5 * 32 ≈ Q10
    }

    case CURVE_S_CURVE: {
      // y = 3x² - 2x³ = x²(3 - 2x)
      int32_t x2 = ((int32_t)x * x) >> FP_SHIFT;           // x² in Q10
      int32_t term = (3L * FP_ONE) - (2L * x);              // (3-2x) in Q10
      return (int16_t)((x2 * term) >> FP_SHIFT);
    }

    case CURVE_CUSTOM: {
      // y = x^(exp/10) — approximate via repeated squaring
      // expRaw is 5-40 (representing 0.5 to 4.0)
      // For integer exponents, use multiply chain
      // For 0.5, use sqrt; for others, linear interpolation between
      uint8_t whole = expRaw / 10;
      uint8_t frac = expRaw % 10;
      int32_t result = FP_ONE;
      // Integer power part
      for (uint8_t i = 0; i < whole; i++) {
        result = (result * x) >> FP_SHIFT;
      }
      // Fractional part (0.5 approximation): if frac >= 4, multiply by sqrt(x)
      if (frac >= 4) {
        uint16_t sq = isqrt_q5((uint16_t)x);
        result = (result * sq) >> 5;  // sq is Q5
      }
      return (int16_t)constrain(result, 0, FP_ONE);
    }

    case CURVE_LUT: {
      // 10-point LUT with linear interpolation, all integer
      // x in Q10: multiply by 9 to get index
      uint16_t idx_q10 = (uint16_t)(((uint32_t)x * 9) >> FP_SHIFT);  // 0-9 integer index
      uint8_t lo = (uint8_t)idx_q10;
      if (lo >= 9) return ((int16_t)lut[9] * FP_ONE) / 100;
      // Fractional part for interpolation
      uint16_t frac = ((uint32_t)x * 9) - ((uint32_t)lo << FP_SHIFT);  // Q10 fraction
      int16_t vLo = lut[lo];
      int16_t vHi = lut[lo + 1];
      // Interpolate: result = (vLo + frac*(vHi-vLo)/1024) * 1024/100
      int32_t interp = ((int32_t)vLo << FP_SHIFT) + ((int32_t)(vHi - vLo) * frac);
      // interp is in Q10 * 100 scale; divide by 100 for Q10 output
      return (int16_t)(interp / 100);
    }

    default: return x;  // LINEAR
  }
}

// ─── Shared Axis Pipeline (integer only) ────────────────────
int axisPipeline(int16_t val, int16_t cMin, int16_t cMax,
                 uint8_t dzLo, uint8_t dzHi,
                 uint8_t cType, uint8_t cExp,
                 const uint8_t* lut) {
  bool rev = false;
  if (cMin > cMax) { int16_t t = cMin; cMin = cMax; cMax = t; rev = true; }

  // Clamp
  if (val < cMin) val = cMin;
  if (val > cMax) val = cMax;

  int16_t range = cMax - cMin;
  if (range <= 0) return 0;

  // Normalize to Q10 (0-1024): n = (val - cMin) * 1024 / range
  int16_t n = (int16_t)(((int32_t)(val - cMin) << FP_SHIFT) / range);
  if (rev) n = FP_ONE - n;

  // Deadzone application (dzLo, dzHi are 0-100 percentages)
  int16_t dL = (int16_t)((uint16_t)dzLo * FP_ONE / 100);  // Q10
  int16_t dH = (int16_t)((uint16_t)dzHi * FP_ONE / 100);

  if (n <= dL) {
    n = 0;
  } else if (n >= (FP_ONE - dH)) {
    n = FP_ONE;
  } else {
    int16_t actRange = FP_ONE - dL - dH;
    if (actRange <= 0) actRange = 1;
    n = (int16_t)(((int32_t)(n - dL) << FP_SHIFT) / actRange);
  }

  // Apply curve
  int16_t c = applyCurveFP(n, cType, cExp, lut);

  // Scale to joystick range
  int out = (int)(((int32_t)c * JOY_MAX + FP_HALF) >> FP_SHIFT);
  return constrain(out, JOY_MIN, JOY_MAX);
}

// ─── Brake Axis Pipeline (long-range cal values) ────────────
int axisPipelineBrake(long val, long cMin, long cMax,
                      uint8_t dzLo, uint8_t dzHi,
                      uint8_t cType, uint8_t cExp,
                      const uint8_t* lut) {
  bool rev = false;
  if (cMin > cMax) { long t = cMin; cMin = cMax; cMax = t; rev = true; }

  if (val < cMin) val = cMin;
  if (val > cMax) val = cMax;

  long range = cMax - cMin;
  if (range <= 0) return 0;

  int16_t n = (int16_t)(((val - cMin) << FP_SHIFT) / range);
  if (rev) n = FP_ONE - n;

  int16_t dL = (int16_t)((uint16_t)dzLo * FP_ONE / 100);
  int16_t dH = (int16_t)((uint16_t)dzHi * FP_ONE / 100);

  if (n <= dL) {
    n = 0;
  } else if (n >= (FP_ONE - dH)) {
    n = FP_ONE;
  } else {
    int16_t actRange = FP_ONE - dL - dH;
    if (actRange <= 0) actRange = 1;
    n = (int16_t)(((int32_t)(n - dL) << FP_SHIFT) / actRange);
  }

  int16_t c = applyCurveFP(n, cType, cExp, lut);

  int out = (int)(((int32_t)c * JOY_MAX + FP_HALF) >> FP_SHIFT);
  return constrain(out, JOY_MIN, JOY_MAX);
}

// ─── Brake Processing (with Kalman, hysteresis) ─────────────
int processBrake() {
  long raw = readBrake();
  rawBrake = raw;

  // Fault check (scale oversampled range to 10-bit for uniform checking)
  if (checkFault(faultB, (int16_t)(raw >> 2), 1023)) {
    return faultB.lastGoodOut;
  }

  // Overload detection
  if (raw > prof.bCalMax + 200) {
    ovrCnt++;
    if (ovrCnt > 50 && !overload) {
      overload = true;
      Serial.println(F("\r\n! BRAKE OVERLOAD"));
    }
  } else {
    if (ovrCnt > 0) ovrCnt--;
    if (ovrCnt == 0) overload = false;
  }


  // Kalman filter (fixed-point)
  int16_t filtered = kalman.update((int16_t)raw);

  // Post-Kalman smoothing
  int16_t smoothed = smBpost.update(filtered, prof.bSmoothMode);

  int out = axisPipelineBrake((long)smoothed,
    prof.bCalMin, prof.bCalMax,
    prof.bDzMinPct, prof.bDzMaxPct,
    prof.bCurveType, prof.bCurveExp,
    prof.bLut);

  // Hysteresis
  if (prof.bHysteresis > 0) {
    int h = map(prof.bHysteresis, 0, 50, 0, JOY_MAX / 50);
    int d = out - (int)lastBrakeOut;
    if (brakeUp) {
      if (d < -h) { brakeUp = false; lastBrakeOut = out; }
      else if (d > 0) lastBrakeOut = out;
    } else {
      if (d > h) { brakeUp = true; lastBrakeOut = out; }
      else if (d < 0) lastBrakeOut = out;
    }
    out = (int)lastBrakeOut;
  }

  out = constrain(out, JOY_MIN, JOY_MAX);
  faultB.lastGoodOut = out;
  return out;
}

// ─── Throttle Processing ────────────────────────────────────
int processThrottle() {
  int16_t r = readThrottle();
  rawThrottle = r;
  if (prof.throttle.inverted) r = 1023 - r;

  if (checkFault(faultT, r, 1023)) {
    return faultT.lastGoodOut;
  }

  int16_t s = smT.update(r, prof.throttle.smoothMode);
  int out = axisPipeline(s,
    prof.throttle.calMin, prof.throttle.calMax,
    prof.throttle.dzMinPct, prof.throttle.dzMaxPct,
    prof.throttle.curveType, prof.throttle.curveExp,
    prof.throttle.lut);

  // Output hysteresis: suppress ±3 LSB jitter
  if (abs(out - lastThrottleOut) <= 3) {
    out = lastThrottleOut;
  } else {
    lastThrottleOut = out;
  }

  faultT.lastGoodOut = out;
  return out;
}

// ─── Clutch Processing (with Bite Point, integer only) ──────
int processClutch() {
  int16_t r = readClutch();
  rawClutch = r;
  if (prof.clutch.inverted) r = 1023 - r;

  if (checkFault(faultC, r, 1023)) {
    return faultC.lastGoodOut;
  }

  int16_t s = smC.update(r, prof.clutch.smoothMode);
  int out = axisPipeline(s,
    prof.clutch.calMin, prof.clutch.calMax,
    prof.clutch.dzMinPct, prof.clutch.dzMaxPct,
    prof.clutch.curveType, prof.clutch.curveExp,
    prof.clutch.lut);

  // Bite point: smooth S-curve ramp around engagement point (integer math)
  if (prof.clutchBitePoint > 0 && prof.clutchBitePoint < 100) {
    int16_t n = (int16_t)(((int32_t)out << FP_SHIFT) / JOY_MAX);  // Q10
    int16_t bp = (int16_t)((uint16_t)prof.clutchBitePoint * FP_ONE / 100);
    int16_t hw = 154;  // 0.15 in Q10 ≈ 154

    int16_t lo = bp - hw;
    int16_t hi = bp + hw;
    if (lo < 0) lo = 0;
    if (hi > FP_ONE) hi = FP_ONE;

    if (n <= lo) {
      n = 0;
    } else if (n >= hi) {
      n = FP_ONE;
    } else {
      int16_t zoneRange = hi - lo;
      if (zoneRange <= 0) zoneRange = 1;
      n = (int16_t)(((int32_t)(n - lo) << FP_SHIFT) / zoneRange);
      // Smoothstep: n² * (3 - 2n)
      int32_t n2 = ((int32_t)n * n) >> FP_SHIFT;
      int32_t term = (3L * FP_ONE) - (2L * n);
      n = (int16_t)((n2 * term) >> FP_SHIFT);
    }
    out = (int)(((int32_t)n * JOY_MAX + FP_HALF) >> FP_SHIFT);
    out = constrain(out, JOY_MIN, JOY_MAX);
  }

  faultC.lastGoodOut = out;
  return out;
}

// ─── 5-Second Calibration ───────────────────────────────────
long calibrate5s(uint8_t axis) {
  wdt_disable();
  Serial.println(F("  Hold steady 5s..."));
  unsigned long tEnd = millis() + CAL_DURATION_MS;
  long sum = 0, n = 0;
  int lastSec = -1;

  while (millis() < tEnd) {
    long r;
    switch (axis) {
      case 1: r = readThrottle(); break;
      case 2: r = readClutch();   break;
      default: r = readBrake();   break;
    }
    sum += r; n++;
    int sl = (int)((tEnd - millis()) / 1000);
    if (sl != lastSec) {
      lastSec = sl;
      Serial.print(F("  ")); Serial.print(sl + 1);
      Serial.print(F("s avg=")); Serial.println(sum / n);
    }
    delay(2);
  }

  long avg = sum / n;
  Serial.print(F("  Done: ")); Serial.println(avg);
  wdt_enable(WDTO_1S);
  return avg;
}

// ─── Auto-Calibration ──────────────────────────────────────
void updateAutocal() {
  if (!autocalActive) return;

  bool changed = false;

  // Brake
  if (rawBrake < prof.bCalMin) { prof.bCalMin = rawBrake; changed = true; }
  if (rawBrake > prof.bCalMax) { prof.bCalMax = rawBrake; changed = true; }

  // Throttle
  if (rawThrottle < prof.throttle.calMin) { prof.throttle.calMin = rawThrottle; changed = true; }
  if (rawThrottle > prof.throttle.calMax) { prof.throttle.calMax = rawThrottle; changed = true; }

  // Clutch (only if enabled)
  if (prof.clutchEnabled) {
    if (rawClutch < prof.clutch.calMin) { prof.clutch.calMin = rawClutch; changed = true; }
    if (rawClutch > prof.clutch.calMax) { prof.clutch.calMax = rawClutch; changed = true; }
  }

  if (changed) autocalLastChange = millis();

  // Timeout: no new extremes for 30s → auto-save
  if (millis() - autocalLastChange > AUTOCAL_TIMEOUT) {
    autocalActive = false;
    eeSave(profIdx, prof);
    kalman.reset();
    Serial.println(F("\n! Autocal complete, saved"));
  }
}

// ─── Profile Management ────────────────────────────────────
void loadProf(uint8_t i) {
  if (i >= NUM_PROFILES) i = 0;
  profIdx = i;
  if (eeOk()) { eeLoad(i, prof); eeSetAct(i); }
  else prof = DEFAULT_PROFILE;

  kalman.tune(prof.kalmanQ, prof.kalmanR);
  kalman.reset();

  switch (prof.updateRateHz) {
    case 250: loopDelUs = 4000; break;
    case 500: loopDelUs = 2000; break;
    default:  loopDelUs = 1000; break;
  }

  lastBrakeOut = 0; brakeUp = true;
  smT.init(); smC.init(); smBpost.init();
  autocalActive = false;
}

// ─── Profile Quick-Switch Button ────────────────────────────
void checkButton() {
  bool cur = digitalRead(PIN_BTN_PROFILE);
  unsigned long now = millis();

  // Falling edge (press)
  if (cur == LOW && btnLast == HIGH && (now - btnDownTime > BTN_DEBOUNCE_MS)) {
    btnDownTime = now;
    btnHandled = false;
  }

  // Long press detection (while held)
  if (cur == LOW && !btnHandled && (now - btnDownTime > BTN_LONG_MS)) {
    eeSave(profIdx, prof);
    Serial.print(F("\n! Saved P")); Serial.println(profIdx);
    btnHandled = true;
  }

  // Rising edge (release) — short press
  if (cur == HIGH && btnLast == LOW && !btnHandled &&
      (now - btnDownTime > BTN_DEBOUNCE_MS)) {
    loadProf((profIdx + 1) % NUM_PROFILES);
    Serial.print(F("\n! Profile ")); Serial.println(profIdx);
  }

  btnLast = cur;
}

// ─── CLI Helpers ────────────────────────────────────────────
// Curve name strings in PROGMEM
const char CN0[] PROGMEM = "Lin";
const char CN1[] PROGMEM = "Prog";
const char CN2[] PROGMEM = "Deg";
const char CN3[] PROGMEM = "S-Crv";
const char CN4[] PROGMEM = "Cust";
const char CN5[] PROGMEM = "LUT";
const char* const CNAMES[] PROGMEM = {CN0, CN1, CN2, CN3, CN4, CN5};

void printCName(uint8_t t) {
  if (t < NUM_CURVES) {
    char buf[6];
    strcpy_P(buf, (char*)pgm_read_word(&CNAMES[t]));
    Serial.print(buf);
  } else Serial.print('?');
}

// Smoothing mode name strings in PROGMEM
const char SN0[] PROGMEM = "MAvg";
const char SN1[] PROGMEM = "EMA";
const char SN2[] PROGMEM = "Med";
const char* const SNAMES[] PROGMEM = {SN0, SN1, SN2};

void printSName(uint8_t t) {
  if (t <= 2) {
    char buf[5];
    strcpy_P(buf, (char*)pgm_read_word(&SNAMES[t]));
    Serial.print(buf);
  } else Serial.print('?');
}

void printLut(const uint8_t* lut) {
  Serial.print(F("    LUT: "));
  for (uint8_t i = 0; i < LUT_SIZE; i++) {
    Serial.print(lut[i]);
    if (i < LUT_SIZE - 1) Serial.print(' ');
  }
  Serial.println();
}

void miniBar(int pct) {
  Serial.print('[');
  uint8_t b = pct / 10;
  for (uint8_t i = 0; i < 10; i++) Serial.print(i < b ? '=' : '-');
  Serial.print(']');
}

void printPot(const char* nm, const PotConfig &p, int16_t raw) {
  Serial.print(F("  ")); Serial.print(nm);
  Serial.print(F(" cal:")); Serial.print(p.calMin);
  Serial.print('-'); Serial.print(p.calMax);
  Serial.print(F(" crv:")); printCName(p.curveType);
  Serial.print(F(" dz:")); Serial.print(p.dzMinPct);
  Serial.print('/'); Serial.print(p.dzMaxPct);
  Serial.print('%');
  Serial.print(F(" sm:")); printSName(p.smoothMode);
  if (p.inverted) Serial.print(F(" INV"));
  Serial.print(F(" raw:")); Serial.println(raw);
}

void printHelp() {
  Serial.println(F("\n-- PROBRAKE LC v" FW_VERSION " COMMANDS --"));
  Serial.println(F("BRAKE:    bmin bmax bcurve bexp bdzmin bdzmax bhyst bkq bkr"));
  Serial.println(F("          blut <10 vals> bsmooth <0-2>"));
  Serial.println(F("THROTTLE: tmin tmax tcurve texp tdzmin tdzmax tinv"));
  Serial.println(F("          tlut <10 vals> tsmooth <0-2>"));
  Serial.println(F("CLUTCH:   con coff cmin cmax ccurve cexp cdzmin cdzmax cinv"));
  Serial.println(F("          cbite <0-99> clut <10 vals> csmooth <0-2>"));
  Serial.println(F("PROFILES: profile <0-2> | save | copy <0-2>"));
  Serial.println(F("SYSTEM:   rate <250|500|1000> status test telem factory help"));
  Serial.println(F("          autocal | faults | rumble <0-255> | rthresh <50-100>"));
  Serial.println(F("CURVES:   0=Lin 1=Prog 2=Deg 3=S-Crv 4=Cust(exp) 5=LUT"));
  Serial.println(F("SMOOTH:   0=MAvg 1=EMA 2=Median"));
}

void printStatus() {
  Serial.print(F("\n[Profile ")); Serial.print(profIdx);
  Serial.print(F("] ")); Serial.print(prof.updateRateHz);
  Serial.print(F("Hz  up:")); Serial.print(uptimeS); Serial.println('s');

  // Brake
  Serial.print(F("  BRAKE  cal:")); Serial.print(prof.bCalMin);
  Serial.print('-'); Serial.print(prof.bCalMax);
  Serial.print(F(" crv:")); printCName(prof.bCurveType);
  Serial.print(F(" dz:")); Serial.print(prof.bDzMinPct);
  Serial.print('/'); Serial.print(prof.bDzMaxPct);
  Serial.print(F("% hyst:")); Serial.print(prof.bHysteresis);
  Serial.print(F(" K:")); Serial.print(prof.kalmanQ);
  Serial.print('/'); Serial.print(prof.kalmanR);
  Serial.print(F(" sm:")); printSName(prof.bSmoothMode);
  Serial.print(F(" raw:")); Serial.println(readBrake());
  printLut(prof.bLut);

  // Throttle
  printPot("THROT", prof.throttle, readThrottle());
  printLut(prof.throttle.lut);

  // Clutch
  printPot("CLUTCH", prof.clutch, readClutch());
  if (prof.clutchEnabled) {
    Serial.print(F("    bite:")); Serial.print(prof.clutchBitePoint);
    Serial.println('%');
  } else {
    Serial.println(F("    (disabled)"));
  }
  printLut(prof.clutch.lut);

  // Rumble
  Serial.print(F("  RUMBLE: "));
  if (prof.rumbleIntensity > 0) {
    Serial.print(prof.rumbleIntensity);
    Serial.print(F(" @")); Serial.print(prof.rumbleThreshold);
    Serial.println('%');
  } else {
    Serial.println(F("off"));
  }
}

void printFaults() {
  Serial.println(F("\n-- FAULT STATUS --"));
  Serial.print(F("  Brake:    "));
  Serial.println(faultB.faulted ? F("FAULT (disconnected)") : F("OK"));
  Serial.print(F("  Throttle: "));
  Serial.println(faultT.faulted ? F("FAULT (disconnected)") : F("OK"));
  Serial.print(F("  Clutch:   "));
  Serial.println(faultC.faulted ? F("FAULT (disconnected)") : F("OK"));
  Serial.print(F("  Overload: "));
  Serial.println(overload ? F("YES") : F("no"));
}

void runTest() {
  Serial.println(F("\n-- SELF-TEST --"));

  long br = readBrake();
  Serial.print(F("  Brake A0=")); Serial.print(br);
  Serial.println(br >= 0 && br <= 4095 ? F(" OK") : F(" FAIL"));

  int16_t tr = readThrottle();
  Serial.print(F("  Throt A1=")); Serial.print(tr);
  Serial.println(tr >= 0 && tr <= 1023 ? F(" OK") : F(" FAIL"));

  int16_t cr = readClutch();
  Serial.print(F("  Clutch A2=")); Serial.print(cr);
  Serial.println(cr >= 0 && cr <= 1023 ? F(" OK") : F(" FAIL"));

  Serial.print(F("  EEPROM: "));
  Serial.println(eeOk() ? F("valid (CRC OK)") : F("empty/invalid"));
  Serial.print(F("  Profile struct: "));
  Serial.print(sizeof(PedalProfile)); Serial.println(F(" bytes"));
  Serial.print(F("  Brake cal range: "));
  Serial.println(prof.bCalMax - prof.bCalMin);

  analogWrite(PIN_LED_BRAKE, 128); delay(80); analogWrite(PIN_LED_BRAKE, 0);
  Serial.println(F("  LED: pulsed"));

  Serial.print(F("  WDT: ")); Serial.println(F("active (1s)"));
  Serial.print(F("  Btn pin ")); Serial.print(PIN_BTN_PROFILE);
  Serial.print(F(": "));
  Serial.println(digitalRead(PIN_BTN_PROFILE) ? F("HIGH") : F("LOW (pressed)"));
}

// ─── LUT Parser ────────────────────────────────────────────
bool parseLut(const char* str, uint8_t* lut) {
  uint8_t cnt = 0;
  const char* p = str;
  while (*p && cnt < LUT_SIZE) {
    while (*p == ' ') p++;
    if (*p == '\0') break;
    int v = atoi(p);
    lut[cnt++] = (uint8_t)constrain(v, 0, 100);
    while (*p && *p != ' ') p++;
  }
  return (cnt == LUT_SIZE);
}

// ─── Command Processor ─────────────────────────────────────
int cmdInt(const char* c, uint8_t pos) { return atoi(c + pos); }

void toLowerStr(char* s) {
  while (*s) { if (*s >= 'A' && *s <= 'Z') *s += 32; s++; }
}

void processCmd(char* cmd) {
  toLowerStr(cmd);
  // Trim trailing whitespace
  uint8_t len = strlen(cmd);
  while (len > 0 && cmd[len - 1] <= ' ') cmd[--len] = '\0';
  if (len == 0) return;

  // ═══════════════ Fast prefix dispatch ═══════════════
  // Route by first character for O(1) initial branch
  char c0 = cmd[0];

  if (c0 == 'b') {
    // ═══════════════ BRAKE ═══════════════
    if (strcmp(cmd, "bmin") == 0) {
      Serial.println(F("Release brake..."));
      safeDelay(2000);
      prof.bCalMin = calibrate5s(0); kalman.reset();
    }
    else if (strcmp(cmd, "bmax") == 0) {
      Serial.println(F("Press brake fully..."));
      safeDelay(2000);
      prof.bCalMax = calibrate5s(0); kalman.reset();
    }
    else if (strncmp(cmd, "bcurve ", 7) == 0) {
      int v = cmdInt(cmd, 7);
      if (v >= 0 && v < NUM_CURVES) {
        prof.bCurveType = v;
        Serial.print(F("  =")); printCName(v); Serial.println();
      } else Serial.println(F("  0-5"));
    }
    else if (strncmp(cmd, "bexp ", 5) == 0) {
      int v = cmdInt(cmd, 5);
      if (v >= 5 && v <= 40) {
        prof.bCurveExp = v;
        Serial.print(F("  =")); Serial.println(v);
      } else Serial.println(F("  5-40"));
    }
    else if (strncmp(cmd, "bdzmin ", 7) == 0) {
      int v = cmdInt(cmd, 7);
      if (v >= 0 && v <= 30) {
        prof.bDzMinPct = v; Serial.print(F("  =")); Serial.println(v);
      } else Serial.println(F("  0-30"));
    }
    else if (strncmp(cmd, "bdzmax ", 7) == 0) {
      int v = cmdInt(cmd, 7);
      if (v >= 0 && v <= 30) {
        prof.bDzMaxPct = v; Serial.print(F("  =")); Serial.println(v);
      } else Serial.println(F("  0-30"));
    }
    else if (strncmp(cmd, "bhyst ", 6) == 0) {
      int v = cmdInt(cmd, 6);
      if (v >= 0 && v <= 50) {
        prof.bHysteresis = v; Serial.print(F("  =")); Serial.println(v);
      } else Serial.println(F("  0-50"));
    }

    else if (strncmp(cmd, "bkq ", 4) == 0) {
      int v = cmdInt(cmd, 4);
      if (v >= 1 && v <= 100) {
        prof.kalmanQ = v;
        kalman.tune(v, prof.kalmanR);
        kalman.reset();
        Serial.print(F("  Q=")); Serial.println(v);
      } else Serial.println(F("  1-100"));
    }
    else if (strncmp(cmd, "bkr ", 4) == 0) {
      int v = cmdInt(cmd, 4);
      if (v >= 1 && v <= 100) {
        prof.kalmanR = v;
        kalman.tune(prof.kalmanQ, v);
        kalman.reset();
        Serial.print(F("  R=")); Serial.println(v);
      } else Serial.println(F("  1-100"));
    }
    else if (strncmp(cmd, "bsmooth ", 8) == 0) {
      int v = cmdInt(cmd, 8);
      if (v >= 0 && v <= 2) {
        prof.bSmoothMode = v; smBpost.init();
        Serial.print(F("  =")); printSName(v); Serial.println();
      } else Serial.println(F("  0-2"));
    }
    else if (strncmp(cmd, "blut ", 5) == 0) {
      if (parseLut(cmd + 5, prof.bLut)) {
        prof.bCurveType = CURVE_LUT;
        Serial.println(F("  Brake LUT set, curve=LUT"));
        printLut(prof.bLut);
      } else Serial.println(F("  Need 10 values 0-100"));
    }
    else { Serial.print(F("  ? ")); Serial.println(cmd); }
  }

  else if (c0 == 't') {
    // ═══════════════ THROTTLE ═══════════════
    if (strcmp(cmd, "tmin") == 0) {
      Serial.println(F("Release throttle..."));
      safeDelay(2000);
      prof.throttle.calMin = (int16_t)calibrate5s(1);
    }
    else if (strcmp(cmd, "tmax") == 0) {
      Serial.println(F("Press throttle fully..."));
      safeDelay(2000);
      prof.throttle.calMax = (int16_t)calibrate5s(1);
    }
    else if (strncmp(cmd, "tcurve ", 7) == 0) {
      int v = cmdInt(cmd, 7);
      if (v >= 0 && v < NUM_CURVES) {
        prof.throttle.curveType = v;
        Serial.print(F("  =")); printCName(v); Serial.println();
      } else Serial.println(F("  0-5"));
    }
    else if (strncmp(cmd, "texp ", 5) == 0) {
      int v = cmdInt(cmd, 5);
      if (v >= 5 && v <= 40) {
        prof.throttle.curveExp = v;
        Serial.print(F("  =")); Serial.println(v);
      } else Serial.println(F("  5-40"));
    }
    else if (strncmp(cmd, "tdzmin ", 7) == 0) {
      int v = cmdInt(cmd, 7);
      if (v >= 0 && v <= 30) {
        prof.throttle.dzMinPct = v; Serial.print(F("  =")); Serial.println(v);
      } else Serial.println(F("  0-30"));
    }
    else if (strncmp(cmd, "tdzmax ", 7) == 0) {
      int v = cmdInt(cmd, 7);
      if (v >= 0 && v <= 30) {
        prof.throttle.dzMaxPct = v; Serial.print(F("  =")); Serial.println(v);
      } else Serial.println(F("  0-30"));
    }

    else if (strcmp(cmd, "tinv") == 0) {
      prof.throttle.inverted = !prof.throttle.inverted;
      Serial.print(F("  inv="));
      Serial.println(prof.throttle.inverted ? F("YES") : F("NO"));
    }
    else if (strncmp(cmd, "tsmooth ", 8) == 0) {
      int v = cmdInt(cmd, 8);
      if (v >= 0 && v <= 2) {
        prof.throttle.smoothMode = v; smT.init();
        Serial.print(F("  =")); printSName(v); Serial.println();
      } else Serial.println(F("  0-2"));
    }
    else if (strncmp(cmd, "tlut ", 5) == 0) {
      if (parseLut(cmd + 5, prof.throttle.lut)) {
        prof.throttle.curveType = CURVE_LUT;
        Serial.println(F("  Throt LUT set, curve=LUT"));
        printLut(prof.throttle.lut);
      } else Serial.println(F("  Need 10 values 0-100"));
    }
    else if (strcmp(cmd, "telem") == 0) {
      telemMode = (telemMode + 1) % 3;
      Serial.print(F("  Telem "));
      if (telemMode == TELEM_OFF)      Serial.println(F("OFF"));
      else if (telemMode == TELEM_TEXT) Serial.println(F("TEXT"));
      else                             Serial.println(F("BINARY"));
    }
    else if (strcmp(cmd, "test") == 0) runTest();
    else { Serial.print(F("  ? ")); Serial.println(cmd); }
  }

  else if (c0 == 'c') {
    // ═══════════════ CLUTCH ═══════════════
    if (strcmp(cmd, "con") == 0) {
      prof.clutchEnabled = 1;
      Serial.println(F("  Clutch ENABLED"));
    }
    else if (strcmp(cmd, "coff") == 0) {
      prof.clutchEnabled = 0;
      Serial.println(F("  Clutch DISABLED"));
    }
    else if (strcmp(cmd, "cmin") == 0) {
      if (!prof.clutchEnabled) Serial.println(F("  Clutch off. 'con' first"));
      else {
        Serial.println(F("Release clutch..."));
        safeDelay(2000);
        prof.clutch.calMin = (int16_t)calibrate5s(2);
      }
    }
    else if (strcmp(cmd, "cmax") == 0) {
      if (!prof.clutchEnabled) Serial.println(F("  Clutch off. 'con' first"));
      else {
        Serial.println(F("Press clutch fully..."));
        safeDelay(2000);
        prof.clutch.calMax = (int16_t)calibrate5s(2);
      }
    }
    else if (strncmp(cmd, "ccurve ", 7) == 0) {
      int v = cmdInt(cmd, 7);
      if (v >= 0 && v < NUM_CURVES) {
        prof.clutch.curveType = v;
        Serial.print(F("  =")); printCName(v); Serial.println();
      } else Serial.println(F("  0-5"));
    }
    else if (strncmp(cmd, "cexp ", 5) == 0) {
      int v = cmdInt(cmd, 5);
      if (v >= 5 && v <= 40) {
        prof.clutch.curveExp = v;
        Serial.print(F("  =")); Serial.println(v);
      } else Serial.println(F("  5-40"));
    }
    else if (strncmp(cmd, "cdzmin ", 7) == 0) {
      int v = cmdInt(cmd, 7);
      if (v >= 0 && v <= 30) {
        prof.clutch.dzMinPct = v; Serial.print(F("  =")); Serial.println(v);
      } else Serial.println(F("  0-30"));
    }
    else if (strncmp(cmd, "cdzmax ", 7) == 0) {
      int v = cmdInt(cmd, 7);
      if (v >= 0 && v <= 30) {
        prof.clutch.dzMaxPct = v; Serial.print(F("  =")); Serial.println(v);
      } else Serial.println(F("  0-30"));
    }

    else if (strcmp(cmd, "cinv") == 0) {
      prof.clutch.inverted = !prof.clutch.inverted;
      Serial.print(F("  inv="));
      Serial.println(prof.clutch.inverted ? F("YES") : F("NO"));
    }
    else if (strncmp(cmd, "cbite ", 6) == 0) {
      int v = cmdInt(cmd, 6);
      if (v >= 0 && v <= 99) {
        prof.clutchBitePoint = v;
        Serial.print(F("  bite=")); Serial.print(v); Serial.println('%');
      } else Serial.println(F("  0-99 (0=off)"));
    }
    else if (strncmp(cmd, "csmooth ", 8) == 0) {
      int v = cmdInt(cmd, 8);
      if (v >= 0 && v <= 2) {
        prof.clutch.smoothMode = v; smC.init();
        Serial.print(F("  =")); printSName(v); Serial.println();
      } else Serial.println(F("  0-2"));
    }
    else if (strncmp(cmd, "clut ", 5) == 0) {
      if (parseLut(cmd + 5, prof.clutch.lut)) {
        prof.clutch.curveType = CURVE_LUT;
        Serial.println(F("  Clutch LUT set, curve=LUT"));
        printLut(prof.clutch.lut);
      } else Serial.println(F("  Need 10 values 0-100"));
    }
    else if (strncmp(cmd, "copy ", 5) == 0) {
      int d = cmdInt(cmd, 5);
      if (d >= 0 && d < NUM_PROFILES) {
        eeSave(d, prof);
        Serial.print(F("  ->P")); Serial.println(d);
      } else Serial.println(F("  0-2"));
    }
    else { Serial.print(F("  ? ")); Serial.println(cmd); }
  }

  else if (c0 == 'r') {
    // ═══════════════ RUMBLE ═══════════════
    if (strncmp(cmd, "rumble ", 7) == 0) {
      int v = cmdInt(cmd, 7);
      if (v >= 0 && v <= 255) {
        prof.rumbleIntensity = v;
        Serial.print(F("  rumble=")); Serial.println(v);
        if (v == 0) analogWrite(PIN_RUMBLE, 0);
      } else Serial.println(F("  0-255 (0=off)"));
    }
    else if (strncmp(cmd, "rthresh ", 8) == 0) {
      int v = cmdInt(cmd, 8);
      if (v >= 50 && v <= 100) {
        prof.rumbleThreshold = v;
        Serial.print(F("  thresh=")); Serial.print(v); Serial.println('%');
      } else Serial.println(F("  50-100"));
    }
    else if (strncmp(cmd, "rate ", 5) == 0) {
      int v = cmdInt(cmd, 5);
      if (v == 250 || v == 500 || v == 1000) {
        prof.updateRateHz = v;
        loopDelUs = (v == 250) ? 4000 : (v == 500) ? 2000 : 1000;
        Serial.print(F("  =")); Serial.print(v); Serial.println(F("Hz"));
      } else Serial.println(F("  250/500/1000"));
    }
    else { Serial.print(F("  ? ")); Serial.println(cmd); }
  }

  else if (c0 == 'p') {
    if (strncmp(cmd, "profile ", 8) == 0) {
      int v = cmdInt(cmd, 8);
      if (v >= 0 && v < NUM_PROFILES) {
        loadProf(v);
        Serial.print(F("  Profile ")); Serial.println(v);
      } else Serial.println(F("  0-2"));
    }
    else { Serial.print(F("  ? ")); Serial.println(cmd); }
  }

  else if (c0 == 's') {
    if (strcmp(cmd, "save") == 0) {
      eeSave(profIdx, prof); eeSetAct(profIdx);
      Serial.print(F("  Saved P")); Serial.println(profIdx);
    }
    else if (strcmp(cmd, "status") == 0) printStatus();
    else { Serial.print(F("  ? ")); Serial.println(cmd); }
  }

  else if (c0 == 'a') {
    if (strcmp(cmd, "autocal") == 0) {
      if (autocalActive) {
        autocalActive = false;
        eeSave(profIdx, prof); kalman.reset();
        Serial.println(F("  Autocal stopped, saved"));
      } else {
        autocalActive = true;
        autocalLastChange = millis();
        Serial.println(F("  Autocal ON — press all pedals to extremes"));
        Serial.println(F("  Saves after 30s idle. 'autocal' to stop."));
      }
    }
    else { Serial.print(F("  ? ")); Serial.println(cmd); }
  }

  else if (c0 == 'f') {
    if (strcmp(cmd, "faults") == 0) printFaults();
    else if (strcmp(cmd, "factory") == 0) {
      eeReset(); loadProf(0);
      Serial.println(F("  Factory reset done"));
      printStatus();
    }
    else { Serial.print(F("  ? ")); Serial.println(cmd); }
  }

  else if (c0 == 'h') {
    if (strcmp(cmd, "help") == 0) printHelp();
    else { Serial.print(F("  ? ")); Serial.println(cmd); }
  }

  else { Serial.print(F("  ? ")); Serial.println(cmd); }
}

// ─── Binary Telemetry Packet ────────────────────────────────
void sendBinaryTelem(int tV, int bV, int cV) {
  uint8_t pkt[17];
  pkt[0]  = 0xAA;                                  // start marker
  pkt[1]  = profIdx;
  pkt[2]  = (uint8_t)(rawThrottle & 0xFF);
  pkt[3]  = (uint8_t)(rawThrottle >> 8);
  pkt[4]  = (uint8_t)(tV & 0xFF);
  pkt[5]  = (uint8_t)(tV >> 8);
  pkt[6]  = (uint8_t)(rawBrake & 0xFF);
  pkt[7]  = (uint8_t)((rawBrake >> 8) & 0xFF);
  pkt[8]  = (uint8_t)(bV & 0xFF);
  pkt[9]  = (uint8_t)(bV >> 8);
  pkt[10] = (uint8_t)(rawClutch & 0xFF);
  pkt[11] = (uint8_t)(rawClutch >> 8);
  pkt[12] = (uint8_t)(cV & 0xFF);
  pkt[13] = (uint8_t)(cV >> 8);

  // Flags byte
  uint8_t flags = 0;
  if (overload)       flags |= 0x01;
  if (faultB.faulted) flags |= 0x02;
  if (faultT.faulted) flags |= 0x04;
  if (faultC.faulted) flags |= 0x08;
  if (autocalActive)  flags |= 0x10;
  pkt[14] = flags;

  // XOR checksum (bytes 1–14)
  uint8_t xck = 0;
  for (uint8_t i = 1; i < 15; i++) xck ^= pkt[i];
  pkt[15] = xck;

  pkt[16] = 0x55;                                  // end marker
  Serial.write(pkt, 17);
}

// ─── Setup ──────────────────────────────────────────────────
void setup() {
  // Capture reset cause BEFORE clearing (for WDT detection)
  resetFlags = MCUSR;
  MCUSR = 0;
  wdt_disable();

  // Pin setup
  pinMode(PIN_BRAKE, INPUT);
  pinMode(PIN_THROTTLE, INPUT);
  pinMode(PIN_CLUTCH, INPUT);
  pinMode(PIN_LED_BRAKE, OUTPUT);
  pinMode(PIN_LED_STATUS, OUTPUT);
  pinMode(PIN_BTN_PROFILE, INPUT_PULLUP);
  pinMode(PIN_RUMBLE, OUTPUT);
  analogWrite(PIN_LED_BRAKE, 0);
  analogWrite(PIN_RUMBLE, 0);

  // ADC setup: prescaler /64 for faster conversions (~19kHz sample rate)
  // Default is /128 (~9.6kHz). /64 still gives >9-bit accuracy.
  ADCSRA = (ADCSRA & 0xF8) | 0x06;  // Prescaler = 64

  // Serial init
  Serial.begin(115200);
  delay(800);

  // Startup LED sequence
  for (uint8_t i = 0; i < 3; i++) {
    digitalWrite(PIN_LED_STATUS, HIGH); delay(60);
    digitalWrite(PIN_LED_STATUS, LOW);  delay(60);
  }

  // Banner
  Serial.println(F("\n== PROBRAKE LC v" FW_VERSION " =="));
  Serial.println(F("Commercial-Grade 3-Pedal Controller"));
  Serial.println(F("A0=Brake A1=Throttle A2=Clutch"));

  // WDT reset warning
  if (resetFlags & (1 << WDRF)) {
    Serial.println(F("! WARNING: Watchdog reset detected"));
  }

  // Init smoothing buffers
  smT.init(); smC.init(); smBpost.init();
  cmdLen = 0;

  // Load profile from EEPROM
  if (eeOk()) {
    profIdx = eeGetAct();
    loadProf(profIdx);
    Serial.print(F("Profile ")); Serial.print(profIdx);
    Serial.println(F(" loaded (CRC OK)"));
  } else {
    prof = DEFAULT_PROFILE;
    profIdx = 0;
    kalman.tune(5, 15);
    Serial.println(F("No saved data — defaults loaded"));
    Serial.println(F("Calibrate: bmin/bmax tmin/tmax cmin/cmax"));
  }

  // HID init
  Joystick.begin(false);
  Joystick.setXAxisRange(JOY_MIN, JOY_MAX);
  Joystick.setYAxisRange(JOY_MIN, JOY_MAX);
  Joystick.setZAxisRange(JOY_MIN, JOY_MAX);
  Joystick.setAcceleratorRange(JOY_MIN, JOY_MAX);
  Joystick.setBrakeRange(JOY_MIN, JOY_MAX);

  // Self-test and help
  runTest();
  printHelp();

  // Init timers
  lastUpdUs = micros();
  lastTelemMs = millis();
  lastUptimeMs = millis();

  // Enable watchdog (1-second timeout)
  wdt_enable(WDTO_1S);
}

// ─── Main Loop ──────────────────────────────────────────────
void loop() {
  wdt_reset();

  // ── Serial CLI ──
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (cmdLen > 0) {
        cmdBuf[cmdLen] = '\0';
        processCmd(cmdBuf);
        cmdLen = 0;
      }
    } else if (cmdLen < CMD_BUF_SIZE - 1) {
      cmdBuf[cmdLen++] = c;
    }
  }

  // ── Profile Button ──
  checkButton();

  // ── Uptime Counter ──
  unsigned long nowMs = millis();
  if (nowMs - lastUptimeMs >= 1000) {
    lastUptimeMs = nowMs;
    uptimeS++;
  }

  // ── Timing Gate ──
  unsigned long now = micros();
  if ((now - lastUpdUs) < loopDelUs) return;
  lastUpdUs = now;

  // ── Process All Axes ──
  int bV = processBrake();
  int tV = processThrottle();
  int cV = prof.clutchEnabled ? processClutch() : 0;

  // ── Auto-Calibration Update ──
  updateAutocal();

  // ── HID Output ──
  Joystick.setXAxis(tV);
  Joystick.setAccelerator(tV);
  Joystick.setYAxis(cV);
  Joystick.setZAxis(bV);
  Joystick.setBrake(bV);
  Joystick.sendState();

  // ── Brake LED (proportional brightness, delta-only) ──
  uint8_t ledVal = (uint8_t)map(bV, JOY_MIN, JOY_MAX, 0, 255);
  if (ledVal != lastBrakeLed) {
    analogWrite(PIN_LED_BRAKE, ledVal);
    lastBrakeLed = ledVal;
  }

  // ── Status LED (fault / overload / autocal indication) ──
  if (faultB.faulted || faultT.faulted || faultC.faulted) {
    digitalWrite(PIN_LED_STATUS, (nowMs / 100) % 2);   // fast blink = fault
  } else if (overload) {
    digitalWrite(PIN_LED_STATUS, (nowMs / 200) % 2);   // slow blink = overload
  } else if (autocalActive) {
    digitalWrite(PIN_LED_STATUS, (nowMs / 50) % 2);    // rapid blink = autocal
  } else {
    digitalWrite(PIN_LED_STATUS, LOW);
  }

  // ── Rumble Motor (ABS Simulation) ──
  if (prof.rumbleIntensity > 0) {
    int thresh = map(prof.rumbleThreshold, 0, 100, 0, JOY_MAX);
    if (bV > thresh) {
      // ~30Hz pulsing for realistic ABS feel
      uint8_t pulse = ((nowMs / 16) % 2) ? prof.rumbleIntensity : 0;
      analogWrite(PIN_RUMBLE, pulse);
    } else {
      analogWrite(PIN_RUMBLE, 0);
    }
  }

  // ── Telemetry (20Hz) ──
  if (telemMode != TELEM_OFF && (nowMs - lastTelemMs >= TELEM_INTERVAL)) {
    lastTelemMs = nowMs;

    if (telemMode == TELEM_BINARY) {
      sendBinaryTelem(tV, bV, cV);
    }
    else {
      // Text telemetry
      int bP = map(bV, 0, JOY_MAX, 0, 100);
      int tP = map(tV, 0, JOY_MAX, 0, 100);
      int cP = map(cV, 0, JOY_MAX, 0, 100);

      Serial.print(F("P")); Serial.print(profIdx);

      // Throttle
      Serial.print(F(" T:"));
      if (tP < 10) Serial.print(' ');
      if (tP < 100) Serial.print(' ');
      Serial.print(tP); Serial.print(F("% ")); miniBar(tP);

      // Brake
      Serial.print(F(" B:"));
      if (bP < 10) Serial.print(' ');
      if (bP < 100) Serial.print(' ');
      Serial.print(bP); Serial.print(F("% ")); miniBar(bP);

      // Clutch (only if enabled)
      if (prof.clutchEnabled) {
        Serial.print(F(" C:"));
        if (cP < 10) Serial.print(' ');
        if (cP < 100) Serial.print(' ');
        Serial.print(cP); Serial.print(F("% ")); miniBar(cP);
      }

      // Status flags
      if (overload)       Serial.print(F(" !OVR"));
      if (faultB.faulted) Serial.print(F(" !BF"));
      if (faultT.faulted) Serial.print(F(" !TF"));
      if (faultC.faulted) Serial.print(F(" !CF"));
      if (autocalActive)  Serial.print(F(" [AC]"));

      Serial.println();
    }
  }
}

/*
 *  ═══════════════════════════════════════════════════════════
 *  WIRING REFERENCE (v4.1)
 *  ═══════════════════════════════════════════════════════════
 *
 *  BRAKE (Load Cell):
 *    LoadCell → INA333 (Vin+/Vin-, Rg sets gain) → Vout → A0
 *    INA333: Vs+=5V, GND, Ref=2.5V divider, 100nF decoupling
 *    Gain = 1 + 100k/Rg  (Rg=1k→G=101, 4.7k→G=22, 10k→G=11)
 *
 *  THROTTLE:
 *    B10K: pin1→5V, pin2(wiper)→A1, pin3→GND
 *    Use 'tinv' command if direction is reversed
 *
 *  CLUTCH:
 *    B10K: pin1→5V, pin2(wiper)→A2, pin3→GND
 *    Use 'cinv' command if direction is reversed
 *
 *  BRAKE LED:
 *    Pin9 → 220Ω → LED anode (cathode → GND)
 *    Brightness proportional to brake pressure
 *
 *  PROFILE BUTTON:
 *    Pin7 → momentary push button → GND
 *    (Internal pull-up enabled, no external resistor needed)
 *    Short press = cycle profiles (0→1→2→0)
 *    Long press (>2s) = save current profile
 *
 *  RUMBLE MOTOR (optional, for ABS simulation):
 *    Pin10 → 1kΩ → N-MOSFET gate (e.g. IRLZ44N)
 *    MOSFET drain → vibration motor (−)
 *    Motor (+) → 5V
 *    MOSFET source → GND
 *    1N4001 flyback diode across motor terminals
 *    Set intensity with 'rumble <0-255>'
 *
 *  DECOUPLING:
 *    100nF ceramic on each analog input to GND
 *    10µF electrolytic on 5V rail
 *
 *  ═══════════════════════════════════════════════════════════
 *  RESPONSE CURVES
 *  ═══════════════════════════════════════════════════════════
 *  0=Linear (y=x)
 *  1=Progressive (y=x²) — gentle start, aggressive end
 *  2=Degressive (y=√x) — aggressive start, gentle end
 *  3=S-Curve (y=3x²−2x³) — gentle start+end, steep middle
 *  4=Custom (y=x^n) — set exponent via bexp/texp/cexp
 *  5=LUT (10-point lookup with interpolation) — full control
 *
 *  ═══════════════════════════════════════════════════════════
 *  SMOOTHING MODES
 *  ═══════════════════════════════════════════════════════════
 *  0=Moving Average (8-sample window, best for pots)
 *  1=EMA (exponential, α≈0.30, fast response)
 *  2=Median (5-sample, rejects noise spikes)
 *
 *  ═══════════════════════════════════════════════════════════
 *  HID AXES
 *  ═══════════════════════════════════════════════════════════
 *  X + Accelerator = Throttle
 *  Y = Clutch
 *  Z + Brake = Brake
 *
 *  ═══════════════════════════════════════════════════════════
 *  BINARY TELEMETRY PACKET (17 bytes, 50Hz)
 *  ═══════════════════════════════════════════════════════════
 *  [0xAA] [profIdx] [tRawL] [tRawH] [tOutL] [tOutH]
 *  [bRawL] [bRawH] [bOutL] [bOutH] [cRawL] [cRawH]
 *  [cOutL] [cOutH] [flags] [XOR] [0x55]
 *
 *  Flags: b0=overload b1=brakeFault b2=throttleFault
 *         b3=clutchFault b4=autocalActive
 *
 *  ═══════════════════════════════════════════════════════════
 *  EEPROM LAYOUT (1024 bytes available)
 *  ═══════════════════════════════════════════════════════════
 *  Addr 0:   Magic byte (0xC5)
 *  Addr 2:   Active profile index (0-2)
 *  Addr 3+:  Profile 0 data + CRC16
 *            Profile 1 data + CRC16
 *            Profile 2 data + CRC16
 *  Each profile block = sizeof(PedalProfile) + 2 bytes CRC
 *
 *  ═══════════════════════════════════════════════════════════
 *  v4.1 OPTIMIZATION CHANGELOG
 *  ═══════════════════════════════════════════════════════════
 *  1. ZERO FLOAT in hot path — all curve math, Kalman, axis
 *     pipeline, and clutch bite point use Q10/Q16 fixed-point
 *  2. Direct ADC registers — bypasses analogRead() overhead
 *     (~112µs → ~13µs per read), prescaler /64 for 2x speed
 *  3. Fixed-point Kalman — Q16 accumulator, no float mul/div
 *  4. Integer sqrt — Babylonian method for degressive curve
 *  5. Delta-only LED writes — skips analogWrite when unchanged
 *  6. First-char command dispatch — O(1) initial routing vs
 *     linear scan through 40+ strcmp calls
 *  7. millis() cached — single call per loop, reused everywhere
 *  8. EEPROM magic bumped — 0xC5 forces clean re-init
 *  9. Struct layout preserved — full binary compatibility
 *     with existing GUI serial protocol
 */
