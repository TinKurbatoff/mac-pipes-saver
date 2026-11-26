import SceneKit
import simd

/// Tessellates the Utah teapot's 32 bicubic Bezier patches into a SceneKit mesh.
enum Teapot {
    /// - Parameters:
    ///   - size: half-height of the result; the teapot spans -size...size vertically (Y up).
    ///   - segments: subdivisions per patch edge.
    static func makeGeometry(size: Float, segments: Int = 8) -> SCNGeometry {
        let data = UtahTeapotData.vertices
        let patchIndices = UtahTeapotData.patches
        let maxHeight: Float = 3.15            // Blinn-scaled teapot height in the source data
        let half = maxHeight / 2
        let scale = size / half
        let lidPatches = 20..<28
        let lidStretch: Float = 1.077         // makes the lid fit snugly (as the example does)

        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [Int32] = []

        func bernstein(_ t: Float) -> (b: SIMD4<Float>, d: SIMD4<Float>) {
            let u = 1 - t
            return (SIMD4(u * u * u, 3 * t * u * u, 3 * t * t * u, t * t * t),
                    SIMD4(-3 * u * u, 3 * u * u - 6 * t * u, 6 * t * u - 3 * t * t, 3 * t * t))
        }

        let row = segments + 1
        for patch in 0..<32 {
            // Control points P[r][c] in source (Z-up) space.
            var cp = [SIMD3<Float>](repeating: .zero, count: 16)
            for k in 0..<16 {
                let vi = patchIndices[patch * 16 + k] * 3
                var p = SIMD3(data[vi], data[vi + 1], data[vi + 2])
                if lidPatches.contains(patch) { p.x *= lidStretch; p.y *= lidStretch }
                cp[k] = p
            }

            let base = Int32(positions.count)
            for si in 0...segments {
                let s = Float(si) / Float(segments)
                let bs = bernstein(s)
                for ti in 0...segments {
                    let t = Float(ti) / Float(segments)
                    let bt = bernstein(t)
                    var p = SIMD3<Float>.zero, ds = SIMD3<Float>.zero, dt = SIMD3<Float>.zero
                    for r in 0..<4 {
                        for c in 0..<4 {
                            let q = cp[r * 4 + c]
                            p += bs.b[r] * bt.b[c] * q
                            ds += bs.d[r] * bt.b[c] * q
                            dt += bs.b[r] * bt.d[c] * q
                        }
                    }
                    var n: SIMD3<Float>
                    if p.x == 0 && p.y == 0 {
                        // Cusp at the top of the lid / centre of the bottom.
                        n = SIMD3(0, p.z > half ? 1 : -1, 0)
                    } else {
                        let raw = simd_normalize(simd_cross(dt, ds))
                        n = SIMD3(raw.x, raw.z, -raw.y)          // Z-up -> Y-up
                    }
                    positions.append(SCNVector3(p.x * scale, (p.z - half) * scale, -p.y * scale))
                    normals.append(SCNVector3(n.x, n.y, n.z))
                    uvs.append(CGPoint(x: CGFloat(1 - t), y: CGFloat(1 - s)))
                }
            }

            func same(_ a: Int32, _ b: Int32) -> Bool {
                let p = positions[Int(a)], q = positions[Int(b)]
                return abs(p.x - q.x) < 1e-6 && abs(p.y - q.y) < 1e-6 && abs(p.z - q.z) < 1e-6
            }
            func emit(_ a: Int32, _ b: Int32, _ c: Int32) {
                if !same(a, b) && !same(a, c) && !same(b, c) { indices += [a, b, c] }
            }
            for si in 0..<segments {
                for ti in 0..<segments {
                    let v1 = base + Int32(si * row + ti)
                    let v2 = v1 + 1
                    let v3 = v2 + Int32(row)
                    let v4 = v1 + Int32(row)
                    emit(v1, v2, v3)
                    emit(v1, v3, v4)
                }
            }
        }

        return SCNGeometry(sources: [SCNGeometrySource(vertices: positions),
                                     SCNGeometrySource(normals: normals),
                                     SCNGeometrySource(textureCoordinates: uvs)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
}
