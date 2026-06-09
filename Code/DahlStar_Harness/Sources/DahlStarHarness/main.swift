// DahlStar Serial Harness — Phase 2 macOS command-line test tool
//
// Usage:
//   DahlStarHarness [--port /dev/cu.usbmodemXXXX] [--baud 115200] [--test]
//   DahlStarHarness --wifi [hostname]              [--port NNNN]   [--test]
//
// Transport selection:
//   (default)   USB serial — auto-detects /dev/cu.usbmodem*
//   --wifi      TCP over Wi-Fi — connects to dahlstar.local:4242 by default
//
// Interactive mode (default): type commands, see responses in real time.
// Test mode (--test):         runs a scripted sequence exercising every command.
//
// Command format matches firmware processCmd() exactly:
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

// ── Transport protocol ────────────────────────────────────────────────────────
// Both SerialPort and TCPPort conform to this so the REPL / test code is shared.

protocol DahlStarTransport {
    func send(_ line: String) throws
    func readLines() -> [String]
}

extension SerialPort: DahlStarTransport {}
extension TCPPort:    DahlStarTransport {}

// ── Argument parsing ──────────────────────────────────────────────────────────

var usbPortPath: String? = nil
var baud         = 115200
var testMode     = false
var useWifi      = false
var wifiHost     = "dahlstar.local"
var wifiPort     = 4242

