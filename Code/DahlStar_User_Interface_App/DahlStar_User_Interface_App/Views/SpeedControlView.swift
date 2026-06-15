// SpeedControlView.swift — Move speed and home speed controls.
// Both firmware parameters are constrained to 500–4000 steps/sec.
// Below 500 the L298P voltage-mode driver hits overcurrent at low speed.

import SwiftUI

struct SpeedControlView: View {
    @Bindable var vm: AntennaViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Range: 500 – 4000 steps/sec  (minimum 500 prevents L298P overcurrent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                speedRow(label: "Move speed",
                         text: $vm.speedField,
                         onSet: { vm.setSpeed() })

                speedRow(label: "Home speed",
                         text: $vm.homeSpeedField,
                         onSet: { vm.setHomeSpeed() })
            }
            .padding(8)
        } label: {
            Label("Speeds", systemImage: "speedometer")
                .font(.headline)
        }
    }

    private func speedRow(label: String,
                          text: Binding<String>,
                          onSet: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label + ":")
                .frame(width: 96, alignment: .trailing)
                .foregroundStyle(.secondary)
            TextField("1000", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .onSubmit { onSet() }
            Text("steps/sec")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Set") { onSet() }
                .buttonStyle(.bordered)
                .disabled(!vm.connectionState.isConnected)
        }
    }
}
