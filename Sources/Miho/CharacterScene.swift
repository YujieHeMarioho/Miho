import AppKit
import SceneKit
import MihoCore
import simd

/// Reconstructed from the user's Miho reference: cyan plush, short ears, brown headphones,
/// and dark trapezoid sunglasses. Geometry and accessories remain genuinely three-dimensional.
final class CharacterScene {
    let scene = SCNScene()
    let camera = SCNNode()
    private let root = SCNNode(), turntable = SCNNode(), dancer = SCNNode(), skin = SCNNode()
    private let leftEar = SCNNode(), rightEar = SCNNode()
    private let headphones = SCNNode(), shades = SCNNode(), eyes = SCNNode(), hat = SCNNode(), shadow = SCNNode()
    private var appearance: CharacterAppearance?
    private let blue = CharacterScene.material(0x05B3E4,roughness: 0.95)
    private let leather = CharacterScene.material(0x844526,roughness: 0.68)
    private let cushion = CharacterScene.material(0x63351F,roughness: 0.88)
    private let frame = CharacterScene.material(0x081A21,roughness: 0.46)
    private let lens = CharacterScene.material(0x020B10,roughness: 0.55)

    init() {
        scene.background.contents = NSColor.clear
        scene.rootNode.addChildNode(root)
        root.addChildNode(turntable); turntable.position.y = 1.02
        turntable.name = "interactionRotation"
        turntable.addChildNode(dancer)
        dancer.addChildNode(skin)
        makeHeadphones(); makeShadow(); makeLighting()
        dancer.addChildNode(leftEar); dancer.addChildNode(rightEar)
        dancer.addChildNode(eyes); dancer.addChildNode(shades); dancer.addChildNode(hat)
        setAppearance(CharacterAppearance())
        apply(DancePose(),duration: 0)
    }
    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex>>16)&255)/255,green: CGFloat((hex>>8)&255)/255,blue: CGFloat(hex&255)/255,alpha: 1)
    }
    private static func material(_ hex: UInt32, roughness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = color(hex); m.roughness.contents = roughness; m.metalness.contents = 0
        return m
    }
    private func plush(_ parent: SCNNode, radii: SIMD3<Float>) {
        // Subpixel fur ribbons alias at desktop size. A smooth velvet surface gives
        // soft shading with a clean silhouette, at every viewing angle and scale.
        let sphere = SCNSphere(radius: 1); sphere.segmentCount = 96; sphere.firstMaterial = blue
        let core = SCNNode(geometry: sphere); core.scale = SCNVector3(CGFloat(radii.x),CGFloat(radii.y),CGFloat(radii.z))
        parent.addChildNode(core)
    }
    private func makeEars(_ style: EarStyle) {
        leftEar.childNodes.forEach { $0.removeFromParentNode() }; rightEar.childNodes.forEach { $0.removeFromParentNode() }
        leftEar.isHidden = style == .none; rightEar.isHidden = style == .none
        leftEar.position = SCNVector3(-0.16,0.76,-0.10)
        rightEar.position = SCNVector3(0.31,0.74,-0.12)
        if style == .none { return }
        if style == .cat {
            leftEar.position.x = -0.45; rightEar.position.x = 0.45
            for ear in [leftEar,rightEar] {
                let cone = SCNCone(topRadius: 0.035,bottomRadius: 0.24,height: 0.40)
                cone.radialSegmentCount = 64; cone.firstMaterial = blue
                let node = SCNNode(geometry: cone); node.position.y = 0.1; ear.addChildNode(node)
            }
            return
        }
        let left = SCNNode(); left.position.y = 0.20; leftEar.addChildNode(left)
        let right = SCNNode(); right.position.y = 0.14; rightEar.addChildNode(right)
        if style == .bunny {
            leftEar.position.x = -0.27; rightEar.position.x = 0.27
            left.position.y = 0.30; right.position.y = 0.30
            plush(left,radii: SIMD3(0.18,0.50,0.18)); plush(right,radii: SIMD3(0.18,0.50,0.18))
        } else {
            plush(left,radii: SIMD3(0.235,0.32,0.21)); plush(right,radii: SIMD3(0.225,0.275,0.20))
        }
    }
    @discardableResult private func box(_ parent: SCNNode, at position: SCNVector3, size: SCNVector3,
                                       radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let geometry = SCNBox(width: size.x,height: size.y,length: size.z,chamferRadius: radius)
        geometry.chamferSegmentCount = 8; geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry); node.position = position; parent.addChildNode(node)
        return node
    }
    private func tube(_ parent: SCNNode, points: [SCNVector3], radius: CGFloat, material: SCNMaterial) {
        // Cylinders meet in tiny round joints, so the curved band stays smooth at any angle.
        for i in 1..<points.count {
            let a = points[i-1], b = points[i]
            let delta = SIMD3<Float>(Float(b.x-a.x),Float(b.y-a.y),Float(b.z-a.z))
            let shape = SCNCylinder(radius: radius,height: CGFloat(simd_length(delta)))
            shape.radialSegmentCount = 12; shape.firstMaterial = material
            let node = SCNNode(geometry: shape)
            node.position = SCNVector3((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
            node.simdOrientation = simd_quatf(from: SIMD3(0,1,0),to: simd_normalize(delta)); parent.addChildNode(node)
            let joint = SCNSphere(radius: radius); joint.segmentCount = 12; joint.firstMaterial = material
            let round = SCNNode(geometry: joint); round.position = b; parent.addChildNode(round)
        }
    }
    private func makeHeadphones() {
        headphones.name = "headphones"
        var points: [SCNVector3] = []
        for step in 0...48 {
            let angle = Double(step)/48 * .pi
            points.append(SCNVector3(cos(angle)*0.97,0.01+sin(angle)*0.95,0.13))
        }
        tube(headphones,points: points,radius: 0.034,material: leather)
        for side in [-1.0,1.0] {
            box(headphones,at: SCNVector3(side*0.91,-0.08,0.04),size: SCNVector3(0.14,0.44,0.31),radius: 0.06,material: cushion)
            box(headphones,at: SCNVector3(side*1.015,-0.08,0.06),size: SCNVector3(0.24,0.55,0.34),radius: 0.095,material: leather)
            // A soft raised front seam reads as leather, without adding a different silhouette.
            box(headphones,at: SCNVector3(side*1.015,-0.08,0.218),size: SCNVector3(0.195,0.46,0.035),radius: 0.06,material: leather)
        }
        // Flatten only this static assembly; the whole headset remains independently animated.
        let combined = headphones.flattenedClone()
        headphones.childNodes.forEach { $0.removeFromParentNode() }
        combined.childNodes.forEach { headphones.addChildNode($0) }
        if let geometry = combined.geometry { headphones.geometry = geometry }
        dancer.addChildNode(headphones)
    }
    private func makeSunglasses(_ style: GlassesStyle, depth: Double) {
        shades.childNodes.forEach { $0.removeFromParentNode() }
        shades.isHidden = style == .none
        shades.position = SCNVector3(0,0.06,depth)
        if style == .none { return }
        if style == .round {
            for side in [-1.0,1.0] {
                let ring = SCNTorus(ringRadius: 0.245,pipeRadius: 0.025)
                ring.ringSegmentCount = 72; ring.pipeSegmentCount = 16; ring.firstMaterial = frame
                let node = SCNNode(geometry: ring); node.eulerAngles.x = .pi/2
                node.position = SCNVector3(side*0.31,0.05,0); shades.addChildNode(node)
                tube(shades,points: [SCNVector3(side*0.55,0.11,0),SCNVector3(side*0.79,0.11,-0.18),SCNVector3(side*0.82,0.1,-0.48)],radius: 0.023,material: frame)
            }
            box(shades,at: SCNVector3(0,0.10,0),size: SCNVector3(0.17,0.035,0.04),radius: 0.014,material: frame)
            return
        }
        let path = NSBezierPath()
        path.flatness = 0.001
        path.move(to: NSPoint(x: -0.285,y: 0.245))
        path.line(to: NSPoint(x: 0.285,y: 0.245))
        path.curve(to: NSPoint(x: 0.345,y: 0.165),controlPoint1: NSPoint(x: 0.342,y: 0.245),controlPoint2: NSPoint(x: 0.366,y: 0.208))
        path.line(to: NSPoint(x: 0.25,y: -0.18))
        path.curve(to: NSPoint(x: 0.182,y: -0.235),controlPoint1: NSPoint(x: 0.238,y: -0.22),controlPoint2: NSPoint(x: 0.226,y: -0.235))
        path.line(to: NSPoint(x: -0.20,y: -0.235))
        path.curve(to: NSPoint(x: -0.273,y: -0.18),controlPoint1: NSPoint(x: -0.245,y: -0.235),controlPoint2: NSPoint(x: -0.262,y: -0.22))
        path.line(to: NSPoint(x: -0.345,y: 0.16))
        path.curve(to: NSPoint(x: -0.285,y: 0.245),controlPoint1: NSPoint(x: -0.36,y: 0.211),controlPoint2: NSPoint(x: -0.34,y: 0.245))
        path.close()
        for side in [-1.0,1.0] {
            let geometry = SCNShape(path: path,extrusionDepth: 0.047)
            geometry.chamferRadius = 0.014; geometry.firstMaterial = frame
            let rim = SCNNode(geometry: geometry); rim.position.x = CGFloat(side*0.37)
            rim.eulerAngles.y = CGFloat(side*0.09); shades.addChildNode(rim)
            let glass = SCNShape(path: path,extrusionDepth: 0.016)
            glass.chamferRadius = 0.009; glass.firstMaterial = lens
            let inset = SCNNode(geometry: glass); inset.scale = SCNVector3(0.92,0.90,1)
            inset.position.z = 0.033; rim.addChildNode(inset)
            tube(shades,points: [SCNVector3(side*0.69,0.15,0),SCNVector3(side*0.79,0.13,-0.16),SCNVector3(side*0.82,0.10,-0.43)],radius: 0.026,material: frame)
        }
        box(shades,at: SCNVector3(0,0.12,0.005),size: SCNVector3(0.15,0.047,0.045),radius: 0.018,material: frame)
    }
    private func makeEyes(_ style: EyeStyle,depth: Double) {
        eyes.childNodes.forEach { $0.removeFromParentNode() }
        eyes.position = SCNVector3(0,0.12,depth)
        let ink = Self.material(0x102330,roughness: 0.5)
        for side in [-1.0,1.0] {
            let center = side*0.28
            if style == .dot || (style == .wink && side < 0) {
                let sphere = SCNSphere(radius: 0.09); sphere.segmentCount = 48; sphere.firstMaterial = ink
                let node = SCNNode(geometry: sphere); node.scale = SCNVector3(0.8,1,0.4)
                node.position = SCNVector3(center,0,0); eyes.addChildNode(node)
            } else {
                let arc = (0...16).map { i -> SCNVector3 in
                    let t = Double(i)/16
                    let height = style == .happy ? sin(t * .pi)*0.065 : -sin(t * .pi)*0.028
                    return SCNVector3(center+(t-0.5)*0.17,height,0)
                }
                tube(eyes,points: arc,radius: 0.021,material: ink)
            }
        }
    }
    private func makeHat(_ accessory: HeadAccessory) {
        hat.childNodes.forEach { $0.removeFromParentNode() }
        headphones.isHidden = accessory != .headphones
        hat.isHidden = accessory != .beanie && accessory != .crown
        if accessory == .beanie {
            let cap = SCNSphere(radius: 0.65); cap.segmentCount = 72; cap.firstMaterial = leather
            let node = SCNNode(geometry: cap); node.scale = SCNVector3(1,0.55,1)
            node.position.y = 0.86; hat.addChildNode(node)
            let rim = SCNTorus(ringRadius: 0.55,pipeRadius: 0.065)
            rim.ringSegmentCount = 72; rim.firstMaterial = leather
            let trim = SCNNode(geometry: rim); trim.position.y = 0.80; hat.addChildNode(trim)
            let pom = SCNSphere(radius: 0.12); pom.segmentCount = 48; pom.firstMaterial = leather
            let tip = SCNNode(geometry: pom); tip.position.y = 1.23; hat.addChildNode(tip)
        } else if accessory == .crown {
            let ring = SCNTorus(ringRadius: 0.43,pipeRadius: 0.055)
            ring.ringSegmentCount = 72; ring.firstMaterial = leather
            let base = SCNNode(geometry: ring); base.position.y = 0.87; hat.addChildNode(base)
            for i in 0..<7 {
                let t = Double(i)/7*2 * .pi
                let spike = SCNCone(topRadius: 0.02,bottomRadius: 0.11,height: 0.31)
                spike.radialSegmentCount = 32; spike.firstMaterial = leather
                let node = SCNNode(geometry: spike); node.position = SCNVector3(cos(t)*0.41,1.04,sin(t)*0.41)
                hat.addChildNode(node)
            }
        }
    }
    func setAppearance(_ next: CharacterAppearance) {
        guard next != appearance else { return }
        let old = appearance
        blue.diffuse.contents = Self.color(next.bodyColor)
        blue.roughness.contents = next.surface == .velvet ? 0.94 : 0.32
        leather.diffuse.contents = Self.color(next.accessoryColor)
        cushion.diffuse.contents = Self.color(next.accessoryColor).blended(withFraction: 0.25,of: .black)
        frame.diffuse.contents = Self.color(next.glassesColor)
        if old?.shape != next.shape {
            skin.childNodes.forEach { $0.removeFromParentNode() }
            let r = next.shape.radii
            if next.shape == .squircle {
                let node = box(skin,at: SCNVector3Zero,size: SCNVector3(r.0*2,r.1*2,r.2*2),radius: 0.50,material: blue)
                (node.geometry as? SCNBox)?.chamferSegmentCount = 24
            } else { plush(skin,radii: SIMD3(Float(r.0),Float(r.1),Float(r.2))) }
            skin.childNodes.first?.name = "bodySurface"
        }
        if old?.ears != next.ears { makeEars(next.ears) }
        let depth = next.shape == .squircle ? next.shape.radii.2+0.04 : next.shape.radii.2*0.93
        if old?.eyes != next.eyes || old?.shape != next.shape { makeEyes(next.eyes,depth: depth) }
        if old?.glasses != next.glasses || old?.shape != next.shape { makeSunglasses(next.glasses,depth: depth+0.03) }
        if old?.accessory != next.accessory { makeHat(next.accessory) }
        eyes.name = "eyes"; shades.name = "glasses"; hat.name = "headAccessory"
        appearance = next
    }
    private func makeShadow() {
        let image = NSImage(size: NSSize(width: 256,height: 256),flipped: false) { rect in
            NSGradient(starting: NSColor(white: 0.12,alpha: 0.18),ending: .clear)?.draw(in: NSBezierPath(ovalIn: rect),relativeCenterPosition: .zero)
            return true
        }
        let material = SCNMaterial(); material.lightingModel = .constant; material.diffuse.contents = image
        material.isDoubleSided = true; material.writesToDepthBuffer = false
        let plane = SCNPlane(width: 1.85,height: 1.1); plane.firstMaterial = material
        shadow.geometry = plane; shadow.eulerAngles.x = -.pi/2; shadow.position = SCNVector3(0,0.025,0)
        scene.rootNode.addChildNode(shadow)
    }
    private func makeLighting() {
        camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true
        // Leave space for audio-driven growth and side motion without clipping
        // the headphones at the desktop panel's portrait aspect ratio.
        camera.camera?.orthographicScale = 1.75
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 30
        camera.camera?.wantsHDR = true; camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = -0.10
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0
        camera.camera?.screenSpaceAmbientOcclusionRadius = 0.04
        camera.position = SCNVector3(0,1.75,7); camera.look(at: SCNVector3(0,1.25,0))
        scene.rootNode.addChildNode(camera)
        func light(_ type: SCNLight.LightType, _ position: SCNVector3, _ intensity: CGFloat, _ color: UInt32) {
            let node = SCNNode(); node.light = SCNLight(); node.light?.type = type
            node.light?.intensity = intensity; node.light?.color = Self.color(color)
            node.position = position; node.look(at: SCNVector3(0,1,0)); scene.rootNode.addChildNode(node)
        }
        light(.ambient,SCNVector3(0,0,0),180,0xFFFFFF)
        light(.directional,SCNVector3(-3,5,5),720,0xFFFFFF)
        light(.directional,SCNVector3(4,2,3),180,0xE6F6FF)
        light(.directional,SCNVector3(2,4,-3),400,0xE0F7FF)
        scene.lightingEnvironment.contents = NSImage(size: NSSize(width: 32,height: 16),flipped: false) { rect in
            NSGradient(colors: [.white,Self.color(0xC9E3EF)])?.draw(in: rect,angle: 90); return true
        }
        scene.lightingEnvironment.intensity = 0.35
    }
    func apply(_ p: DancePose, duration: Double) {
        SCNTransaction.begin(); SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
        root.position = SCNVector3(p.x,p.y,p.z)
        let scale = p.scale.isFinite ? min(1.25,max(0.85,p.scale)) : 1
        dancer.scale = SCNVector3(scale,scale,scale)
        dancer.eulerAngles = SCNVector3(p.body.x,p.body.y,p.body.z)
        skin.scale = SCNVector3(1/sqrt(p.squash),p.squash,1/sqrt(p.squash))
        leftEar.eulerAngles = SCNVector3(p.leftEar.x,p.leftEar.y,-0.13+p.leftEar.z)
        rightEar.eulerAngles = SCNVector3(p.rightEar.x,p.rightEar.y,0.13+p.rightEar.z)
        leftEar.position.y = CGFloat(0.76+(p.squash-1)*0.7)
        rightEar.position.y = CGFloat(0.74+(p.squash-1)*0.7)
        headphones.eulerAngles = SCNVector3(p.head.x*0.35,p.head.y*0.35,p.head.z*0.55)
        headphones.position.y = CGFloat((p.squash-1)*0.3+p.accessoryBounce)
        shades.eulerAngles = SCNVector3(p.head.x*0.22,p.head.y*0.20,p.head.z*0.35)
        shades.position.y = CGFloat(0.06+p.accessoryBounce*0.3)
        shadow.position.x = CGFloat(p.x*0.75)
        shadow.scale = SCNVector3(max(0.6,1-p.y*0.65),max(0.6,1-p.y*0.65),1)
        shadow.opacity = CGFloat(max(0.3,1-p.y*1.4))
        SCNTransaction.commit()
    }
    func setInteractionRotation(_ rotation: Rotation3, duration: Double) {
        SCNTransaction.begin(); SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
        // Quaternion composition keeps a full spin continuous across the ±π boundary.
        turntable.simdOrientation = simd_quatf(angle: Float(rotation.y),axis: SIMD3(0,1,0)) *
            simd_quatf(angle: Float(rotation.x),axis: SIMD3(1,0,0))
        SCNTransaction.commit()
    }
}
