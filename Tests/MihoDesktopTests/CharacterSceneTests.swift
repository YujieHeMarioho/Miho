import XCTest
import SceneKit
import Metal
import MihoCore
@testable import MihoDesktop

@MainActor
final class CharacterSceneTests: XCTestCase {
    func testRenderedHaloHugsRealSilhouetteAndDifferentFrequencyBandsMakeDifferentWaves() throws {
        let rig = CharacterScene(), renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(),options: nil)
        renderer.scene = rig.scene; renderer.pointOfView = rig.camera
        let width = 180, height = 210
        func render(_ field: SoundFieldFrame) throws -> [UInt8] {
            rig.setSoundField(field); rig.apply(DancePose(),duration: 0)
            let image = renderer.snapshot(atTime: 0,with: CGSize(width: width,height: height),antialiasingMode: .multisampling4X)
            let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil,context: nil,hints: nil))
            var pixels = [UInt8](repeating: 0,count: width*height*4)
            pixels.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width*4,
                    space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
                context.draw(cg,in: CGRect(x: 0,y: 0,width: width,height: height))
            }
            return pixels
        }
        let quiet = try render(SoundFieldFrame())
        var low = SoundFieldFrame(); low.drive = 0.9; low.spectrum[1] = 0.9; low.bass = 0.8; low.transient = 0.8
        var high = low; high.spectrum[1] = 0; high.spectrum[16] = 0.9; high.bass = 0; high.transient = 0
        let bass = try render(low), treble = try render(high)
        let changed = (0..<(width*height)).filter { abs(Int(bass[$0*4+3])-Int(treble[$0*4+3])) > 8 }
        XCTAssertGreaterThan(changed.count,40,"Actual GPU output must distinguish low and high frequencies")
        var distance = (0..<(width*height)).map { quiet[$0*4+3] > 240 ? 0 : 1000 }
        for y in 0..<height { for x in 0..<width {
            let i = y*width+x
            if x > 0 { distance[i] = min(distance[i],distance[i-1]+1) }
            if y > 0 { distance[i] = min(distance[i],distance[i-width]+1) }
        }}
        for y in (0..<height).reversed() { for x in (0..<width).reversed() {
            let i = y*width+x
            if x+1 < width { distance[i] = min(distance[i],distance[i+1]+1) }
            if y+1 < height { distance[i] = min(distance[i],distance[i+width]+1) }
        }}
        let haloPixels = (0..<(width*height)).filter { quiet[$0*4+3] < 100 && Int(bass[$0*4+3])-Int(quiet[$0*4+3]) > 8 }
        XCTAssertGreaterThan(haloPixels.count,40)
        XCTAssertGreaterThan(haloPixels.filter { Int(bass[$0*4+2])-Int(bass[$0*4]) > 4 }.count,20,
                             "Low-opacity glow must retain its blue/violet tint instead of clipping to white")
        XCTAssertLessThan(haloPixels.map { distance[$0] }.max() ?? 1000,24,"Halo must remain attached to the actual mesh silhouette")
        rig.setInteractionRotation(.init(0,.pi/2,0),duration: 0)
        XCTAssertNotEqual(try render(low),bass,"Silhouette glow must rotate with real geometry")
    }

    func testAudioGrowthScalesBodyAndHeadphonesTogetherWithoutFlattening() throws {
        let rig = CharacterScene()
        let headset = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "headphones",recursively: true))
        let body = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "bodySurface",recursively: true))
        let distance = Double(headset.convertVector(SCNVector3(1,0,0),to: rig.scene.rootNode).x)
        var pose = DancePose();pose.scale = 1.18
        rig.apply(pose,duration: 0)
        XCTAssertEqual(Double(headset.convertVector(SCNVector3(1,0,0),to: rig.scene.rootNode).x),distance*1.18,accuracy: 0.001)
        let x = body.convertVector(SCNVector3(1,0,0),to: rig.scene.rootNode)
        let z = body.convertVector(SCNVector3(0,0,1),to: rig.scene.rootNode)
        XCTAssertEqual(x.x,z.z,accuracy: 0.001)
    }
    func testColorEditsReachFlattenedHeadphonesAndReuseBodyGeometry() throws {
        let rig = CharacterScene()
        let originalBody = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "bodySurface",recursively: true)?.geometry)
        var look = CharacterAppearance(); look.bodyColor = 0xF397B9; look.accessoryColor = 0xFF0000
        rig.setAppearance(look)
        let body = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "bodySurface",recursively: true)?.geometry)
        XCTAssertTrue(originalBody === body)
        let pink = try XCTUnwrap((body.firstMaterial?.diffuse.contents as? NSColor)?.usingColorSpace(.sRGB))
        XCTAssertEqual(pink.redComponent,243.0/255,accuracy: 0.001)
        let headset = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "headphones",recursively: true)?.geometry)
        XCTAssertTrue(headset.materials.contains { material in
            guard let color = (material.diffuse.contents as? NSColor)?.usingColorSpace(.sRGB) else { return false }
            return color.redComponent > 0.99 && color.greenComponent < 0.01 && color.blueComponent < 0.01
        })
    }
    func testSphereIsDeepAndSmoothWithoutSubpixelFurMeshes() throws {
        let rig = CharacterScene()
        let body = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "bodySurface",recursively: true))
        let sphere = try XCTUnwrap(body.geometry as? SCNSphere)
        XCTAssertEqual(body.scale.x,body.scale.y,accuracy: 0.001)
        XCTAssertEqual(body.scale.y,body.scale.z,accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(sphere.segmentCount,96)
        XCTAssertEqual(body.parent?.childNodes.count,1)
    }
    func testCustomChoicesRebuildGeometryWithoutResettingRotation() throws {
        let rig = CharacterScene()
        rig.setInteractionRotation(.init(0,.pi/2,0),duration: 0)
        var look = CharacterAppearance()
        for shape in BodyShape.allCases {
            look.shape = shape; rig.setAppearance(look)
            XCTAssertNotNil(rig.scene.rootNode.childNode(withName: "bodySurface",recursively: true)?.geometry)
        }
        for eyes in EyeStyle.allCases { look.eyes = eyes; rig.setAppearance(look) }
        for ears in EarStyle.allCases { look.ears = ears; rig.setAppearance(look) }
        for glasses in GlassesStyle.allCases {
            look.glasses = glasses; rig.setAppearance(look)
            let node = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "glasses",recursively: true))
            XCTAssertEqual(node.isHidden,glasses == .none)
            XCTAssertEqual(node.childNodes.isEmpty,glasses == .none)
        }
        for accessory in HeadAccessory.allCases {
            look.accessory = accessory; rig.setAppearance(look)
            XCTAssertEqual(rig.scene.rootNode.childNode(withName: "headphones",recursively: true)?.isHidden,accessory != .headphones)
        }
        let pivot = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "interactionRotation",recursively: true))
        let facing = pivot.convertVector(SCNVector3(0,0,1),to: rig.scene.rootNode)
        XCTAssertEqual(facing.x,1,accuracy: 0.001)
    }
    func testDanceUpdatesDoNotOverwriteMouseRotation() throws {
        let rig = CharacterScene()
        let pivot = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "interactionRotation",recursively: true))
        rig.setInteractionRotation(.init(0,.pi/2,0),duration: 0)
        var dance = DancePose(); dance.body = .init(0.1,-0.2,0.15)
        rig.apply(dance,duration: 0)
        let facing = pivot.convertVector(SCNVector3(0,0,1),to: rig.scene.rootNode)
        XCTAssertEqual(facing.x,1,accuracy: 0.001)
        XCTAssertEqual(facing.z,0,accuracy: 0.001)
        rig.apply(DancePose(),duration: 0)
        let stillFacing = pivot.convertVector(SCNVector3(0,0,1),to: rig.scene.rootNode)
        XCTAssertEqual(stillFacing.x,1,accuracy: 0.001)
        XCTAssertEqual(stillFacing.z,0,accuracy: 0.001)
    }

    func testFlattenedHeadsetStaysAroundBodyInsteadOfFloatingAboveIt() throws {
        let rig = CharacterScene()
        let headset = try XCTUnwrap(rig.scene.rootNode.childNode(withName: "headphones",recursively: true))
        let bounds = headset.boundingBox
        let low = headset.convertPosition(bounds.min,to: rig.scene.rootNode)
        let high = headset.convertPosition(bounds.max,to: rig.scene.rootNode)
        XCTAssertLessThan(low.y,0.75)
        XCTAssertGreaterThan(high.y,1.9)
        XCTAssertLessThan(high.y,2.10)
        XCTAssertGreaterThan(high.x-low.x,2.1)
    }
}
