// BandPreset.swift — Persisted mapping of amateur bands to antenna step positions.
// Positions must be determined empirically after antenna commissioning.

import Observation
import Foundation

@Observable
final class BandPresetsStore {
    static let allBands = ["80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m"]

    // band name → absolute step count
    var presets: [String: Int] = [:]

    init() { load() }

    func preset(for band: String) -> Int? { presets[band] }

    func save(band: String, steps: Int) {
        presets[band] = steps
        persist()
    }

    func remove(band: String) {
        presets.removeValue(forKey: band)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: "dahlstar.bandPresets")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "dahlstar.bandPresets"),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return }
        presets = decoded
    }
}
