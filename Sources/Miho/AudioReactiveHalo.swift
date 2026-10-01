import SceneKit
import MihoCore

/// Expanded copies of the actual mesh create a feathered silhouette. Opaque
/// character geometry draws over their interiors; no surrounding circle exists.
final class AudioReactiveHalo {
    private struct Layer {
        var root: SCNNode
        var transforms: [(SCNNode,SCNNode)]
        var material: SCNMaterial
        var opacity: Double
    }
    private var layers: [Layer] = []
    private var frame = SoundFieldFrame()
    private var center = SCNVector3(0,1.02,0)

    func rebuild(character: SCNNode,parent: SCNNode) {
        layers.forEach { $0.root.removeFromParentNode() }; layers.removeAll()
        // Closely spaced shells with a Gaussian falloff avoid visible contour
        // bands at desktop size, while leaving a small, softly fading wave.
        for index in 0..<8 {
            let width = 0.30+Double(index)*0.18
            let opacity = 0.28*exp(-width*width/1.1)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = NSColor(srgbRed: 0.35,green: 0.83,blue: 0.98,alpha: 1)
            material.cullMode = .front
            material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = true
            material.blendMode = .alpha
            material.shaderModifiers = [.geometry: Self.displacement,.fragment: Self.tint]
            material.setValue(width,forKey: "haloLayer")
            let clone = character.clone()
            var transforms: [(SCNNode,SCNNode)] = []
            func pair(_ source: SCNNode,_ target: SCNNode) {
                transforms.append((source,target))
                target.name = nil; target.castsShadow = false; target.renderingOrder = -20+index
                if let original = target.geometry, let geometry = original.copy() as? SCNGeometry {
                    geometry.materials = Array(repeating: material,count: max(1,original.materials.count))
                    target.geometry = geometry
                }
                for (a,b) in zip(source.childNodes,target.childNodes) { pair(a,b) }
            }
            pair(character,clone)
            clone.name = "audioHalo\(index)"
            parent.addChildNode(clone)
            layers.append(.init(root: clone,transforms: transforms,material: material,opacity: opacity))
        }
        update(frame,center: center)
        synchronize()
    }
    func synchronize() {
        for layer in layers {
            for (source,target) in layer.transforms {
                target.simdTransform = source.simdTransform
                target.isHidden = source.isHidden
            }
        }
    }
    func update(_ frame: SoundFieldFrame,center: SCNVector3) {
        self.frame = frame; self.center = center
        for layer in layers {
            let material = layer.material
            material.setValue(NSValue(scnVector3: center),forKey: "haloCenter")
            for group in 0..<6 {
                let values = (0..<4).map { offset -> CGFloat in
                    let index = group*4+offset
                    let value = index < frame.spectrum.count ? frame.spectrum[index] : 0
                    return CGFloat(value.isFinite ? min(1,max(0,value)) : 0)
                }
                material.setValue(NSValue(scnVector4: SCNVector4(values[0],values[1],values[2],values[3])),forKey: "haloBands\(group)")
            }
            material.setValue(frame.bass,forKey: "haloBass")
            material.setValue(frame.transient,forKey: "haloTransient")
            material.setValue(layer.opacity*(0.18+frame.drive*0.82),forKey: "haloOpacity")
        }
    }
    private static let displacement = """
    #pragma arguments
    float4 haloBands0;
    float4 haloBands1;
    float4 haloBands2;
    float4 haloBands3;
    float4 haloBands4;
    float4 haloBands5;
    float3 haloCenter;
    float haloLayer;
    float haloBass;
    float haloTransient;
    #pragma body
    float3 p = (scn_node.modelViewTransform * _geometry.position).xyz;
    float3 c = (scn_frame.viewTransform * float4(haloCenter,1.0)).xyz;
    float angle = atan2(p.y-c.y,p.x-c.x);
    float band = fract((angle+3.14159265)/6.2831853)*24.0;
    int i = int(floor(band));
    float values[24] = {haloBands0.x,haloBands0.y,haloBands0.z,haloBands0.w,
        haloBands1.x,haloBands1.y,haloBands1.z,haloBands1.w,
        haloBands2.x,haloBands2.y,haloBands2.z,haloBands2.w,
        haloBands3.x,haloBands3.y,haloBands3.z,haloBands3.w,
        haloBands4.x,haloBands4.y,haloBands4.z,haloBands4.w,
        haloBands5.x,haloBands5.y,haloBands5.z,haloBands5.w};
    float level = mix(values[i],values[(i+1)%24],smoothstep(0.0,1.0,fract(band)));
    float lowArc = 1.0-smoothstep(4.0,9.0,min(band,24.0-band));
    float width = 0.012+level*0.16+lowArc*(haloBass*0.055+haloTransient*0.05);
    _geometry.position.xyz += _geometry.normal * width * haloLayer;
    """
    private static let tint = """
    #pragma arguments
    float3 haloCenter;
    float haloOpacity;
    #pragma transparent
    #pragma body
    float3 c = (scn_frame.viewTransform * float4(haloCenter,1.0)).xyz;
    float angle = atan2(_surface.position.y-c.y,_surface.position.x-c.x);
    float colour = 0.5+0.5*sin(angle);
    float edge = abs(dot(normalize(_surface.geometryNormal),normalize(_surface.view)));
    _output.color.a = haloOpacity*smoothstep(0.0,0.6,edge);
    // SceneKit converts linear RGB to the display colour space after this
    // modifier. Linearize the premultiplied display colour to keep low-alpha
    // edges tinted rather than overbright white after that conversion.
    float3 tint = mix(float3(0.25,0.87,0.98),float3(0.75,0.42,0.98),colour)*_output.color.a;
    _output.color.rgb = select(tint/12.92,pow((tint+0.055)/1.055,float3(2.4)),tint>0.04045);
    """
}
