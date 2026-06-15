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
    private(set) var connectionClosed = false

    // ── Connect ───────────────────────────────────────────────────────────────

    init(hostname: String, port: UInt16) throws {
        var hints = addrinfo()
        hints.ai_family   = AF_INET    // Arduino WiFiS3 only supports IPv4
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

        // Disable Nagle so small commands flush immediately (no 200ms delay)
        var nodelay: Int32 = 1
        setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &nodelay, socklen_t(MemoryLayout<Int32>.size))

        // SO_RCVTIMEO: read() waits up to 200ms for data, then returns EAGAIN.
        // Better than O_NONBLOCK, which returned EAGAIN immediately before Arduino's
        // response could arrive — causing the harness to never see incoming data.
        var tv = timeval()
        tv.tv_sec  = 0
        tv.tv_usec = 200_000   // 200 ms
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        fd = sock
    }

    deinit { Darwin.close(fd) }

    // ── Write ─────────────────────────────────────────────────────────────────

    func send(_ line: String) throws {
        var bytes = Array((line + "\n").utf8)
        let written = Darwin.write(fd, &bytes, bytes.count)
        if written != bytes.count { throw TCPError.writeFailed(errno) }
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func readLines() -> [String] {
        var buf = [UInt8](repeating: 0, count: 512)
        var lines: [String] = []
        while true {
            // withUnsafeMutableBytes pins buf's real storage so read() writes into
            // it directly — &buf passes a temporary that gets discarded on return.
            let n = buf.withUnsafeMutableBytes { ptr -> Int in
                Darwin.read(fd, ptr.baseAddress!, ptr.count)
            }
            if n > 0 {
                rxBuf += String(decoding: buf[..<n], as: UTF8.self)
            } else {
                if n == 0 {
                    connectionClosed = true
                } else if errno != EAGAIN && errno != EWOULDBLOCK {
                    fputs("TCP:ERR:\(errno) \(String(cString: strerror(errno)))\n", stderr)
                }
                break
            }
        }
        // Arduino sends \r\n; Swift decodes CR+LF as a single grapheme cluster that
        // doesn't equal the lone '\n' Character firstIndex searches for. Normalize first.
        rxBuf = rxBuf.replacingOccurrences(of: "\r\n", with: "\n")
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
