import XCTest
import SceneKit
import MihoCore
@testable import MihoDesktop

@MainActor
final class CharacterSceneTests: XCTestCase {
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
