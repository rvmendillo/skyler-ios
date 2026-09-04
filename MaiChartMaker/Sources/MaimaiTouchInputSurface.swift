import SwiftUI
import UIKit

enum MaimaiInputSensor: Hashable {
    case lane(Int)
    case touch(String)

    var key: String {
        switch self {
        case .lane(let lane):
            return "L\(lane)"
        case .touch(let region):
            return "T:\(region)"
        }
    }
}

struct MaimaiTouchInputSurface: UIViewRepresentable {
    let onSensorChange: (MaimaiInputSensor, Bool) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isMultipleTouchEnabled = true
        view.onSensorChange = onSensorChange
        return view
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.onSensorChange = onSensorChange
    }

    final class TouchView: UIView {
        var onSensorChange: ((MaimaiInputSensor, Bool) -> Void)?
        private var active: [ObjectIdentifier: MaimaiInputSensor] = [:]

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                let id = ObjectIdentifier(touch)
                let sensor = sensor(at: touch.location(in: self))
                active[id] = sensor
                onSensorChange?(sensor, true)
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                let id = ObjectIdentifier(touch)
                let newSensor = sensor(at: touch.location(in: self))
                let oldSensor = active[id]

                guard oldSensor != newSensor else { continue }

                if let oldSensor {
                    onSensorChange?(oldSensor, false)
                }

                active[id] = newSensor
                onSensorChange?(newSensor, true)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches)
        }

        private func finish(_ touches: Set<UITouch>) {
            for touch in touches {
                let id = ObjectIdentifier(touch)
                if let sensor = active.removeValue(forKey: id) {
                    onSensorChange?(sensor, false)
                }
            }
        }

        private func sensor(at point: CGPoint) -> MaimaiInputSensor {
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = hypot(dx, dy)
            let radius = max(1, min(bounds.width, bounds.height) * 0.5)
            let normalized = distance / radius

            if normalized < 0.22 {
                return .touch("C")
            }

            let angle = atan2(dy, dx) + (.pi / 2)
            let normalizedAngle = angle < 0 ? angle + 2 * .pi : angle
            let sector = Int((normalizedAngle / (.pi / 4)).rounded()) % 8
            let lane = sector + 1

            if normalized >= 0.72 {
                return .lane(lane)
            }

            if normalized < 0.46 {
                return .touch("B\(lane)")
            }

            return .touch("E\(lane)")
        }
    }
}
