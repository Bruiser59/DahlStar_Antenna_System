// SerialPort.swift — POSIX termios serial port for macOS
// Opens a serial device, configures baud/framing, provides line-oriented I/O.

import Foundation
#if canImport(Darwin)
import Darwin
#endif

final class SerialPort {

    private let fd: Int32
    private var rxBuf = ""

    // ── Open ──────────────────────────────────────────────────────────────────

    init(path: String, baud: Int = 115200) throws {
        fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd != -1 else {
            throw SerialError.openFailed(path, errno)
        }
        // Exclusive access
        guard ioctl(fd, UInt(TIOCEXCL)) != -1 else {
            Darwin.close(fd)
            throw SerialError.ioctlFailed("TIOCEXCL", errno)
        }
        // Switch to blocking I/O
        var flags = fcntl(fd, F_GETFL)
        flags &= ~O_NONBLOCK
        _ = fcntl(fd, F_SETFL, flags)

        try configure(baud: baud)
    }

    deinit { Darwin.close(fd) }

    // ── Configure ─────────────────────────────────────────────────────────────

    private func configure(baud: Int) throws {
        var tty = termios()
        guard tcgetattr(fd, &tty) == 0 else {
            throw SerialError.tcgetFailed(errno)
        }
        // 8N1, no flow control
        cfmakeraw(&tty)
        tty.c_cflag &= ~UInt(CSIZE)
        tty.c_cflag |= UInt(CS8 | CREAD | CLOCAL)
        tty.c_cflag &= ~UInt(PARENB | CSTOPB | CRTSCTS)
        tty.c_lflag  = 0
        tty.c_iflag  = 0
        tty.c_oflag  = 0
        // Minimal read: return when ≥1 byte available, no timeout
        tty.c_cc.16 = 1   // VMIN  — index 16 in the c_cc tuple
        tty.c_cc.17 = 0   // VTIME — index 17

        let b = speed_t(baudConstant(baud))
        cfsetispeed(&tty, b)
        cfsetospeed(&tty, b)

        guard tcsetattr(fd, TCSANOW, &tty) == 0 else {
            throw SerialError.tcsetFailed(errno)
        }
        tcdrain(fd)
    }

    private func baudConstant(_ baud: Int) -> Int32 {
        switch baud {
        case 9600:   return B9600
        case 19200:  return B19200
        case 38400:  return B38400
        case 57600:  return B57600
        case 115200: return B115200
        default:     return B115200
        }
    }

    // ── Write ─────────────────────────────────────────────────────────────────

    /// Send a command line. Appends `\n` automatically.
    func send(_ line: String) throws {
        let bytes = (line + "\n").utf8
        let count = bytes.count
        let written = bytes.withContiguousStorageIfAvailable { ptr -> Int in
            Darwin.write(fd, ptr.baseAddress!, count)
        } ?? 0
        if written != count {
            throw SerialError.writeFailed(errno)
        }
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    /// Read all available bytes, split into complete lines. Returns whatever complete
    /// lines are ready; partial final line is buffered for the next call.
    func readLines() -> [String] {
        var buf = [UInt8](repeating: 0, count: 256)
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

    // ── Port Discovery ────────────────────────────────────────────────────────

    /// Returns the first `/dev/cu.usbmodem*` path found (Arduino on USB).
    static func findArduinoPort() -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: "/dev") else { return nil }
        return entries
            .filter { $0.hasPrefix("cu.usbmodem") }
            .sorted()
            .first
            .map { "/dev/" + $0 }
    }
}

// ── Errors ────────────────────────────────────────────────────────────────────

enum SerialError: Error, CustomStringConvertible {
    case openFailed(String, Int32)
    case ioctlFailed(String, Int32)
    case tcgetFailed(Int32)
    case tcsetFailed(Int32)
    case writeFailed(Int32)

    var description: String {
        switch self {
        case .openFailed(let p, let e):  return "Cannot open \(p): \(String(cString: strerror(e)))"
        case .ioctlFailed(let n, let e): return "ioctl \(n) failed: \(String(cString: strerror(e)))"
        case .tcgetFailed(let e):        return "tcgetattr failed: \(String(cString: strerror(e)))"
        case .tcsetFailed(let e):        return "tcsetattr failed: \(String(cString: strerror(e)))"
        case .writeFailed(let e):        return "write failed: \(String(cString: strerror(e)))"
        }
    }
}
