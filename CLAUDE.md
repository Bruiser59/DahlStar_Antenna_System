# DahlStar Antenna System — Claude Context

This file gives Claude Code immediate context for working in this repository. Read it before writing any code or making any architectural decisions.

## What This Project Is

A personal amateur radio project: a single-element motor-driven coil-loaded HF vertical antenna covering 80–10 meters. A stepper motor extends and retracts a loading coil inside a 36-inch radiating tube, continuously varying the resonant frequency. An Arduino Uno R4 WiFi controls everything; a macOS Swift/SwiftUI application provides the user interface.

**Full system description:** `System_Engineering/DahlStar_System_Description.md`
**Software development proposal (current):** `Planning/Software/DahlStar_Software_Development_Proposal_v3.docx`

---

## Repository Structure

```
Code/
  DahlStar_Controller_App/       ← Arduino firmware (PlatformIO, VS Code)
  DahlStar_User_Interface_App/   ← macOS UI (Xcode, Swift/SwiftUI)
Planning/
  Software/                      ← All software documentation goes here
System_Engineering/
  DahlStar_System_Description.md ← Authoritative hardware reference
Datasheets/                      ← Component datasheets (PDFs)
Images/                          ← Assembly and component photos
```

---

## Code Project Status

**Phase 1 (Firmware Foundation):** ✅ Complete — `Code/DahlStar_Controller_App/src/main.cpp` implements full MotionController, RelayManager, DisplayManager, PersistenceManager, and CommManager (USB serial). Bench-validated on hardware.

**Phase 2 (USB Serial Communication):** ✅ Complete — `Code/DahlStar_Serial_Harness/` is a Swift CLI harness (POSIX termios, no dependencies) for exercising all firmware commands interactively or via `--test` auto-sequence.

**Phase 3 (macOS UI Application):** 🔲 Not started — `Code/DahlStar_User_Interface_App/` is still the default Xcode stub. Wi-Fi transport should be implemented first (simpler than BLE).

---

## Arduino Firmware Project

**Tool:** PlatformIO extension in VS Code
**Board:** `uno_r4_wifi` (Renesas RA4M1, `platformio.ini` already configured)
**Framework:** Arduino

### Pin Assignments

| Pin | Direction | Function | Notes |
|-----|-----------|----------|-------|
| D3 | Output | Motor Shield PWMA | Channel A PWM speed |
| D5 | Input | Limit switch sense | Via RC debounce (A6). HIGH = coil at home (switch actuated, NC opens, pin floats high); LOW = coil not at home (NC contact closed, pulls pin low). Confirmed by hardware test. |
| D6 | Output | 9T UNUN tap relay (K1) | Normally Open |
| D7 | Output | Motor power relay (K8) | Active LOW (Elegoo module); LOW = energized/NO, HIGH = de-energized/NC |
| D8 | Output | Motor Shield BRAKEB | Channel B brake |
| D9 | Output | Motor Shield BRAKEA | Channel A brake |
| D11 | Output | Motor Shield PWMB | Channel B PWM speed |
| D12 | Output | Motor Shield DIRA | Channel A direction |
| D13 | Output | Motor Shield DIRB | Channel B direction |
| A0 | Input | Motor Shield Ch A current sense | Read-only from shield; not a relay output |
| A1 | Input | Motor Shield Ch B current sense | Read-only from shield; not a relay output |
| A2 | Output | 10T UNUN tap relay (K2) | Normally Open |
| A3 | Output | 11T UNUN tap relay (K3) | Normally Closed — power-on default tap |
| A4 | Output | 12T UNUN tap relay (K4) | Normally Open |
| A5 | Output | 13T UNUN tap relay (K5) | Normally Open |
| SCL | I2C | OLED display clock | Hosyond GME12864-13, SSD1306-compatible, 3.3 V |
| SDA | I2C | OLED display data | Hosyond GME12864-13, SSD1306-compatible, 3.3 V |

**Critical:** A0 and A1 are inputs from the motor shield, not relay control outputs. Do not write to them.

### UNUN Relay Switching Logic

The 11T tap (K3, controlled by A3) is wired **Normally Closed** — it is active at power-on with no firmware action needed. All other taps are Normally Open.

- **Switching to a non-default tap:** Assert A3 HIGH (opens the 11T NC path) AND assert the target tap pin HIGH simultaneously.
- **Switching back to 11T:** De-assert A3 (K3 returns to NC, restoring 11T) AND de-assert any previously active tap pin.
- **Relay signal lines must be held** for any non-default tap to remain connected.

### Motor and Mechanical Specs

- **Motor:** Stepperonline NEMA 17, 26.85:1 planetary gear (17HS15-1684S-PG27)
- **Steps per output revolution:** 200 × 26.85 = 5,370 steps
- **Lead screw:** ReliaBot 550 mm T8 Tr8x8 — 2 mm pitch, 4 starts = **8 mm lead/rev**
- **Travel per step:** ~0.00149 mm/step
- **MAX_STEPS constant:** 289,799 — based on 17 in (431.8 mm) maximum coil travel. Formula: `MAX_STEPS = total_travel_mm / 0.00149`
- **Motor direction (confirmed):** CW rotation (viewed from gearbox output shaft) = extend; CCW = retract. In firmware: positive step count = extend, negative = retract.

### Recommended Libraries

