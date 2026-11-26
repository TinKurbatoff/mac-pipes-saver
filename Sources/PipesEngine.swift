import AppKit
import SceneKit
import SpriteKit
import simd

/// Integer lattice coordinate.
struct Cell: Hashable {
    var x: Int, y: Int, z: Int
    static func + (a: Cell, b: Cell) -> Cell { Cell(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    var vector: SIMD3<Float> { SIMD3(Float(x), Float(y), Float(z)) }
}

private let allDirections: [Cell] = [
    Cell(x: 1, y: 0, z: 0), Cell(x: -1, y: 0, z: 0),
    Cell(x: 0, y: 1, z: 0), Cell(x: 0, y: -1, z: 0),
    Cell(x: 0, y: 0, z: 1), Cell(x: 0, y: 0, z: -1),
]

/// One growing pipe.
private final class Pipe {
    var cell: Cell              // cell the tip is moving away from
    var dir: Cell               // direction of the current move
    var runStart: SIMD3<Float>  // start point of the current straight run
    var runNode: SCNNode?       // the straight run currently growing
    var progress: Float = 0     // 0..1 progress of the current one-cell move
    var alive = true
    let cylinder: SCNGeometry
    let ball: SCNGeometry
    let elbow: SCNGeometry
    let teapot: SCNGeometry

    init(cell: Cell, cylinder: SCNGeometry, ball: SCNGeometry, elbow: SCNGeometry, teapot: SCNGeometry) {
        self.cell = cell
        self.dir = allDirections[0]
        self.runStart = cell.vector
        self.cylinder = cylinder
        self.ball = ball
        self.elbow = elbow
        self.teapot = teapot
    }
}

/// Builds and animates the pipes scene. All mutation happens on SceneKit's
/// render thread inside `renderer(_:updateAtTime:)`.
final class PipesEngine: NSObject, SCNSceneRendererDelegate {
    // MARK: Geometry constants (in grid units)
    private let halfExtent = 10                 // lattice spans -10...10 on each axis
    private var side: Int { halfExtent * 2 + 1 }
    private let pipeRadius: CGFloat = 0.2
    private let ballRadius: CGFloat = 0.3
    private let elbowBend: Float = 0.3          // centerline radius of elbow bends
    private let cameraDistance: Float = 14
    private let maxNodes = 7000                 // safety valve: dissolve before the scene gets too heavy

    // MARK: Scene graph
    let scene = SCNScene()
    let overlay: SKScene
    let cameraNode = SCNNode()
    private let cameraSpinner = SCNNode()
    private let cameraRig = SCNNode()
    private let pipesRoot = SCNNode()

    // Shared, material-less templates. Each pipe gets copies carrying its material.
    private let cylinderTemplate: SCNGeometry
    private let ballTemplate: SCNGeometry
    private let elbowTemplate: SCNGeometry
    private let teapotTemplate: SCNGeometry
    private lazy var candyCaneImage: NSImage = PipesEngine.makeCandyCaneImage()

    // MARK: Simulation state
    private var settings: PipesSettings
    private var pendingSettings: PipesSettings?
    private let settingsLock = NSLock()
    private var occupied: [Bool]
    private var pipes: [Pipe] = []
    private var nodeCount = 0
    private var ballChance: Double = 1.0 / 3.0
    private var teapotChance: Double = 1.0 / 200.0
    private var candyCane = false
    private var cycleIndex = 0
    private var lastTime: TimeInterval?
    private var runElapsed: Double = 0
    private var runDuration: Double = 25
    private var sceneFull = false

    private enum Phase { case growing, dissolving }
    private var phase: Phase = .growing
    private var dissolveElapsed: Double = 0
    private let dissolveDuration: Double = 1.8
    private var dissolveBlocks: [CGRect] = []
    private var dissolveAdded = 0

    init(settings: PipesSettings, viewSize: CGSize) {
        self.settings = settings
        occupied = Array(repeating: false, count: (halfExtent * 2 + 1) * (halfExtent * 2 + 1) * (halfExtent * 2 + 1))

        let cyl = SCNCylinder(radius: pipeRadius, height: 1)
        cyl.radialSegmentCount = 18
        cylinderTemplate = cyl
        let sph = SCNSphere(radius: ballRadius)
        sph.segmentCount = 24
        ballTemplate = sph
        elbowTemplate = PipesEngine.makeElbow(bend: CGFloat(elbowBend), tube: pipeRadius)
        // Same proportions as the example: teapot "radius" equals the ball-joint radius.
        teapotTemplate = Teapot.makeGeometry(size: Float(ballRadius))

        overlay = SKScene(size: CGSize(width: max(viewSize.width, 1), height: max(viewSize.height, 1)))
        overlay.scaleMode = .resizeFill
        overlay.backgroundColor = .clear
        overlay.anchorPoint = .zero

        super.init()
        buildScene()
        startNewRun()
    }

    /// Thread-safe: called from the UI when the user changes options.
    func apply(settings newSettings: PipesSettings) {
        settingsLock.lock()
        pendingSettings = newSettings
        settingsLock.unlock()
    }

    // MARK: - Scene setup

    private func buildScene() {
        scene.background.contents = NSColor.black
        scene.rootNode.addChildNode(pipesRoot)

        let camera = SCNCamera()
        camera.fieldOfView = 45
        camera.zNear = 0.5
        camera.zFar = 200
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3(0, 0, cameraDistance)
        cameraRig.addChildNode(cameraNode)
        cameraSpinner.addChildNode(cameraRig)
        scene.rootNode.addChildNode(cameraSpinner)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.color = NSColor(white: 0.30, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.color = NSColor(white: 1.0, alpha: 1)
        key.simdPosition = SIMD3(-1.2, 1.5, 0.5) * 10
        key.simdLook(at: .zero)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .directional
        fill.light!.color = NSColor(white: 0.25, alpha: 1)
        fill.simdPosition = SIMD3(1.0, -0.6, 1.2) * 10
        fill.simdLook(at: .zero)
        scene.rootNode.addChildNode(fill)
    }

    /// A quarter torus: center of curvature at the origin, arc from (bend,0,0) to (0,bend,0).
    private static func makeElbow(bend: CGFloat, tube: CGFloat, arcSegments: Int = 10, tubeSegments: Int = 18) -> SCNGeometry {
        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [Int32] = []
        for i in 0...arcSegments {
            let theta = CGFloat.pi / 2 * CGFloat(i) / CGFloat(arcSegments)
            let radial = SCNVector3(cos(theta), sin(theta), 0)
            for j in 0...tubeSegments {
                let phi = 2 * CGFloat.pi * CGFloat(j) / CGFloat(tubeSegments)
                let n = SCNVector3(radial.x * cos(phi), radial.y * cos(phi), sin(phi))
                verts.append(SCNVector3(radial.x * bend + n.x * tube, radial.y * bend + n.y * tube, n.z * tube))
                norms.append(n)
                uvs.append(CGPoint(x: CGFloat(j) / CGFloat(tubeSegments), y: CGFloat(i) / CGFloat(arcSegments) * 0.5))
            }
        }
        let stride = Int32(tubeSegments + 1)
        for i in 0..<Int32(arcSegments) {
            for j in 0..<Int32(tubeSegments) {
                let a = i * stride + j
                let b = a + stride
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms),
                                     SCNGeometrySource(textureCoordinates: uvs)],
                           elements: [element])
    }

    /// Red/white diagonal stripes that tile seamlessly (candy-cane rounds).
    private static func makeCandyCaneImage() -> NSImage {
        let size = 128
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<size {
            for x in 0..<size {
                let red = ((x + y) / 64) % 2 == 0
                rep.setColor(red ? NSColor(deviceRed: 0.85, green: 0.05, blue: 0.08, alpha: 1)
                                 : NSColor(deviceRed: 0.97, green: 0.97, blue: 0.97, alpha: 1), atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }

    private func makeMaterial() -> SCNMaterial {
        if candyCane {
            let m = SCNMaterial()
            m.lightingModel = .lambert
            m.diffuse.contents = candyCaneImage
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(2, 2, 1)
            m.locksAmbientWithDiffuse = true
            return m
        }
        let hue = CGFloat.random(in: 0..<1)
        let color = NSColor(calibratedHue: hue,
                            saturation: CGFloat.random(in: 0.65...1),
                            brightness: CGFloat.random(in: 0.75...1), alpha: 1)
        let m = SCNMaterial()
        m.lightingModel = .phong
        m.diffuse.contents = color
        m.locksAmbientWithDiffuse = true
        m.specular.contents = NSColor(calibratedRed: 0.66, green: 0.99, blue: 1.0, alpha: 1)
        m.shininess = 0.35
        m.emission.contents = color.blended(withFraction: 0.75, of: .black)
        return m
    }

    // MARK: - Runs

    private func startNewRun() {
        pipesRoot.childNodes.forEach { $0.removeFromParentNode() }
        for i in occupied.indices { occupied[i] = false }
        pipes.removeAll()
        nodeCount = 0
        sceneFull = false
        runElapsed = 0
        runDuration = settings.resetInterval * Double.random(in: 0.85...1.15)

        switch settings.joints {
        case .elbow: ballChance = 0
        case .ball: ballChance = 1
        case .mixed: ballChance = 1.0 / 3.0
        case .cycle:
            ballChance = [0, 1, 1.0 / 3.0][cycleIndex % 3]
            cycleIndex += 1
        }

        // Like the example: 1 round in 20 is a candy-cane round, where teapots are far more common.
        candyCane = settings.teapots && Double.random(in: 0..<1) < 1.0 / 20.0
        teapotChance = settings.teapots ? (candyCane ? 1.0 / 20.0 : 1.0 / 200.0) : 0

        pickCameraView()
        for _ in 0..<settings.pipeCount {
            if let p = spawnPipe() { pipes.append(p) }
        }
    }

    private func pickCameraView() {
        cameraSpinner.simdOrientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        if Bool.random() {
            cameraRig.simdOrientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))  // head-on
        } else {
            let axes: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
            let angles: [Float] = [.pi / 2, -.pi / 2, .pi]
            let a = simd_quatf(angle: angles.randomElement()!, axis: axes.randomElement()!)
            let b = simd_quatf(angle: angles.randomElement()!, axis: axes.randomElement()!)
            cameraRig.simdOrientation = a * b
        }
    }

    // MARK: - Lattice

    private func index(_ c: Cell) -> Int? {
        let n = halfExtent
        guard abs(c.x) <= n, abs(c.y) <= n, abs(c.z) <= n else { return nil }
        return ((c.x + n) * side + (c.y + n)) * side + (c.z + n)
    }

    private func isFree(_ c: Cell) -> Bool {
        guard let i = index(c) else { return false }
        return !occupied[i]
    }

    private func occupy(_ c: Cell) {
        if let i = index(c) { occupied[i] = true }
    }

    private func freeDirections(from c: Cell) -> [Cell] {
        allDirections.filter { isFree(c + $0) }
    }

    // MARK: - Pipes

    private func addNode(_ geometry: SCNGeometry) -> SCNNode {
        let node = SCNNode(geometry: geometry)
        pipesRoot.addChildNode(node)
        nodeCount += 1
        return node
    }

    private func spawnPipe() -> Pipe? {
        let n = halfExtent
        var start: Cell?
        for _ in 0..<200 {
            let c = Cell(x: Int.random(in: -n...n), y: Int.random(in: -n...n), z: Int.random(in: -n...n))
            if isFree(c) && !freeDirections(from: c).isEmpty { start = c; break }
        }
        guard let cell = start else { sceneFull = true; return nil }

        let material = makeMaterial()
        func copy(_ g: SCNGeometry) -> SCNGeometry {
            let c = g.copy() as! SCNGeometry
            c.materials = [material]
            return c
        }
        let teapot = teapotTemplate.copy() as! SCNGeometry
        let teapotMaterial = material.copy() as! SCNMaterial
        teapotMaterial.isDoubleSided = true    // the lid gap and spout opening show back faces
        teapotMaterial.diffuse.contentsTransform = SCNMatrix4Identity
        teapot.materials = [teapotMaterial]
        let pipe = Pipe(cell: cell, cylinder: copy(cylinderTemplate), ball: copy(ballTemplate),
                        elbow: copy(elbowTemplate), teapot: teapot)
        occupy(cell)

        let cap = addNode(pipe.ball)
        cap.simdPosition = cell.vector

        let dir = freeDirections(from: cell).randomElement()!
        beginRun(pipe, dir: dir, from: cell.vector)
        return pipe
    }

    private func beginRun(_ pipe: Pipe, dir: Cell, from start: SIMD3<Float>) {
        pipe.dir = dir
        pipe.runStart = start
        occupy(pipe.cell + dir)
        let node = addNode(pipe.cylinder)
        node.simdOrientation = orientation(for: dir)
        node.isHidden = true
        pipe.runNode = node
    }

    private func orientation(for d: Cell) -> simd_quatf {
        if d.y == -1 { return simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0)) }
        return simd_quatf(from: SIMD3(0, 1, 0), to: d.vector)
    }

    private func layoutRun(_ pipe: Pipe, to end: SIMD3<Float>) {
        guard let node = pipe.runNode else { return }
        let d = pipe.dir.vector
        let length = simd_dot(end - pipe.runStart, d)
        if length < 0.002 {
            node.isHidden = true
        } else {
            node.isHidden = false
            node.simdPosition = pipe.runStart + d * (length / 2)
            node.simdScale = SIMD3(1, length, 1)
        }
    }

    /// Tip has reached the next cell: decide where to go from here.
    private func arrive(_ pipe: Pipe) {
        let here = pipe.cell + pipe.dir
        let incoming = pipe.dir
        layoutRun(pipe, to: here.vector)
        pipe.cell = here

        let options = freeDirections(from: here)
        guard !options.isEmpty else { pipe.alive = false; return }

        let next: Cell
        if options.contains(incoming) && Double.random(in: 0..<1) < 0.55 {
            next = incoming
        } else {
            next = options.randomElement()!
        }

        let p = here.vector
        if next == incoming {
            if candyCane {
                beginRun(pipe, dir: next, from: p)   // one node per cell so the stripes keep their scale
            } else {
                occupy(here + next)                  // keep extending the same straight run
            }
            return
        }

        if Double.random(in: 0..<1) < teapotChance {
            let teapot = addNode(pipe.teapot)
            teapot.simdPosition = p
            teapot.simdOrientation = randomRightAngleOrientation()
            beginRun(pipe, dir: next, from: p)
        } else if Double.random(in: 0..<1) < ballChance {
            let ball = addNode(pipe.ball)
            ball.simdPosition = p
            beginRun(pipe, dir: next, from: p)
        } else {
            let d1 = incoming.vector, d2 = next.vector
            layoutRun(pipe, to: p - d1 * elbowBend)
            let u = -d2, v = d1, w = simd_cross(u, v)
            let center = p - d1 * elbowBend + d2 * elbowBend
            let elbow = addNode(pipe.elbow)
            elbow.simdTransform = simd_float4x4(columns: (SIMD4(u, 0), SIMD4(v, 0), SIMD4(w, 0), SIMD4(center, 1)))
            beginRun(pipe, dir: next, from: p + d2 * elbowBend)
        }
    }

    private func randomRightAngleOrientation() -> simd_quatf {
        func turn(_ axis: SIMD3<Float>) -> simd_quatf {
            simd_quatf(angle: Float(Int.random(in: 0..<4)) * .pi / 2, axis: axis)
        }
        return turn(SIMD3(0, 0, 1)) * turn(SIMD3(0, 1, 0)) * turn(SIMD3(1, 0, 0))
    }

    private func stepPipes(_ dt: Double) {
        let advance = Float(dt * settings.speed)
        for pipe in pipes where pipe.alive {
            pipe.progress += advance
            var steps = 0
            while pipe.alive && pipe.progress >= 1 && steps < 8 {
                pipe.progress -= 1
                arrive(pipe)
                steps += 1
            }
            if pipe.alive {
                layoutRun(pipe, to: pipe.cell.vector + pipe.dir.vector * min(pipe.progress, 1))
            }
        }
        // Replace pipes that got boxed in, like the classic screensaver.
        for i in pipes.indices where !pipes[i].alive && !sceneFull {
            if let p = spawnPipe() { pipes[i] = p }
        }
        pipes.removeAll { !$0.alive }
        if pipes.isEmpty { sceneFull = true }
    }

    // MARK: - Dissolve

    private func beginDissolve() {
        phase = .dissolving
        dissolveElapsed = 0
        dissolveAdded = 0
        let size = overlay.size
        let block = max(16, ceil(sqrt(size.width * size.height / 3500)))
        let cols = Int(ceil(size.width / block)), rows = Int(ceil(size.height / block))
        dissolveBlocks.removeAll(keepingCapacity: true)
        for r in 0..<rows {
            for c in 0..<cols {
                dissolveBlocks.append(CGRect(x: CGFloat(c) * block, y: CGFloat(r) * block, width: block, height: block))
            }
        }
        dissolveBlocks.shuffle()
    }

    private func stepDissolve(_ dt: Double) {
        dissolveElapsed += dt
        let target = min(dissolveBlocks.count, Int(Double(dissolveBlocks.count) * dissolveElapsed / dissolveDuration))
        while dissolveAdded < target {
            let r = dissolveBlocks[dissolveAdded]
            let sprite = SKSpriteNode(color: .black, size: CGSize(width: r.width + 1, height: r.height + 1))
            sprite.position = CGPoint(x: r.midX, y: r.midY)
            overlay.addChild(sprite)
            dissolveAdded += 1
        }
        if dissolveElapsed >= dissolveDuration + 0.25 {
            startNewRun()
            overlay.removeAllChildren()
            phase = .growing
        }
    }

    // MARK: - SCNSceneRendererDelegate

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt: Double
        if let last = lastTime { dt = min(max(time - last, 0), 0.1) } else { dt = 0 }
        lastTime = time

        settingsLock.lock()
        let newSettings = pendingSettings
        pendingSettings = nil
        settingsLock.unlock()
        if let s = newSettings {
            settings = s
            overlay.removeAllChildren()
            phase = .growing
            startNewRun()
            return
        }

        if settings.rotateCamera {
            cameraSpinner.simdOrientation = simd_quatf(angle: Float(dt * 0.07), axis: SIMD3(0, 1, 0)) * cameraSpinner.simdOrientation
        }

        switch phase {
        case .growing:
            runElapsed += dt
            stepPipes(dt)
            if runElapsed >= runDuration || sceneFull || nodeCount > maxNodes {
                beginDissolve()
            }
        case .dissolving:
            stepDissolve(dt)
        }
    }
}
