// ActivityLogView.swift — Scrolling monospace log of commands sent and responses received.
// Colors: green = ACK, red = NAK, cyan = STATUS, gray = sent commands.

import SwiftUI

struct ActivityLogView: View {
    let log: [LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logHeader
            Divider()
            logBody
        }
        .background(.windowBackground)
    }

    private var logHeader: some View {
        HStack {
            Text("Activity Log")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(log.count) lines")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(log) { entry in
                        logRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: log.count) { _, _ in
                if let last = log.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.directionMark)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(width: 12, alignment: .center)
            Text(entry.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(entry.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
    }
}
