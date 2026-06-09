// TCPPort.swift — POSIX TCP client for macOS
// Connects to a hostname:port, provides the same line-oriented interface as SerialPort.
// Hostname resolution uses the system resolver, so "dahlstar.local" (mDNS) works natively.

import Foundation
#if canImport(Darwin)
import Darwin
#endif

final class TCPPort {

    private let fd: Int32
    private var rxBuf = ""

    // ── Connect ───────────────────────────────────────────────────────────────

    init(hostname: String, port: UInt16) throws {
        var hints = addrinfo()
        hints.ai_family   = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var res: UnsafeMutablePointer<addrinfo>? = nil
        let portStr = String(port)
        let rc = getaddrinfo(hostname, portStr, &hints, &res)
        guard rc == 0, let addr = res else {
            throw TCPError.resolveFailed(hostname, rc)
        }
        defer { freeaddrinfo(res) }

        let sock = socket(addr.pointee.ai_family, addr.pointee.ai_socktype, addr.pointee.ai_protocol)
        guard sock != -1 else { throw TCPError.socketFailed(errno) }

        guard connect(sock, addr.pointee.ai_addr, addr.pointee.ai_addrlen) == 0 else {
            Darwin.close(sock)
            throw TCPError.connectFailed(hostname, port, errno)
        }

        // Non-blocking reads so the REPL background thread can poll
        var flags = fcntl(sock, F_GETFL)
        flags |= O_NONBLOCK
        _ = fcntl(sock, F_SETFL, flags)

        fd = sock
    }

    deinit { Darwin.close(fd) }

    // ── Write ─────────────────────────────────────────────────────────────────

    func send(_ line: String) throws {
        let bytes = (line + "\n").utf8
        let count = bytes.count
        let written = bytes.withContiguousStorageIfAvailable { ptr -> Int in
            Darwin.write(fd, ptr.baseAddress!, count)
        } ?? 0
        if written != count { throw TCPError.writeFailed(errno) }
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func readLines() -> [String] {
        var buf = [UInt8](repeating: 0, count: 512)
        var lines: [String] = []
        while true {
            let n = Darwin.read(fd, &buf, buf.count)
            if n <= 0 { break }
            rxBuf += String(bytes: buf.prefix(n), encoding: .utf8) ?? ""
        }
        while let nl = rxBuf.firstIndex(of: "\n") {
            let line = String(rxBuf[rxBuf.startIndex..<nl])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            rxBuf.removeSubrange(rxBuf.startIndex...nl)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    // ── Connectivity check ────────────────────────────────────────────────────

    var isConnected: Bool {
        var err: Int32 = 0
        var errLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &errLen)
        return err == 0
    }
}

// ── Errors ────────────────────────────────────────────────────────────────────

enum TCPError: Error, CustomStringConvertible {
    case resolveFailed(String, Int32)
    case socketFailed(Int32)
    case connectFailed(String, UInt16, Int32)
    case writeFailed(Int32)

    var description: String {
        switch self {
        case .resolveFailed(let h, let rc): return "Cannot resolve \(h): \(String(cString: gai_strerror(rc)))"
        case .socketFailed(let e):          return "socket() failed: \(String(cString: strerror(e)))"
        case .connectFailed(let h, let p, let e): return "Cannot connect to \(h):\(p) — \(String(cString: strerror(e)))"
        case .writeFailed(let e):           return "write() failed: \(String(cString: strerror(e)))"
        }
    }
}
