// DahlStar Serial Harness — Phase 2 macOS command-line test tool
//
// Usage:
//   DahlStarHarness [--port /dev/cu.usbmodemXXXX] [--baud 115200] [--test]
//
// Interactive mode (default): type commands, see responses in real time.
// Test mode (--test):         runs a scripted sequence exercising every command.
//
// Command format matches firmware CommManager exactly:
//   CMD:EXTEND, CMD:RETRACT, CMD:CALIBRATE, CMD:STOP, CMD:STATUS,
//   CMD:MOTOR:ON, CMD:MOTOR:OFF, CMD:TAP:<9T|10T|11T|12T|13T>, CMD:MOVE:<steps>

import Foundation

// ── ANSI helpers ─────────────────────────────────────────────────────────────

enum ANSI {
    static let reset  = "\u{1B}[0m"
    static let bold   = "\u{1B}[1m"
    static let cyan   = "\u{1B}[36m"
    static let green  = "\u{1B}[32m"
    static let yellow = "\u{1B}[33m"
    static let red    = "\u{1B}[31m"
    static let gray   = "\u{1B}[90m"
}

func colorize(_ s: String) -> String {
    if s.hasPrefix("ACK:")    { return ANSI.green  + s + ANSI.reset }
    if s.hasPrefix("NAK:")    { return ANSI.red     + s + ANSI.reset }
    if s.hasPrefix("STATUS:") { return ANSI.cyan    + s + ANSI.reset }
    return s
}

func printHeader(_ msg: String) {
    print("\n\(ANSI.bold)\(ANSI.yellow)═══ \(msg) ═══\(ANSI.reset)")
}

func printSent(_ cmd: String) {
    print("\(ANSI.gray)→ \(cmd)\(ANSI.reset)")
}

func printReceived(_ line: String) {
    print(colorize(line))
}

// ── Argument parsing ──────────────────────────────────────────────────────────

var portPath: String? = nil
var baud      = 115200
var testMode  = false

var args = CommandLine.arguments.dropFirst()
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--port":
        portPath = args.isEmpty ? nil : args.removeFirst()
    case "--baud":
        if let v = args.first.flatMap(Int.init) { baud = v; args.removeFirst() }
    case "--test":
        testMode = true
    case "--help", "-h":
        print("""
        DahlStar Serial Harness — Phase 2 USB test tool

        Usage: DahlStarHarness [--port PATH] [--baud 115200] [--test]

          --port PATH   Serial device (default: auto-detect /dev/cu.usbmodem*)
          --baud RATE   Baud rate (default: 115200)
          --test        Run automated test sequence instead of interactive REPL

        Interactive commands (no CMD: prefix needed):
          EXTEND, RETRACT, CALIBRATE, STOP, STATUS
          MOTOR:ON, MOTOR:OFF
          TAP:9T  TAP:10T  TAP:11T  TAP:12T  TAP:13T
          MOVE:<steps>
          quit / exit
        """)
        exit(0)
    default:
        break
    }
}

// ── Resolve port ──────────────────────────────────────────────────────────────

let resolvedPort: String
if let p = portPath {
    resolvedPort = p
} else if let p = SerialPort.findArduinoPort() {
    resolvedPort = p
    print("Auto-detected Arduino port: \(ANSI.bold)\(p)\(ANSI.reset)")
} else {
    fputs("Error: no /dev/cu.usbmodem* port found. Connect Arduino and retry, or specify --port.\n", stderr)
    exit(1)
}

// ── Open port ─────────────────────────────────────────────────────────────────

let port: SerialPort
do {
    port = try SerialPort(path: resolvedPort, baud: baud)
    print("Opened \(resolvedPort) at \(baud) baud\n")
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}

// ── Drain startup messages ────────────────────────────────────────────────────

print("\(ANSI.gray)Waiting for firmware boot messages...\(ANSI.reset)")
Thread.sleep(forTimeInterval: 2.5)  // Arduino resets on USB open; give it time
for line in port.readLines() { printReceived(line) }
print()

// ── Shared send+wait helper ───────────────────────────────────────────────────

