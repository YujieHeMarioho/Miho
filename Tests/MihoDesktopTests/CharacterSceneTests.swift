import XCTest
import SceneKit
@testable import MihoDesktop

@MainActor
final class CharacterSceneTests: XCTestCase {
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
