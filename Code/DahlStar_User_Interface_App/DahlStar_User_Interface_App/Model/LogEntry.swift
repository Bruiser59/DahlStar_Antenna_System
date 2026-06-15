// LogEntry.swift — One line in the activity log (sent or received).

import SwiftUI

struct LogEntry: Identifiable {
    let id = UUID()
    let text: String
    let direction: Direction
    let timestamp = Date()

    enum Direction { case sent, received }

    var directionMark: String { direction == .sent ? "→" : "←" }

    var color: Color {
        guard direction == .received else { return .secondary }
        if text.hasPrefix("ACK:")    { return .green }
        if text.hasPrefix("NAK:")    { return .red }
        if text.hasPrefix("STATUS:") { return .cyan }
        return .primary
    }
}
