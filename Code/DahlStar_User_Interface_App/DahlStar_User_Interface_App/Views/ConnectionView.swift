// ConnectionView.swift — Shown when not connected; hosts the connection form.

import SwiftUI

struct ConnectionView: View {
    @Bindable var vm: AntennaViewModel

    var body: some View {
        VStack(spacing: 28) {
            // Title
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                Text("DahlStar Controller")
                    .font(.largeTitle.bold())
                Text("HF Vertical Antenna — Remote Control")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Connection form
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Host")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                    TextField("dahlstar.local", text: $vm.hostField)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit { vm.connect() }
                }
                GridRow {
                    Text("Port")
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("4242", text: $vm.portField)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onSubmit { vm.connect() }
                        Spacer()
                    }
                }
            }

            // Status + connect button
            VStack(spacing: 12) {
                statusRow
                Button("Connect") { vm.connect() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(vm.connectionState == .connecting)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityLabel("Connect to DahlStar antenna controller")
            }
        }
        .padding(40)
        .frame(minWidth: 440, minHeight: 420)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch vm.connectionState {
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting to \(vm.hostField)…")
                    .foregroundStyle(.secondary)
            }
        case .failed(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 340)
        default:
            EmptyView()
        }
    }
}
