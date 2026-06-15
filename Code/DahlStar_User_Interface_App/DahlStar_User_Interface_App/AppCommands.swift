// AppCommands.swift — macOS menu bar Antenna commands and FocusedValueKey injection.

import SwiftUI

// ── FocusedValue key ──────────────────────────────────────────────────────────

private struct DahlStarVMKey: FocusedValueKey {
    typealias Value = AntennaViewModel
}

extension FocusedValues {
    var dahlStarVM: AntennaViewModel? {
        get { self[DahlStarVMKey.self] }
        set { self[DahlStarVMKey.self] = newValue }
    }
}

// ── Commands ──────────────────────────────────────────────────────────────────

struct DahlStarCommands: Commands {
    @FocusedValue(\.dahlStarVM) var vm: AntennaViewModel?

    private var connected: Bool { vm?.connectionState.isConnected == true }
    private var calibrated: Bool { vm?.antennaState.calibrated == true }

    var body: some Commands {
        CommandMenu("Antenna") {
            Button("Refresh Status") {
                vm?.refreshStatus()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!connected)

            Divider()

            Button("Stop Motor") {
                vm?.stop()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(!connected)

            Button("Extend Coil") {
                vm?.extend()
            }
            .disabled(!connected || !calibrated)

            Button("Retract Coil") {
                vm?.retract()
            }
            .disabled(!connected || !calibrated)

            Divider()

            Button("Disconnect") {
                vm?.disconnect()
            }
            .disabled(!connected)
        }
    }
}
