import Foundation
import ScreenSaver

/// User-configurable options, persisted with ScreenSaverDefaults.
struct PipesSettings: Equatable {
    enum Joints: Int, CaseIterable {
        case elbow = 0, ball, mixed, cycle

        var title: String {
            switch self {
            case .elbow: return "Elbow"
            case .ball: return "Ball"
            case .mixed: return "Mixed"
            case .cycle: return "Cycle"
            }
        }
    }

    var joints: Joints = .mixed
    /// Grid segments grown per second, per pipe.
    var speed: Double = 25
    /// How many pipes grow simultaneously.
    var pipeCount: Int = 3
    /// Seconds between dissolve/reset.
    var resetInterval: Double = 25
    /// Slowly orbit the camera around the scene.
    var rotateCamera: Bool = false
    /// Easter egg from the original: occasional teapots in place of joints, and rare candy-cane rounds.
    var teapots: Bool = true

    static let speedRange: ClosedRange<Double> = 5...80
    static let pipeCountRange: ClosedRange<Int> = 1...8
    static let resetIntervalRange: ClosedRange<Double> = 10...120

    private enum Key {
        static let joints = "joints"
        static let speed = "speed"
        static let pipeCount = "pipeCount"
        static let resetInterval = "resetInterval"
        static let rotateCamera = "rotateCamera"
        static let teapots = "teapots"
    }

    private static var defaults: UserDefaults? {
        let id = Bundle(for: PipesSaverView.self).bundleIdentifier ?? "local.pipesaver.Pipes"
        return ScreenSaverDefaults(forModuleWithName: id)
    }

    static func load() -> PipesSettings {
        var s = PipesSettings()
        guard let d = defaults else { return s }
        if let v = d.object(forKey: Key.joints) as? Int, let j = Joints(rawValue: v) { s.joints = j }
        if let v = d.object(forKey: Key.speed) as? Double { s.speed = v.clamped(to: speedRange) }
        if let v = d.object(forKey: Key.pipeCount) as? Int { s.pipeCount = min(max(v, pipeCountRange.lowerBound), pipeCountRange.upperBound) }
        if let v = d.object(forKey: Key.resetInterval) as? Double { s.resetInterval = v.clamped(to: resetIntervalRange) }
        if let v = d.object(forKey: Key.rotateCamera) as? Bool { s.rotateCamera = v }
        if let v = d.object(forKey: Key.teapots) as? Bool { s.teapots = v }
        return s
    }

    func save() {
        guard let d = PipesSettings.defaults else { return }
        d.set(joints.rawValue, forKey: Key.joints)
        d.set(speed, forKey: Key.speed)
        d.set(pipeCount, forKey: Key.pipeCount)
        d.set(resetInterval, forKey: Key.resetInterval)
        d.set(rotateCamera, forKey: Key.rotateCamera)
        d.set(teapots, forKey: Key.teapots)
        d.synchronize()
    }
}

extension Double {
    func clamped(to r: ClosedRange<Double>) -> Double { Swift.min(Swift.max(self, r.lowerBound), r.upperBound) }
}
