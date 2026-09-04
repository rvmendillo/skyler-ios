import SceneKit

// SceneKit has no built-in octahedron primitive; this alias gives the shrine
// a compact faceted crystal while keeping the world fully procedural.
typealias SCNOctahedron = SCNPyramid

extension SCNPyramid {
    convenience init(radius: CGFloat) {
        self.init(width: radius * 1.55, height: radius * 2.15, length: radius * 1.55)
    }
}
