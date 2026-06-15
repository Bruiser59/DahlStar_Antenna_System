// TapSelectorView.swift — UNUN tap selector (9T through 13T).
// The 11T tap is Normally Closed on K3 — it's the power-on default.

import SwiftUI

struct TapSelectorView: View {
    let vm: AntennaViewModel

    var body: some View {
        GroupBox {
            HStack(spacing: 0) {
                ForEach(AntennaState.allTaps, id: \.self) { tap in
                    tapButton(tap)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator, lineWidth: 1))
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        } label: {
            HStack(spacing: 6) {
                Label("UNUN Tap", systemImage: "tuningfork")
                    .font(.headline)
                Spacer()
                Text("Active: \(vm.antennaState.tap)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tapButton(_ tap: String) -> some View {
        let isSelected = vm.antennaState.tap == tap
        let isDefault = tap == "11T"   // NC relay — power-on default
        return Button {
            vm.selectTap(tap)
        } label: {
            VStack(spacing: 2) {
                Text(tap)
                    .font(.system(.body, design: .monospaced).weight(isSelected ? .bold : .regular))
                if isDefault && !isSelected {
                    Text("default")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(" ").font(.system(size: 8))  // keeps height uniform
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!vm.connectionState.isConnected)
        .accessibilityLabel("UNUN tap \(tap)\(isDefault ? ", power-on default" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
