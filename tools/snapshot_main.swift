// Offscreen render harness: compiles together with Sources/ and writes PNG snapshots.
// Usage: snapshot <out-dir> [seconds] [width] [height] [joints 0-3]
import AppKit
import SceneKit
import Metal

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "."
let seconds = args.count > 2 ? Double(args[2])! : 12
let w = args.count > 3 ? Double(args[3])! : 1280
let h = args.count > 4 ? Double(args[4])! : 800
var settings = PipesSettings()
if args.count > 5, let j = PipesSettings.Joints(rawValue: Int(args[5])!) { settings.joints = j }
settings.resetInterval = args.count > 6 ? Double(args[6])! : 1000

let engine = PipesEngine(settings: settings, viewSize: CGSize(width: w, height: h))
let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
renderer.scene = engine.scene
renderer.pointOfView = engine.cameraNode
renderer.overlaySKScene = engine.overlay
let dt = 1.0 / 60
var t = 0.0
var shot = 0
let start = Date()
while t < seconds {
    engine.renderer(renderer, updateAtTime: t)
    t += dt
    if Int(t / dt) % Int(seconds / 3 / dt) == 0 {
        let img = renderer.snapshot(atTime: t, with: CGSize(width: w, height: h), antialiasingMode: .multisampling4X)
        let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
        let png = rep.representation(using: .png, properties: [:])!
        let path = "\(outDir)/shot\(shot).png"
        try! png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) at t=\(String(format: "%.1f", t))")
        shot += 1
    }
}
print("simulated \(seconds)s in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