/// Send a command and collect responses for up to `timeout` seconds.
/// Returns when an ACK, NAK, or STATUS:CAL:DONE line is received, or timeout expires.
@discardableResult
func send(_ verb: String, timeout: Double = 3.0) -> [String] {
    let cmd = verb.hasPrefix("CMD:") ? verb : "CMD:\(verb)"
    printSent(cmd)
    do { try port.send(cmd) } catch { fputs("Send error: \(error)\n", stderr); return [] }

    var responses: [String] = []
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        for line in port.readLines() {
            printReceived(line)
            responses.append(line)
            // A terminal response ends the wait early
            if line.hasPrefix("ACK:") || line.hasPrefix("NAK:") ||
               line == "STATUS:CAL:DONE" { return responses }
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return responses
}

/// Wait for incoming lines for `duration` seconds (used during motion).
func drain(for duration: Double) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
        for line in port.readLines() { printReceived(line) }
        Thread.sleep(forTimeInterval: 0.05)
    }
}

// ── Test mode ─────────────────────────────────────────────────────────────────

func runTestSequence() {
    printHeader("DahlStar Serial Harness — Automated Test Sequence")
    print("Tests every firmware command. Motor will move — ensure antenna is clear.\n")

    // 1. Status query
    printHeader("1 · Query initial status")
    send("STATUS")

    // 2. Motor power on
    printHeader("2 · Motor power ON")
    send("MOTOR:ON")
    Thread.sleep(forTimeInterval: 0.5)
    send("STATUS")

    // 3. Motor power off
    printHeader("3 · Motor power OFF")
    send("MOTOR:OFF")

    // 4. Tap selection — cycle through all taps
    printHeader("4 · UNUN tap selection")
    for tap in ["9T","10T","12T","13T","11T"] {
        send("TAP:\(tap)")
        Thread.sleep(forTimeInterval: 0.3)
    }
    send("STATUS")  // should report TAP:11T

    // 5. Calibrate (home)
    printHeader("5 · CALIBRATE (homing to limit switch)")
    print("This may take up to 60 seconds depending on coil position...")
    send("CALIBRATE", timeout: 0.5)   // just capture ACK; actual motion is polled below
    drain(for: 60.0)                  // collect STATUS:POS updates and STATUS:CAL:DONE

    // 6. Extend a small amount
    printHeader("6 · EXTEND (1000 steps)")
    send("EXTEND")
    drain(for: 3.0)

    // 7. Retract back
    printHeader("7 · RETRACT (1000 steps)")
    send("RETRACT")
    drain(for: 3.0)

    // 8. MOVE absolute (move 5000 steps out)
    printHeader("8 · MOVE +5000 steps")
    send("MOVE:5000")
    drain(for: 5.0)

    // 9. STOP (during motion — issue move then immediately stop)
    printHeader("9 · STOP mid-motion")
    send("MOVE:20000", timeout: 0.3)
    Thread.sleep(forTimeInterval: 0.5)
    send("STOP")
    drain(for: 1.0)

    // 10. Final status
    printHeader("10 · Final status")
    send("STATUS")

    // 11. Unknown command (should get NAK)
    printHeader("11 · Unknown command (expect NAK)")
    send("BOGUS:CMD")

    printHeader("Test sequence complete")
    print()
}

// ── Interactive REPL ──────────────────────────────────────────────────────────

func runREPL() {
    print("""
    \(ANSI.bold)DahlStar Serial Harness — Interactive Mode\(ANSI.reset)
    Type commands without the CMD: prefix. Press Enter to send.
    Commands: EXTEND  RETRACT  CALIBRATE  STOP  STATUS
              MOTOR:ON  MOTOR:OFF  TAP:9T … TAP:13T  MOVE:<steps>
    Type \(ANSI.bold)quit\(ANSI.reset) or \(ANSI.bold)exit\(ANSI.reset) to close.
    Received lines are printed as they arrive (green=ACK, red=NAK, cyan=STATUS).
    """)

    // Background reader thread: prints any unsolicited lines while user is typing
    let readThread = Thread {
        while true {
            for line in port.readLines() { printReceived(line) }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
    readThread.start()

    while true {
        print("\(ANSI.bold)> \(ANSI.reset)", terminator: "")
        fflush(stdout)
        guard let input = readLine(strippingNewline: true)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty else { continue }

        let lower = input.lowercased()
        if lower == "quit" || lower == "exit" { break }

        let cmd = input.uppercased().hasPrefix("CMD:") ? input.uppercased()
                : "CMD:" + input.uppercased()
        printSent(cmd)
        do { try port.send(cmd) } catch { print("Send error: \(error)") }
    }

    readThread.cancel()
    print("Bye.")
}

// ── Entry point ───────────────────────────────────────────────────────────────

if testMode {
    runTestSequence()
} else {
    runREPL()
}
