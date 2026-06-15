// MainView.swift — Primary control panel shown when connected to the antenna controller.

import SwiftUI

struct MainView: View {
    let vm: AntennaViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if let error = vm.lastError {
                nakBanner(error)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ScrollView {
                VStack(spacing: 14) {
                    PositionView(vm: vm)
                    BandPresetsView(vm: vm)
                    TapSelectorView(vm: vm)
                    MotorControlView(vm: vm)
                    SpeedControlView(vm: vm)
                }
                .padding(16)
            }
            Divider()
            ActivityLogView(log: vm.log)
                .frame(height: 175)
        }
        .frame(minWidth: 500, minHeight: 640)
        .animation(.easeInOut(duration: 0.2), value: vm.lastError != nil)
    }

    // ── NAK error banner ──────────────────────────────────────────────────────

    private func nakBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .accessibilityLabel("Firmware error: \(message)")
            Spacer()
            Button {
                vm.lastError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.1))
    }

    // ── Header bar ────────────────────────────────────────────────────────────

    private var headerBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("DahlStar")
                .font(.headline)
            Text("·")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(vm.hostField)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Connected to \(vm.hostField)")

            Spacer()

            if vm.antennaState.calibrated {
                Label("Calibrated", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("Uncalibrated", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider().frame(height: 16)

            Button {
                vm.refreshStatus()
            } label: {
                Label("Status", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("r", modifiers: [.command])
            .help("Refresh status from firmware (⌘R)")
            .accessibilityLabel("Refresh antenna status")

            Button("Disconnect") {
                vm.disconnect()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Disconnect from antenna controller")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
