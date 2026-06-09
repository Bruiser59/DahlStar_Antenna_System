# DahlStar Serial Harness

Phase 2 macOS command-line test tool for the DahlStar Antenna System.

Communicates with the Arduino firmware over USB serial using the shared ASCII protocol.

## Build

```bash
cd Code/DahlStar_Serial_Harness
swift build -c release
```

## Run — Interactive

```bash
.build/release/DahlStarHarness
```

Auto-detects the Arduino on `/dev/cu.usbmodem*`. Type commands without the `CMD:` prefix:

| Command | Effect |
|---------|--------|
| `STATUS` | Query all firmware state |
| `CALIBRATE` | Home the coil to the limit switch |
| `EXTEND` | Move coil out by 1000 steps |
| `RETRACT` | Move coil in by 1000 steps |
| `MOVE:<n>` | Move coil by n steps (±) |
| `STOP` | Halt motion immediately |
| `MOTOR:ON` / `MOTOR:OFF` | Toggle motor power relay |
| `TAP:9T` … `TAP:13T` | Select UNUN impedance tap |
| `quit` / `exit` | Close the tool |

Responses are color-coded: **green** = ACK, **red** = NAK, **cyan** = STATUS.

## Run — Automated Test

```bash
.build/release/DahlStarHarness --test
```

Runs a scripted sequence exercising every command. The motor will move — ensure the antenna is mechanically clear before running.

## Options

```
--port PATH    Specify serial device (default: auto-detect)
--baud RATE    Baud rate (default: 115200)
--test         Run automated test sequence
```
