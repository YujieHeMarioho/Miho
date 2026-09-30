import SceneKit
import simd

/// Crossed, tapered ribbons give the silhouette real short fur rather than a flat texture.
/// One mesh per surface keeps strand count independent of draw-call count.
enum FurGeometry {
    static func ellipsoid(radii: SIMD3<Float>, strands: Int, seed: UInt64) -> SCNGeometry {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], colors: [Float] = [], indices: [Int32] = []
        vertices.reserveCapacity(strands*12); normals.reserveCapacity(strands*12)
        colors.reserveCapacity(strands*48); indices.reserveCapacity(strands*24)
        var state = seed
        func random() -> Float {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return Float((z ^ (z >> 31)) >> 40)/Float(1 << 24)
        }
        func append(_ v: SIMD3<Float>, normal: SIMD3<Float>, color: SIMD3<Float>) {
            vertices.append(SCNVector3(CGFloat(v.x),CGFloat(v.y),CGFloat(v.z)))
            normals.append(SCNVector3(CGFloat(normal.x),CGFloat(normal.y),CGFloat(normal.z)))
            colors.append(contentsOf: [color.x,color.y,color.z,1])
        }
        for i in 0..<strands {
            let y = 1-2*(Float(i)+0.5)/Float(strands)
            let angle = Float(i)*2.39996323 + random()*0.25
            let radius = sqrt(max(0,1-y*y))
            let unit = SIMD3<Float>(cos(angle)*radius,y,sin(angle)*radius)
            let normal = simd_normalize(unit/radii)
            let start = unit*radii + normal*0.001
            let reference: SIMD3<Float> = abs(normal.y) < 0.92 ? SIMD3(0,1,0) : SIMD3(1,0,0)
            let tangent = simd_normalize(simd_cross(normal,reference))
            let bitangent = simd_cross(normal,tangent)
            let length = 0.012 + random()*0.017
            let lean = tangent*(random()-0.5)*0.012 + bitangent*(random()-0.5)*0.010
            let middle = start + normal*length*0.55 + lean*0.3
            let end = start + normal*length + lean
            let width = 0.0017 + random()*0.0008
            let shade = 0.93 + random()*0.13
            let color = SIMD3<Float>(0.018,0.71,0.91)*shade
            for across in [tangent,bitangent] {
                let base = Int32(vertices.count)
                for (point,w) in [(start,width),(middle,width*0.63),(end,Float(0.00015))] {
                    append(point-across*w,normal: normal,color: color)
                    append(point+across*w,normal: normal,color: color)
                }
                indices.append(contentsOf: [base,base+1,base+2,base+1,base+3,base+2,base+2,base+3,base+4,base+3,base+5,base+4])
            }
        }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),SCNGeometrySource(normals: normals),
            SCNGeometrySource(data: colorData,semantic: .color,vectorCount: vertices.count,usesFloatComponents: true,
                              componentsPerVector: 4,bytesPerComponent: 4,dataOffset: 0,dataStride: 16)],
            elements: [SCNGeometryElement(indices: indices,primitiveType: .triangles)])
        let material = SCNMaterial(); material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor.white
        material.roughness.contents = 0.96; material.metalness.contents = 0
        material.isDoubleSided = true
        geometry.firstMaterial = material
        return geometry
    }
}
