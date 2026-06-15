// AntennaState.swift — Value snapshot of the antenna controller's state.
// Updated by AntennaViewModel as STATUS/ACK responses arrive over TCP.

struct AntennaState {
    var position: Int = 0          // steps from home (0 = fully retracted)
    var tap: String = "11T"        // active UNUN tap: 9T/10T/11T/12T/13T
    var motorOn: Bool = false      // K8 motor power relay energized
    var calibrated: Bool = false   // firmware has a valid home position
    var isMoving: Bool = false     // motion command accepted and in progress
    var limitSwitch: Bool = false  // HIGH = coil at home (limit switch actuated)

    static let maxSteps = 289799   // 17 in × 25.4 mm/in ÷ 0.00149 mm/step
    static let allTaps = ["9T", "10T", "11T", "12T", "13T"]

    var positionFraction: Double {
        guard Self.maxSteps > 0 else { return 0 }
        return min(1.0, max(0.0, Double(position) / Double(Self.maxSteps)))
    }

    var positionPercent: Double { positionFraction * 100.0 }
    var positionMM: Double { Double(position) * 0.00149 }
    var positionInches: Double { positionMM / 25.4 }
}
