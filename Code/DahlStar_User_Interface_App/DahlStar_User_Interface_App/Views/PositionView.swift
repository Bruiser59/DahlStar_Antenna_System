// PositionView.swift — Position readout, progress bar, and jog / move controls.

import SwiftUI

struct PositionView: View {
    @Bindable var vm: AntennaViewModel
    @State private var showMoveField = false

    private var isConnected: Bool { vm.connectionState.isConnected }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                positionReadout
                progressBar
                jogRow
                if showMoveField { moveRow }
            }
            .padding(8)
        } label: {
            Label("Position", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
    }

    // ── Subviews ──────────────────────────────────────────────────────────────

    private var positionReadout: some View {
        HStack(alignment: .lastTextBaseline) {
            if vm.antennaState.calibrated {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(vm.antennaState.position)")
                        .font(.system(.title, design: .monospaced).weight(.semibold))
                    + Text(" steps")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text(String(format: "%.2f in  ·  %.1f mm  ·  %.1f%%",
                                vm.antennaState.positionInches,
                                vm.antennaState.positionMM,
                                vm.antennaState.positionPercent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Not calibrated", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
            }

            Spacer()

            if vm.antennaState.isMoving {
                Label("Moving", systemImage: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative)
            }
        }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ProgressView(value: vm.antennaState.calibrated ? vm.antennaState.positionFraction : 0)
                .progressViewStyle(.linear)
                .animation(.easeInOut(duration: 0.15), value: vm.antennaState.positionFraction)
                .opacity(vm.antennaState.calibrated ? 1 : 0.3)

            HStack {
                Text("Home (retracted)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Extended")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var jogRow: some View {
        HStack(spacing: 8) {
            Button {
                vm.retract()
            } label: {
                Label("Retract", systemImage: "chevron.left")
            }
            .disabled(!vm.antennaState.calibrated || !isConnected)
            .accessibilityLabel("Retract coil 10,000 steps toward home")

            Button {
                vm.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!isConnected)
            .keyboardShortcut(".", modifiers: [.command])
            .accessibilityLabel("Stop motor immediately (⌘.)")

            Button {
                vm.extend()
            } label: {
                Label("Extend", systemImage: "chevron.right")
            }
            .disabled(!vm.antennaState.calibrated || !isConnected)
            .accessibilityLabel("Extend coil 10,000 steps")

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showMoveField.toggle() }
            } label: {
                Label(showMoveField ? "Hide Move" : "Move…",
                      systemImage: showMoveField ? "minus" : "arrow.left.and.right")
                    .labelStyle(.titleOnly)
            }
        }
        .buttonStyle(.bordered)
    }

    private var moveRow: some View {
        HStack(spacing: 8) {
            Text("Move:")
                .foregroundStyle(.secondary)
            TextField("+/− steps", text: $vm.moveStepsField)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .onSubmit { vm.move() }
            Text("steps (+ = extend, − = retract)")
                .foregroundStyle(.secondary)
                .font(.caption)
            Spacer()
            Button("Send") { vm.move() }
                .disabled(!vm.antennaState.calibrated || !isConnected)
        }
        .buttonStyle(.bordered)
    }
}
