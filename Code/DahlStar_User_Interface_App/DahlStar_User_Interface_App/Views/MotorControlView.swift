// MotorControlView.swift — Motor power and calibration controls.
// Calibrate triggers homing: the coil retracts until the limit switch fires.
// A confirmation dialog is shown before starting calibration.

import SwiftUI

struct MotorControlView: View {
    let vm: AntennaViewModel
    @State private var showCalibrateConfirm = false

    private var isConnected: Bool { vm.connectionState.isConnected }
    private var isMoving: Bool   { vm.antennaState.isMoving }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                motorRow
                Divider().padding(.vertical, 10)
                calibrateRow
            }
            .padding(8)
        } label: {
            Label("Motor Control", systemImage: "bolt.fill")
                .font(.headline)
        }
        .confirmationDialog(
            "Calibrate Antenna?",
            isPresented: $showCalibrateConfirm,
            titleVisibility: .visible
        ) {
            Button("Start Calibration", role: .destructive) {
                vm.calibrate()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The loading coil will retract to the home position (limit switch). Ensure the antenna cable and coil are clear of obstructions.")
        }
    }

    // ── Motor power row ───────────────────────────────────────────────────────

    private var motorRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Motor Power")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Circle()
                        .fill(vm.antennaState.motorOn ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 7, height: 7)
                    Text(vm.antennaState.motorOn ? "ON" : "OFF")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Motor ON") { vm.motorOn() }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .disabled(!isConnected || vm.antennaState.motorOn || isMoving)

                Button("Motor OFF") { vm.motorOff() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!isConnected || !vm.antennaState.motorOn || isMoving)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // ── Calibrate row ─────────────────────────────────────────────────────────

    private var calibrateRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calibrate (Home)")
                    .font(.subheadline.weight(.medium))
                Text("Retract coil to limit switch to establish position zero")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showCalibrateConfirm = true
            } label: {
                Label("Calibrate…", systemImage: "target")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!isConnected || isMoving)
            .accessibilityLabel("Start antenna calibration — moves coil to home position")
        }
    }
}
