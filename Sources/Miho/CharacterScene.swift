import AppKit
import SceneKit
import MihoCore

/// An original, articulated little sprout dancer. All geometry is local and procedural.
/// Keeping the rig alive avoids rebuilding meshes or loading assets on audio callbacks.
final class CharacterScene {
    let scene = SCNScene()
    let camera = SCNNode()
    private let root = SCNNode(), torso = SCNNode(), head = SCNNode()
    private let leftArm = SCNNode(), rightArm = SCNNode(), leftElbow = SCNNode(), rightElbow = SCNNode()
    private let leftLeg = SCNNode(), rightLeg = SCNNode(), leftKnee = SCNNode(), rightKnee = SCNNode()
    private let leftFoot = SCNNode(), rightFoot = SCNNode()
    private let leftEar = SCNNode(), rightEar = SCNNode(), sprout = SCNNode()
    private let leftEye = SCNNode(), rightEye = SCNNode(), leftPupil = SCNNode(), rightPupil = SCNNode()
    private let mouth = SCNNode(), tongue = SCNNode(), shadow = SCNNode()
    private let cream = CharacterScene.material(0xFFF0D7, roughness: 0.50)
    private let mint = CharacterScene.material(0x65BFB1, roughness: 0.70)
    private let mintDark = CharacterScene.material(0x32978A, roughness: 0.60)
    private let pink = CharacterScene.material(0xF4A298, roughness: 0.70)
    private let coral = CharacterScene.material(0xEC826E, roughness: 0.55)
    private let white = CharacterScene.material(0xFFF9EE, roughness: 0.43)
    private let ink = CharacterScene.material(0x38292E, roughness: 0.23)

    init() {
        scene.background.contents = NSColor.clear
        scene.rootNode.addChildNode(root)
        root.addChildNode(torso); torso.position.y = 0.85
        makeBody(); makeHead(); makeArms(); makeLegs(); makeShadow(); makeLighting()
        apply(DancePose(), duration: 0)
    }