| Library | Purpose |
|---------|---------|
| `WiFiS3` | Wi-Fi connectivity (first transport implemented) |
| `ArduinoBLE` | BLE peripheral (second transport implemented) |
| `AccelStepper` | Stepper control with acceleration profiles |
| `Adafruit_SSD1306` or `U8g2` | OLED display driver (I2C, SSD1306) |
| `EEPROM` | Non-volatile storage for step count and tap state |

### Recommended Firmware Architecture

Non-blocking event loop with these modules:
- **CommManager** — transport selection (Wi-Fi / BLE), packet framing, command parsing, status reporting
- **MotionController** — stepper drive, step counting, limit switch polling (D5), travel limit enforcement
- **RelayManager** — UNUN tap state machine (enforces NC/NO switching logic above), motor power relay
- **DisplayManager** — OLED status screens (position %, tap, motor power, calibration status, errors)
- **PersistenceManager** — EEPROM read/write for step count and active tap

---

## macOS UI Project

**Tool:** Xcode
**Language:** Swift / SwiftUI
**Target:** macOS, Apple Silicon (M-series MacBook Pro)
**Architecture:** MVVM

### Recommended Layer Structure

```
Model:     AntennaState, ConnectionState
ViewModel: AntennaViewModel  (@Published properties, command dispatch, response parsing)
Views:     MainView, ConnectionView, PositionControlView, TapSelectorView, MotorControlView
Transport: AntennaTransport (protocol)
           ├── WiFiTransport    (Network.framework — implement first)
           └── BLETransport     (CoreBluetooth — implement second)
```

### UI Requirements

- Must conform to Apple Human Interface Guidelines
- Support macOS light mode and dark mode
- All controls disabled when not connected
- Accessibility: VoiceOver labels and keyboard navigation on all interactive elements
- Calibrate action requires user confirmation before executing

---

## Communication Protocol

The same ASCII protocol is used over both transports.

| Direction | Format | Example |
|-----------|--------|---------|
| Command (macOS → Arduino) | `CMD:<VERB>[:<PARAM>]\n` | `CMD:EXTEND\n`, `CMD:TAP:12T\n`, `CMD:MOTOR:ON\n` |
| Acknowledgment | `ACK:<VERB>\n` | `ACK:EXTEND\n` |
| Error | `NAK:<VERB>:<REASON>\n` | `NAK:EXTEND:AT_LIMIT\n` |
| Status (unsolicited) | `STATUS:<KEY>:<VALUE>\n` | `STATUS:POS:1250\n` |

Status updates are sent at ~200 ms intervals during motion. Calibration completion is signalled by `STATUS:CAL:DONE\n`.

### Transports (implement in this order)

1. **Wi-Fi — implement first** (simpler): Arduino acts as TCP server; macOS connects as TCP client using `Network.framework`. Requires Wi-Fi credentials provisioned on the Arduino. IP address/hostname TBD.

2. **BLE — implement second** (more complex): Arduino acts as BLE peripheral using `ArduinoBLE`. macOS acts as BLE central using `CoreBluetooth`. Requires a custom GATT service with a write-without-response characteristic (commands) and a notify characteristic (status/ACK). UUIDs TBD — use arbitrary 128-bit UUIDs for this project.

---

## Development Phase Order

1. **Firmware Foundation** ✅ — motion control, relay logic, OLED display, EEPROM persistence, USB serial CommManager; bench-validated
2. **USB Serial Communication** ✅ — ASCII protocol already in firmware; macOS Swift CLI harness (`Code/DahlStar_Serial_Harness/`) for interactive testing and automated command exercise over USB
3. **macOS UI Application (Core)** — Xcode project; MVVM; AntennaViewModel + all model types; `WiFiTransport` (Wi-Fi first, simpler); all UI views; end-to-end test over Wi-Fi
4. **BLE Transport** — GATT service on firmware + `BLETransport` on macOS; add to existing UI transport selector
5. **Integration & Polish** — full system integration, dark mode, accessibility, HIG review, documentation

---

## Open Questions (decisions needed before certain work can proceed)

| Item | Needed For | Status |
|------|-----------|--------|
| Wi-Fi SSID / credential provisioning | Phase 3 start | Decide: hardcoded vs. USB provisioning |
| Arduino IP address or mDNS hostname | Phase 3 macOS client | Decide: fixed IP vs. mDNS |
| BLE GATT service + characteristic UUIDs | Phase 4 start | Choose 128-bit UUIDs |
| Minimum macOS version | Xcode deployment target | Recommend: macOS 13 (Ventura) |
| Position indicator UI design | Phase 3 macOS UI | Choose: progress bar / graphic / band indicator |
| Band-to-step-position mapping | Optional UI feature | Empirical — determine post-commissioning |

---

## Key Facts to Never Get Wrong

- **A0 and A1 are inputs** (motor shield current sense), not relay outputs
- **11T tap is Normally Closed** (default at power-on) — K3 / pin A3
- **9T tap is on D6** (not A1 as in earlier incorrect schematics)
- **Motor power relay is on D7** (not A0 as in earlier incorrect schematics)
- **Limit switch sense is D5 only** — D2 and D4 are unused; HIGH = at home (switch actuated, NC opens, pin floats high via pull-up); LOW = not at home. Confirmed by hardware test — the proposal appendix has this backwards.
- **OLED is 3.3 V** (not 5 V)
- **Transport order:** Wi-Fi first (simpler), BLE second (more complex)
