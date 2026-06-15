// AntennaViewModel.swift — MVVM bridge between WiFiTransport and SwiftUI views.
// All properties are @MainActor (via SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor).
// Runs a dedicated receive Task that processes incoming firmware lines in real time.

import SwiftUI
import Observation

// ── Connection state ──────────────────────────────────────────────────────────

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var isConnected: Bool { self == .connected }

    var label: String {
        switch self {
        case .disconnected:    return "Disconnected"
        case .connecting:      return "Connecting…"
        case .connected:       return "Connected"
        case .failed(let msg): return "Error: \(msg)"
        }
    }

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected), (.connecting, .connecting), (.connected, .connected):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// ── ViewModel ─────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class AntennaViewModel {

    // Published state
    var connectionState: ConnectionState = .disconnected
    var antennaState = AntennaState()
    var log: [LogEntry] = []
    var lastError: String?          // Set on NAK; auto-cleared after 4 seconds

    // Connection fields (bound to ConnectionView text fields).
    // Inline defaults are overridden in init() from UserDefaults.
    var hostField = "dahlstar.local"
    var portField = "4242"

    // Motion input
    var moveStepsField = "10000"

    // Speed fields (updated from ACK:SPEED / ACK:HOMESPEED responses)
    var speedField = "1000"
    var homeSpeedField = "1000"

    // Band presets (step positions saved per amateur band)
    var bandPresets = BandPresetsStore()

    // ── Internals ─────────────────────────────────────────────────────────────

    private let transport = WiFiTransport()
    private var receiveTask: Task<Void, Never>?
    private var motionEndTask: Task<Void, Never>?   // deferred CMD:STATUS after motion stops
    private var reconnectTask: Task<Void, Never>?   // auto-reconnect after unexpected disconnect
    private var errorClearTask: Task<Void, Never>?  // auto-dismiss NAK banner
    private var userInitiatedDisconnect = false
    private let maxLogLines = 300

    init() {
        // Restore last-used connection params. Inline defaults ("dahlstar.local" / "4242")
        // are already set by the time this body runs, so setters are safe to call here.
        if let h = UserDefaults.standard.string(forKey: "dahlstar.host") { hostField = h }
        if let p = UserDefaults.standard.string(forKey: "dahlstar.port") { portField = p }
    }

    // ── Connection ────────────────────────────────────────────────────────────

    func connect() {
        guard connectionState == .disconnected || connectionState.label.hasPrefix("Error") else { return }
        guard let port = UInt16(portField.trimmingCharacters(in: .whitespaces)) else { return }
        let host = hostField.trimmingCharacters(in: .whitespaces)
        connectionState = .connecting
        userInitiatedDisconnect = false

        Task {
            do {
                try await transport.connect(host: host, port: port)
                connectionState = .connected
                // Persist successful connection params for next launch
                UserDefaults.standard.set(host, forKey: "dahlstar.host")
                UserDefaults.standard.set(portField, forKey: "dahlstar.port")
                startReceiveLoop()
                // WiFiServer::available() only wakes when client sends data — poke it
                try? await Task.sleep(for: .milliseconds(300))
                await sendCommand("CMD:STATUS", log: false)
            } catch {
                connectionState = .failed(error.localizedDescription)
                try? await Task.sleep(for: .seconds(3))
                if case .failed = connectionState { connectionState = .disconnected }
            }
        }
    }

    func disconnect() {
        userInitiatedDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        motionEndTask?.cancel()
        motionEndTask = nil
        errorClearTask?.cancel()
        errorClearTask = nil
        lastError = nil
        Task { await transport.disconnect() }
        connectionState = .disconnected
        antennaState = AntennaState()
        appendLog("Disconnected", direction: .received)
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task {
            while !Task.isCancelled {
                guard let line = await transport.nextLine() else {
                    if !Task.isCancelled && !userInitiatedDisconnect {
                        appendLog("Connection lost — attempting to reconnect…", direction: .received)
                        reconnectTask = Task { await self.attemptAutoReconnect() }
                    } else if !Task.isCancelled {
                        connectionState = .disconnected
                    }
                    return
                }
                processLine(line)
            }
        }
    }

    // Retry up to 3 times with 2s / 4s / 6s delays before giving up.
    private func attemptAutoReconnect() async {
        let host = hostField
        guard let port = UInt16(portField.trimmingCharacters(in: .whitespaces)) else {
            connectionState = .disconnected
            return
        }

        for attempt in 1...3 {
            guard !Task.isCancelled else { return }
            connectionState = .connecting
            let delay = Double(attempt * 2)
            appendLog("Reconnect attempt \(attempt)/3 (in \(Int(delay))s)…", direction: .received)

            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return  // Cancelled during sleep
            }

            guard !Task.isCancelled else { return }

            do {
                try await transport.connect(host: host, port: port)
                connectionState = .connected
                startReceiveLoop()
                try? await Task.sleep(for: .milliseconds(300))
                await sendCommand("CMD:STATUS", log: false)
                appendLog("Reconnected to \(host)", direction: .received)
                return
            } catch {
                appendLog("Reconnect attempt \(attempt) failed", direction: .received)
            }
        }

        if !Task.isCancelled {
            connectionState = .disconnected
            antennaState = AntennaState()
            appendLog("Auto-reconnect failed — connect manually to try again", direction: .received)
        }
    }

    // ── Commands ──────────────────────────────────────────────────────────────

    @discardableResult
    func sendCommand(_ cmd: String, log shouldLog: Bool = true) async -> Bool {
        if shouldLog { appendLog(cmd, direction: .sent) }
        do {
            try await transport.send(cmd)
            return true
        } catch {
            appendLog("SEND ERROR: \(error.localizedDescription)", direction: .received)
            return false
        }
    }

    func extend()  { Task { await sendCommand("CMD:EXTEND") } }
    func retract() { Task { await sendCommand("CMD:RETRACT") } }
    func stop()    { Task { await sendCommand("CMD:STOP") } }

    func move() {
        let raw = moveStepsField.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, let steps = Int(raw) else { return }
        Task { await sendCommand("CMD:MOVE:\(steps)") }
    }

    func moveToBandPreset(steps targetSteps: Int) {
        let delta = targetSteps - antennaState.position
        guard delta != 0 else { return }
        Task { await sendCommand("CMD:MOVE:\(delta)") }
    }

    func calibrate() { Task { await sendCommand("CMD:CALIBRATE") } }

    func selectTap(_ tap: String) { Task { await sendCommand("CMD:TAP:\(tap)") } }

    func motorOn()  { Task { await sendCommand("CMD:MOTOR:ON") } }
    func motorOff() { Task { await sendCommand("CMD:MOTOR:OFF") } }

    func setSpeed() {
        guard let spd = Int(speedField), spd >= 500, spd <= 4000 else { return }
        Task { await sendCommand("CMD:SPEED:\(spd)") }
    }

    func setHomeSpeed() {
        guard let spd = Int(homeSpeedField), spd >= 500, spd <= 4000 else { return }
        Task { await sendCommand("CMD:HOMESPEED:\(spd)") }
    }

    func refreshStatus() { Task { await sendCommand("CMD:STATUS") } }

    // ── Response parsing ──────────────────────────────────────────────────────

    private func processLine(_ line: String) {
        appendLog(line, direction: .received)

        if line.hasPrefix("STATUS:POS:"), let n = Int(line.dropFirst("STATUS:POS:".count)) {
            antennaState.position = n
            // Reschedule motion-end check on every position broadcast (200ms cadence).
            // 600ms after the last one, CMD:STATUS fires → STATUS:MTR:OFF clears isMoving.
            if antennaState.isMoving { scheduleMotionEndCheck() }

        } else if line.hasPrefix("STATUS:TAP:") {
            antennaState.tap = String(line.dropFirst("STATUS:TAP:".count))

        } else if line == "STATUS:MTR:ON" {
            antennaState.motorOn = true

        } else if line == "STATUS:MTR:OFF" {
            antennaState.motorOn = false
            antennaState.isMoving = false
            motionEndTask?.cancel()

        } else if line == "STATUS:CAL:DONE" {
            antennaState.calibrated = true
            antennaState.isMoving = false
            motionEndTask?.cancel()

        } else if line == "STATUS:CAL:PENDING" {
            antennaState.calibrated = false

        } else if line.hasPrefix("STATUS:LIMIT:") {
            antennaState.limitSwitch = line.hasSuffix("HIGH")

        } else if line == "ACK:MOTOR:ON" {
            antennaState.motorOn = true

        } else if line == "ACK:MOTOR:OFF" {
            antennaState.motorOn = false

        } else if line.hasPrefix("ACK:TAP:") {
            antennaState.tap = String(line.dropFirst("ACK:TAP:".count))

        } else if line == "ACK:CALIBRATE" || line == "ACK:HOME" {
            antennaState.isMoving = true
            antennaState.calibrated = false

        } else if line == "ACK:EXTEND" || line == "ACK:RETRACT" || line == "ACK:MOVE" {
            antennaState.isMoving = true

        } else if line == "ACK:STOP" {
            antennaState.isMoving = false
            motionEndTask?.cancel()
            Task { await sendCommand("CMD:STATUS", log: false) }

        } else if line.hasPrefix("ACK:SPEED:"), let v = Int(line.dropFirst("ACK:SPEED:".count)) {
            speedField = String(v)

        } else if line.hasPrefix("ACK:HOMESPEED:"), let v = Int(line.dropFirst("ACK:HOMESPEED:".count)) {
            homeSpeedField = String(v)

        } else if line.hasPrefix("NAK:") {
            lastError = line
            scheduleErrorClear()
        }
    }

    private func scheduleMotionEndCheck() {
        motionEndTask?.cancel()
        motionEndTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, connectionState == .connected else { return }
            await sendCommand("CMD:STATUS", log: false)
        }
    }

    private func scheduleErrorClear() {
        errorClearTask?.cancel()
        errorClearTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            lastError = nil
        }
    }

    // ── Activity log ──────────────────────────────────────────────────────────

    private func appendLog(_ text: String, direction: LogEntry.Direction) {
        log.append(LogEntry(text: text, direction: direction))
        if log.count > maxLogLines {
            log.removeFirst(log.count - maxLogLines)
        }
    }
}
