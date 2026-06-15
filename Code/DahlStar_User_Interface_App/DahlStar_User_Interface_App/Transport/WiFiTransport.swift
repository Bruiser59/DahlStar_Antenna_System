// WiFiTransport.swift — Network.framework TCP client for DahlStar macOS app
// Connects to the Arduino's TCP server (port 4242) using NWConnection.
// mDNS hostnames (e.g. "dahlstar.local") resolve natively via the system resolver.
// Exposes an async line-oriented API that AntennaViewModel consumes.

import Network
import Foundation

actor WiFiTransport {

    enum TransportError: Error, LocalizedError {
        case notConnected
        case connectionFailed(NWError)
        case timeout

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Not connected to antenna controller"
            case .connectionFailed(let e):
                return e.localizedDescription
            case .timeout:
                return "Connection timed out"
            }
        }
    }

    // ── State ─────────────────────────────────────────────────────────────────

    private var connection: NWConnection?
    private var rxBuf = ""
    private var bufferedLines: [String] = []
    private var waiters: [CheckedContinuation<String?, Never>] = []
    private var isClosed = true

    // NWConnection callbacks fire on this queue; actor methods hop back via Task.
    private let nwQueue = DispatchQueue(label: "com.dahlstar.wifi.nw", qos: .utility)

    // ── Connect ───────────────────────────────────────────────────────────────

    func connect(host: String, port: UInt16) async throws {
        // Tear down any existing connection first
        connection?.cancel()
        isClosed = false
        bufferedLines = []
        for w in waiters { w.resume(returning: nil) }
        waiters = []

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let params = NWParameters.tcp
        // Disable Nagle so small ASCII commands flush immediately
        if let tcpOpts = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOpts.noDelay = true
        }

        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false

            // Set a 10-second connection timeout
            let timeoutWork = DispatchWorkItem {
                if !resumed {
                    resumed = true
                    conn.cancel()
                    cont.resume(throwing: TransportError.timeout)
                }
            }
            self.nwQueue.asyncAfter(deadline: .now() + 10, execute: timeoutWork)

            conn.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if !resumed {
                        resumed = true
                        timeoutWork.cancel()
                        cont.resume()
                    }
                    Task { await self.beginReceiving(conn) }
                case .failed(let error):
                    if !resumed {
                        resumed = true
                        timeoutWork.cancel()
                        cont.resume(throwing: TransportError.connectionFailed(error))
                    }
                    Task { await self.markClosed() }
                case .cancelled:
                    if !resumed {
                        resumed = true
                        timeoutWork.cancel()
                        cont.resume(throwing: CancellationError())
                    }
                    Task { await self.markClosed() }
                default:
                    break
                }
            }
            conn.start(queue: self.nwQueue)
        }
    }

    // ── Send ──────────────────────────────────────────────────────────────────

    func send(_ line: String) async throws {
        guard let conn = connection else { throw TransportError.notConnected }
        let data = Data((line + "\n").utf8)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    // ── Receive ───────────────────────────────────────────────────────────────

    // Returns the next complete line from the firmware, or nil if connection closed.
    func nextLine() async -> String? {
        if !bufferedLines.isEmpty { return bufferedLines.removeFirst() }
        if isClosed { return nil }
        return await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    // ── Disconnect ────────────────────────────────────────────────────────────

    func disconnect() {
        connection?.cancel()
        connection = nil
        markClosed()
    }

    // ── Internal receive loop ─────────────────────────────────────────────────

    private func beginReceiving(_ conn: NWConnection) {
        guard !isClosed else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { await self.handleReceived(data: data, isComplete: isComplete, error: error, conn: conn) }
        }
    }

    private func handleReceived(data: Data?, isComplete: Bool, error: NWError?, conn: NWConnection) {
        if let data, !data.isEmpty, let str = String(data: data, encoding: .utf8) {
            rxBuf += str
            // Arduino sends \r\n; normalize to \n before splitting
            rxBuf = rxBuf.replacingOccurrences(of: "\r\n", with: "\n")
            while let nl = rxBuf.firstIndex(of: "\n") {
                let line = String(rxBuf[rxBuf.startIndex..<nl])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                rxBuf.removeSubrange(rxBuf.startIndex...nl)
                if !line.isEmpty { deliverLine(line) }
            }
        }
        if isComplete || error != nil {
            markClosed()
            return
        }
        beginReceiving(conn)
    }

    private func deliverLine(_ line: String) {
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: line)
        } else {
            bufferedLines.append(line)
        }
    }

    private func markClosed() {
        isClosed = true
        for w in waiters { w.resume(returning: nil) }
        waiters.removeAll()
    }
}
