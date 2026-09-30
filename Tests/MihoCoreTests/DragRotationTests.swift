import XCTest
@testable import MihoCore

final class DragRotationTests: XCTestCase {
    func testViewerModeKeepsAngleAfterMomentumSettles() {
        let rotation = DragRotation(); rotation.automaticallyReturns = false
        rotation.begin(); rotation.drag(dx: 70,dy: 10,dt: 0.1); rotation.end()
        for _ in 0..<300 { rotation.update(dt: 1/60) }
        let resting = rotation.rotation
        XCTAssertGreaterThan(resting.y,1)
        for _ in 0..<300 { rotation.update(dt: 1/60) }
        XCTAssertEqual(rotation.rotation.y,resting.y,accuracy: 0.001)
        rotation.reset()
        XCTAssertEqual(rotation.rotation,Rotation3())
    }
    func testHorizontalDragTurnsRightAndSupportsFullCircle() {
        let rotation = DragRotation()
        rotation.begin()
        rotation.drag(dx: 100,dy: 0,dt: 0.1)
        XCTAssertEqual(rotation.rotation.y,1.5,accuracy: 0.0001)
        rotation.drag(dx: 400,dy: 0,dt: 0.1)
        XCTAssertGreaterThan(rotation.rotation.y,2 * .pi)
        rotation.update(dt: 0.1)
        XCTAssertEqual(rotation.rotation.y,7.5,accuracy: 0.0001)
    }
    func testVerticalTiltIsBoundedAndInvalidEventsAreIgnored() {
        let rotation = DragRotation()
        rotation.begin()
        rotation.drag(dx: 0,dy: 10_000,dt: 0)
        XCTAssertEqual(rotation.rotation.x,-0.55)
        rotation.drag(dx: .nan,dy: .infinity,dt: .nan)
        XCTAssertTrue(rotation.rotation.y.isFinite)
        rotation.drag(dx: 0,dy: -20_000,dt: 0.01)
        XCTAssertEqual(rotation.rotation.x,0.55)
    }
    func testReleaseHasInertiaThenReturnsToNearestFront() {
        let rotation = DragRotation()
        rotation.begin(); rotation.drag(dx: 60,dy: 15,dt: 0.1); rotation.end()
        let released = rotation.rotation.y
        rotation.update(dt: 1/60)
        XCTAssertGreaterThan(rotation.rotation.y,released)
        for _ in 0..<600 { rotation.update(dt: 1/60) }
        XCTAssertEqual(atan2(sin(rotation.rotation.y),cos(rotation.rotation.y)),0,accuracy: 0.005)
        XCTAssertEqual(rotation.rotation.x,0,accuracy: 0.002)
    }
    func testNewDragInterruptsSpringAndResetClearsMomentum() {
        let rotation = DragRotation()
        rotation.begin(); rotation.drag(dx: 80,dy: 10,dt: 0.1); rotation.end()
        for _ in 0..<150 { rotation.update(dt: 1/60) }
        rotation.begin()
        let held = rotation.rotation
        rotation.update(dt: 0.1)
        XCTAssertEqual(rotation.rotation,held)
        rotation.reset()
        for _ in 0..<60 { rotation.update(dt: 1/60) }
        XCTAssertEqual(rotation.rotation,Rotation3())
        XCTAssertFalse(rotation.isDragging)
    }
}
