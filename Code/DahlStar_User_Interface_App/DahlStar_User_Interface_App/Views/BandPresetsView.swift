// BandPresetsView.swift — One-tap band tuning using saved step positions.
// Right-click any band button to save or clear its preset.

import SwiftUI

struct BandPresetsView: View {
    let vm: AntennaViewModel

    private var isConnected: Bool { vm.connectionState.isConnected }
    private var isCalibrated: Bool { vm.antennaState.calibrated }

    let columns = [GridItem(.adaptive(minimum: 70), spacing: 6)]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Right-click a band to save the current position as a preset. Tap to move there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(BandPresetsStore.allBands, id: \.self) { band in
                        bandButton(band)
                    }
                }
            }
            .padding(8)
        } label: {
            Label("Band Presets", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
        }
    }

    @ViewBuilder
    private func bandButton(_ band: String) -> some View {
        let savedSteps = vm.bandPresets.preset(for: band)
        let hasPreset = savedSteps != nil

        Button {
            if let steps = savedSteps {
                vm.moveToBandPreset(steps: steps)
            }
        } label: {
            VStack(spacing: 2) {
                Text(band)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                if let steps = savedSteps {
                    Text("\(steps)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("not set")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
        }
        .buttonStyle(.bordered)
        .tint(hasPreset ? .accentColor : nil)
        .disabled(!hasPreset || !isCalibrated || !isConnected)
        .help(helpText(band: band, savedSteps: savedSteps))
        .contextMenu {
            if isCalibrated && isConnected {
                Button("Save '\(band)' at step \(vm.antennaState.position)") {
                    vm.bandPresets.save(band: band, steps: vm.antennaState.position)
                }
            } else {
                Text(isCalibrated ? "Not connected" : "Calibrate before saving")
            }
            if hasPreset {
                Divider()
                Button("Clear '\(band)' preset", role: .destructive) {
                    vm.bandPresets.remove(band: band)
                }
            }
        }
        .accessibilityLabel(accessibilityLabel(band: band, savedSteps: savedSteps))
        .accessibilityHint(hasPreset ? "Double-tap to move antenna to \(band) position" : "Right-click to save current position as \(band) preset")
    }

    private func helpText(band: String, savedSteps: Int?) -> String {
        if let steps = savedSteps {
            return "Move to \(band) preset (\(steps) steps). Right-click to update or clear."
        }
        return "Right-click to save current position as \(band) preset"
    }

    private func accessibilityLabel(band: String, savedSteps: Int?) -> String {
        if let steps = savedSteps {
            return "\(band) preset, \(steps) steps"
        }
        return "\(band), no preset saved"
    }
}