    private static func material(_ hex: UInt32, roughness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color(hex)
        m.roughness.contents = roughness
        m.metalness.contents = 0
        return m
    }
    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255,
                blue: CGFloat(hex & 255)/255, alpha: 1)
    }
    @discardableResult private func ball(_ parent: SCNNode, _ position: SCNVector3, _ scale: SCNVector3,
                                        _ material: SCNMaterial) -> SCNNode {
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 40
        sphere.firstMaterial = material
        let node = SCNNode(geometry: sphere)
        node.position = position; node.scale = scale; parent.addChildNode(node)
        return node
    }
    private func roundedBox(_ parent: SCNNode, at position: SCNVector3, size: SCNVector3,
                            radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let shape = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: radius)
        shape.chamferSegmentCount = 6
        shape.firstMaterial = material
        let node = SCNNode(geometry: shape); node.position = position; parent.addChildNode(node)
        return node
    }
    private func curve(_ parent: SCNNode, points: [SCNVector3], radius: CGFloat, material: SCNMaterial) {
        for i in 1..<points.count {
            let a = points[i-1], b = points[i]
            let dx = b.x-a.x, dy = b.y-a.y, dz = b.z-a.z
            let length = sqrt(dx*dx+dy*dy+dz*dz)
            let shape = SCNCylinder(radius: radius, height: CGFloat(length))
            shape.radialSegmentCount = 10; shape.firstMaterial = material
            let node = SCNNode(geometry: shape)
            node.position = SCNVector3((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: SIMD3<Float>(Float(dx/length),Float(dy/length),Float(dz/length)))
            parent.addChildNode(node)
            ball(parent,b,SCNVector3(radius,radius,radius),material)
        }
    }
    private func makeBody() {
        ball(torso,SCNVector3(0,0,0),SCNVector3(0.39,0.43,0.30),mint)
        // Rounded hood around the neck, ribbed waistband and a real front pouch.
        let collar = SCNTorus(ringRadius: 0.25, pipeRadius: 0.055)
        collar.firstMaterial = mintDark
        let collarNode = SCNNode(geometry: collar); collarNode.position = SCNVector3(0,0.30,0.04)
        torso.addChildNode(collarNode)
        ball(torso,SCNVector3(0,-0.31,0),SCNVector3(0.31,0.10,0.25),mintDark)
        _ = roundedBox(torso,at: SCNVector3(0,-0.12,0.265),size: SCNVector3(0.34,0.17,0.06),radius: 0.06,material: mintDark)
        for x in [-0.08,0.08] {
            curve(torso,points: [SCNVector3(x,0.30,0.24),SCNVector3(x*0.95,0.17,0.31),SCNVector3(x*1.05,0.11,0.31)],radius: 0.010,material: white)
            ball(torso,SCNVector3(x*1.05,0.10,0.31),SCNVector3(0.016,0.024,0.016),cream)
        }
        // A tiny sprout badge is a repeated signature, not a texture stuck on the model.
        ball(torso,SCNVector3(0.22,0.11,0.265),SCNVector3(0.060,0.057,0.025),cream)
        ball(torso,SCNVector3(0.205,0.12,0.29),SCNVector3(0.022,0.012,0.010),mintDark).eulerAngles.z = -0.4
        ball(torso,SCNVector3(0.232,0.13,0.29),SCNVector3(0.022,0.012,0.010),mintDark).eulerAngles.z = 0.4
    }
    private func makeHead() {
        head.position = SCNVector3(0,0.78,0.035); torso.addChildNode(head)
        ball(head,SCNVector3(0,0,0),SCNVector3(0.59,0.52,0.45),cream)
        // Soft asymmetrical ears and peach inner surfaces give a readable silhouette.
        for (ear,side) in [(leftEar,-1.0),(rightEar,1.0)] {
            head.addChildNode(ear); ear.position = SCNVector3(side*0.40,0.39,-0.03)
            ear.eulerAngles.z = CGFloat(-side*0.30)
            ball(ear,SCNVector3(0,0.17,0),SCNVector3(0.17,0.28,0.12),cream)
            ball(ear,SCNVector3(0,0.18,0.090),SCNVector3(0.095,0.19,0.033),pink)
        }
        sprout.position = SCNVector3(0.02,0.49,-0.03); head.addChildNode(sprout)
        curve(sprout,points: [SCNVector3(0,0,0),SCNVector3(0.015,0.12,0),SCNVector3(0.04,0.19,0)],radius: 0.022,material: mintDark)
        ball(sprout,SCNVector3(-0.06,0.14,0),SCNVector3(0.12,0.06,0.05),mint).eulerAngles.z = -0.40
        ball(sprout,SCNVector3(0.12,0.21,0),SCNVector3(0.14,0.065,0.055),mint).eulerAngles.z = 0.45
        for (eye,pupil,side) in [(leftEye,leftPupil,-1.0),(rightEye,rightPupil,1.0)] {
            eye.position = SCNVector3(side*0.22,0.045,0.401); head.addChildNode(eye)
            ball(eye,SCNVector3(0,0,0),SCNVector3(0.145,0.172,0.075),white)
            pupil.position = SCNVector3(-side*0.01,-0.008,0.058); eye.addChildNode(pupil)
            ball(pupil,SCNVector3(0,0,0),SCNVector3(0.103,0.135,0.054),ink)
            let iris = Self.material(0x8E5840,roughness: 0.26)
            ball(pupil,SCNVector3(0,-0.035,0.035),SCNVector3(0.073,0.060,0.017),iris)
            ball(pupil,SCNVector3(0,0.002,0.050),SCNVector3(0.064,0.095,0.020),ink)
            let glint = Self.material(0xFFFFFF,roughness: 0.1)
            glint.emission.contents = NSColor(white: 0.8,alpha: 1)
            ball(pupil,SCNVector3(-0.037,0.055,0.065),SCNVector3(0.027,0.031,0.012),glint)
            ball(pupil,SCNVector3(0.033,-0.025,0.061),SCNVector3(0.011,0.012,0.006),glint)
            curve(head,points: [SCNVector3(side*0.34,0.265,0.345),SCNVector3(side*0.25,0.286,0.380),SCNVector3(side*0.16,0.272,0.385)],radius: 0.014,material: ink)
            ball(head,SCNVector3(side*0.375,-0.11,0.354),SCNVector3(0.090,0.053,0.025),pink)
        }
        ball(head,SCNVector3(-0.060,-0.15,0.418),SCNVector3(0.10,0.067,0.045),white)
        ball(head,SCNVector3(0.060,-0.15,0.418),SCNVector3(0.10,0.067,0.045),white)
        ball(head,SCNVector3(0,-0.107,0.47),SCNVector3(0.043,0.029,0.026),ink)
        mouth.position = SCNVector3(0,-0.227,0.416); head.addChildNode(mouth)
        ball(mouth,SCNVector3(0,0,0),SCNVector3(0.076,0.045,0.023),ink)
        mouth.addChildNode(tongue)
        ball(tongue,SCNVector3(0,-0.015,0.021),SCNVector3(0.041,0.018,0.007),coral)
    }
    private func makeArms() {
        for (arm,elbow,side) in [(leftArm,leftElbow,-1.0),(rightArm,rightElbow,1.0)] {
            torso.addChildNode(arm); arm.position = SCNVector3(side*0.34,0.18,0)
            ball(arm,SCNVector3(0,-0.12,0),SCNVector3(0.12,0.18,0.13),mint)
            arm.addChildNode(elbow); elbow.position = SCNVector3(0,-0.25,0)
            ball(elbow,SCNVector3(0,-0.06,0),SCNVector3(0.093,0.13,0.10),mint)
            ball(elbow,SCNVector3(0,-0.15,0.005),SCNVector3(0.10,0.065,0.10),mintDark)
            ball(elbow,SCNVector3(0,-0.225,0.02),SCNVector3(0.105,0.10,0.10),cream)
            ball(elbow,SCNVector3(-side*0.075,-0.20,0.045),SCNVector3(0.050,0.062,0.045),cream)
        }
    }
    private func makeLegs() {
        for (leg,knee,foot,side) in [(leftLeg,leftKnee,leftFoot,-1.0),(rightLeg,rightKnee,rightFoot,1.0)] {
            root.addChildNode(leg); leg.position = SCNVector3(side*0.18,0.57,0)
            ball(leg,SCNVector3(0,-0.10,0),SCNVector3(0.115,0.15,0.115),cream)
            leg.addChildNode(knee); knee.position = SCNVector3(0,-0.20,0)
            ball(knee,SCNVector3(0,-0.075,0),SCNVector3(0.088,0.13,0.09),cream)
            knee.addChildNode(foot); foot.position = SCNVector3(0,-0.21,0.04)
            ball(foot,SCNVector3(0,0,0.045),SCNVector3(0.155,0.115,0.24),coral)
            _ = roundedBox(foot,at: SCNVector3(0,-0.059,0.04),size: SCNVector3(0.32,0.08,0.46),radius: 0.038,material: white)
            ball(foot,SCNVector3(0,0.026,0.23),SCNVector3(0.12,0.063,0.032),white)
            for y in [0.07,0.095] {
                curve(foot,points: [SCNVector3(-0.07,y,0.14),SCNVector3(0,y+0.005,0.15),SCNVector3(0.07,y,0.14)],radius: 0.012,material: white)
            }
        }
    }
    private func makeShadow() {
        // An alpha radial texture, no visible floor, stays clean on any desktop wallpaper.
        let image = NSImage(size: NSSize(width: 256,height: 256),flipped: false) { rect in
            NSGradient(starting: NSColor(white: 0.12,alpha: 0.22),ending: .clear)?.draw(in: NSBezierPath(ovalIn: rect),relativeCenterPosition: .zero)
            return true
        }
        let material = SCNMaterial(); material.lightingModel = .constant; material.diffuse.contents = image
        material.isDoubleSided = true; material.writesToDepthBuffer = false
        let plane = SCNPlane(width: 1.55,height: 0.95); plane.firstMaterial = material
        shadow.geometry = plane; shadow.eulerAngles.x = -.pi/2; shadow.position = SCNVector3(0,0.018,0)
        scene.rootNode.addChildNode(shadow)
    }
    private func makeLighting() {
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 1.60
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 30
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = 0.1
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.65
        camera.camera?.screenSpaceAmbientOcclusionRadius = 0.08
        camera.position = SCNVector3(0.3,2.5,7)
        camera.look(at: SCNVector3(0,1.18,0))
        scene.rootNode.addChildNode(camera)
        func light(_ type: SCNLight.LightType, _ position: SCNVector3, _ intensity: CGFloat, _ color: UInt32) {
            let node = SCNNode(); node.light = SCNLight(); node.light?.type = type
            node.light?.intensity = intensity; node.light?.color = Self.color(color)
            node.position = position; node.look(at: SCNVector3(0,1,0))
            if type == .directional { node.light?.castsShadow = false }
            scene.rootNode.addChildNode(node)
        }
        light(.ambient,SCNVector3(0,0,0),350,0xFFFFFF)
        light(.directional,SCNVector3(-3,5,5),1_050,0xFFF2DF)
        light(.directional,SCNVector3(4,2,3),450,0xD8F4FF)
        light(.directional,SCNVector3(2,4,-3),850,0xFFFFFF)
        scene.lightingEnvironment.contents = NSImage(size: NSSize(width: 32,height: 16),flipped: false) { rect in
            NSGradient(colors: [Self.color(0xF9EDD9),Self.color(0xC7E0E4)])?.draw(in: rect,angle: 90)
            return true
        }
        scene.lightingEnvironment.intensity = 0.55
    }

    func apply(_ p: DancePose, duration: Double) {
        func rotate(_ node: SCNNode, _ r: Rotation3) { node.eulerAngles = SCNVector3(r.x,r.y,r.z) }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
        root.position = SCNVector3(p.x,p.y,p.z)
        root.scale = SCNVector3(1/sqrt(p.squash),p.squash,1/sqrt(p.squash))
        rotate(torso,p.body); rotate(head,p.head)
        rotate(leftArm,p.leftArm); rotate(rightArm,p.rightArm)
        leftElbow.eulerAngles.x = CGFloat(p.leftElbow); rightElbow.eulerAngles.x = CGFloat(p.rightElbow)
        rotate(leftLeg,p.leftLeg); rotate(rightLeg,p.rightLeg)
        leftKnee.eulerAngles.x = CGFloat(p.leftKnee); rightKnee.eulerAngles.x = CGFloat(p.rightKnee)
        rotate(leftFoot,p.leftFoot); rotate(rightFoot,p.rightFoot)
        leftEar.eulerAngles.z = CGFloat(0.30+p.ear); rightEar.eulerAngles.z = CGFloat(-0.30+p.ear*0.8)
        sprout.eulerAngles.z = CGFloat(-p.ear*0.7)
        leftEye.scale.y = CGFloat(max(0.07,1-p.blink*0.95)); rightEye.scale.y = leftEye.scale.y
        leftPupil.position.x = CGFloat(0.01+p.gaze); rightPupil.position.x = CGFloat(-0.01+p.gaze)
        mouth.scale.y = CGFloat(0.32+p.smile*0.85); tongue.opacity = CGFloat(p.smile)
        shadow.scale = SCNVector3(1-p.y*0.45,1-p.y*0.45,1)
        shadow.opacity = CGFloat(1-p.y*1.3)
        SCNTransaction.commit()
    }
}