var args = CommandLine.arguments.dropFirst()
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--port":
        // In USB mode: serial device path. In WiFi mode: TCP port number.
        if let next = args.first {
            if useWifi, let n = Int(next) { wifiPort = n; args.removeFirst() }
            else if !useWifi { usbPortPath = next; args.removeFirst() }
            else { args.removeFirst() }
        }
    case "--baud":
        if let v = args.first.flatMap(Int.init) { baud = v; args.removeFirst() }
    case "--wifi":
        useWifi = true
        // Optional positional hostname after --wifi
        if let next = args.first, !next.hasPrefix("--") {
            wifiHost = next
            args.removeFirst()
        }
    case "--test":
        testMode = true
    case "--help", "-h":
        print("""
        DahlStar Serial Harness — Phase 2 USB + Wi-Fi test tool

        Usage (USB serial):
          DahlStarHarness [--port /dev/cu.usbmodemXXXX] [--baud 115200] [--test]

        Usage (Wi-Fi TCP):
          DahlStarHarness --wifi [hostname] [--port 4242] [--test]
          Default hostname: dahlstar.local  (mDNS, resolves on local network)

          --port PATH   USB: serial device path (default: auto-detect)
          --baud RATE   USB: baud rate (default: 115200)
          --wifi HOST   Wi-Fi: connect to HOST (default: dahlstar.local)
          --port N      Wi-Fi: TCP port (default: 4242)
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

// ── Open transport ────────────────────────────────────────────────────────────

let transport: any DahlStarTransport

if useWifi {
    print("Connecting to \(ANSI.bold)\(wifiHost):\(wifiPort)\(ANSI.reset) over Wi-Fi...")
    do {
        transport = try TCPPort(hostname: wifiHost, port: UInt16(wifiPort))
        print("Connected.\n")
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }
} else {
    let resolvedPort: String
    if let p = usbPortPath {
        resolvedPort = p
    } else if let p = SerialPort.findArduinoPort() {
        resolvedPort = p
        print("Auto-detected Arduino port: \(ANSI.bold)\(p)\(ANSI.reset)")
    } else {
        fputs("Error: no /dev/cu.usbmodem* port found. Connect Arduino and retry, or use --wifi.\n", stderr)
        exit(1)
    }
    do {
        transport = try SerialPort(path: resolvedPort, baud: baud)
        print("Opened \(resolvedPort) at \(baud) baud\n")
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }
}

// ── Drain startup / connect messages ─────────────────────────────────────────

if useWifi {
    // WiFiServer::available() only wakes when the client sends data, so we
    // send CMD:STATUS immediately to give the firmware something to detect
    // the connection with. The response serves as our connect-time state dump.
    try? transport.send("CMD:STATUS")
    Thread.sleep(forTimeInterval: 0.5)
    for line in transport.readLines() { printReceived(line) }
} else {
    print("\(ANSI.gray)Waiting for firmware boot messages...\(ANSI.reset)")
    Thread.sleep(forTimeInterval: 2.5)  // Arduino resets on USB open
    for line in transport.readLines() { printReceived(line) }
}
print()

// ── Shared send+wait helper ───────────────────────────────────────────────────

@discardableResult
func send(_ verb: String, timeout: Double = 3.0) -> [String] {
    let cmd = verb.hasPrefix("CMD:") ? verb : "CMD:\(verb)"
    printSent(cmd)
    do { try transport.send(cmd) } catch { fputs("Send error: \(error)\n", stderr); return [] }

    var responses: [String] = []
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        for line in transport.readLines() {
            printReceived(line)
            responses.append(line)
            if line.hasPrefix("ACK:") || line.hasPrefix("NAK:") ||
               line == "STATUS:CAL:DONE" { return responses }
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return responses
}

func drain(for duration: Double) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
        for line in transport.readLines() { printReceived(line) }
        Thread.sleep(forTimeInterval: 0.05)
    }
}

// ── Test mode ─────────────────────────────────────────────────────────────────

func runTestSequence() {
    let transportName = useWifi ? "Wi-Fi (\(wifiHost):\(wifiPort))" : "USB Serial"
    printHeader("DahlStar Harness — Automated Test Sequence [\(transportName)]")
    print("Tests every firmware command. Motor will move — ensure antenna is clear.\n")

    printHeader("1 · Query initial status")
    send("STATUS")

    printHeader("2 · Motor power ON")
    send("MOTOR:ON")
    Thread.sleep(forTimeInterval: 0.5)
    send("STATUS")

    printHeader("3 · Motor power OFF")
    send("MOTOR:OFF")

    printHeader("4 · UNUN tap selection")
    for tap in ["9T","10T","12T","13T","11T"] {
        send("TAP:\(tap)")
        Thread.sleep(forTimeInterval: 0.3)
    }
    send("STATUS")

    printHeader("5 · CALIBRATE (homing to limit switch)")
    print("This may take up to 60 seconds depending on coil position...")
    send("CALIBRATE", timeout: 0.5)
    drain(for: 60.0)

    printHeader("6 · EXTEND (1000 steps)")
    send("EXTEND")
    drain(for: 3.0)

    printHeader("7 · RETRACT (1000 steps)")
    send("RETRACT")
    drain(for: 3.0)

    printHeader("8 · MOVE +5000 steps")
    send("MOVE:5000")
    drain(for: 5.0)

    printHeader("9 · STOP mid-motion")
    send("MOVE:20000", timeout: 0.3)
    Thread.sleep(forTimeInterval: 0.5)
    send("STOP")
    drain(for: 1.0)

    printHeader("10 · Final status")
    send("STATUS")

    printHeader("11 · Unknown command (expect NAK)")
    send("BOGUS:CMD")

    printHeader("Test sequence complete")
    print()
}

// ── Interactive REPL ──────────────────────────────────────────────────────────

func runREPL() {
    let transportName = useWifi ? "Wi-Fi (\(wifiHost):\(wifiPort))" : "USB Serial"
    print("""
    \(ANSI.bold)DahlStar Harness — Interactive Mode [\(transportName)]\(ANSI.reset)
    Type commands without the CMD: prefix. Press Enter to send.
    Commands: EXTEND  RETRACT  CALIBRATE  STOP  STATUS
              MOTOR:ON  MOTOR:OFF  TAP:9T … TAP:13T  MOVE:<steps>
    Type \(ANSI.bold)quit\(ANSI.reset) or \(ANSI.bold)exit\(ANSI.reset) to close.
    Received lines: \(ANSI.green)green\(ANSI.reset)=ACK  \(ANSI.red)red\(ANSI.reset)=NAK  \(ANSI.cyan)cyan\(ANSI.reset)=STATUS
    """)

    let readThread = Thread {
        while true {
            for line in transport.readLines() { printReceived(line) }
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
        do { try transport.send(cmd) } catch { print("Send error: \(error)") }
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
