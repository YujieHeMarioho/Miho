import AppKit
import XCTest
import MihoCore
@testable import MihoDesktop

@available(macOS 14.2, *)
private final class FakeCapture: AudioCapturing {
    var onOutputChanged: (() -> Void)?
    var starts = 0
    var stops = 0
    var disposed = false
    var gain = 0.0
    var failure: Error?
    func setSensitivity(_ value: Double) { gain = value }
    func latest() -> CaptureSnapshot { CaptureSnapshot() }
    func start(completion: @escaping (Error?) -> Void) { starts += 1; completion(failure) }
    func stop() { stops += 1 }
    func dispose() { disposed = true }
}

@available(macOS 14.2, *)
@MainActor
final class CaptureLifecycleTests: XCTestCase {
    private var preferenceSuites: [String] = []

    private func makeDefaults() -> UserDefaults {
        let name = "Miho.tests.\(UUID().uuidString)"
        preferenceSuites.append(name)
        return UserDefaults(suiteName: name)!
    }

    override func tearDown() {
        for name in preferenceSuites { UserDefaults.standard.removePersistentDomain(forName: name) }
        preferenceSuites.removeAll()
        super.tearDown()
    }

    private func makeModel(_ capture: FakeCapture) -> CompanionModel {
        CompanionModel(capture: capture, defaults: makeDefaults())
    }

    func testPermissionFailureLeavesUsableModelAndCanRetry() {
        let capture = FakeCapture()
        capture.failure = CaptureError.coreAudio("创建系统音频捕获", -1)
        let model = makeModel(capture)
        model.setEnabled(true)
        XCTAssertTrue(model.enabled)
        XCTAssertTrue(model.status.contains("权限"))
        capture.failure = nil
        model.retry()
        XCTAssertEqual(capture.starts, 2)
        XCTAssertTrue(model.status.contains("等待声音"))
        model.shutdown()
    }

    func testPauseCancelsPendingDeviceReconnect() async {
        let capture = FakeCapture()
        let model = makeModel(capture)
        model.setEnabled(true)
        capture.onOutputChanged?()
        model.setEnabled(false)
        let settled = expectation(description: "debounce elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertEqual(capture.starts, 1)
        XCTAssertEqual(capture.stops, 1)
        XCTAssertFalse(model.enabled)
        model.shutdown()
    }

    func testOutputChangesDebounceAndWakeRestartsCapture() async {
        let capture = FakeCapture()
        let model = makeModel(capture)
        model.setEnabled(true)
        capture.onOutputChanged?()
        capture.onOutputChanged?()
        let outputSettled = expectation(description: "output reconnect")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { outputSettled.fulfill() }
        await fulfillment(of: [outputSettled], timeout: 2)
        XCTAssertEqual(capture.starts, 2)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertEqual(capture.stops, 1)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        let wakeSettled = expectation(description: "wake reconnect")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { wakeSettled.fulfill() }
        await fulfillment(of: [wakeSettled], timeout: 2)
        XCTAssertEqual(capture.starts, 3)
        model.shutdown()
        XCTAssertTrue(capture.disposed)
        XCTAssertNil(capture.onOutputChanged)
    }

    func testWakeDoesNotResumeWhenPaused() async {
        let capture = FakeCapture()
        let model = makeModel(capture)
        model.setEnabled(true)
        model.setEnabled(false)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        let settled = expectation(description: "paused wake settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertEqual(capture.starts, 1)
        XCTAssertFalse(model.enabled)
        model.shutdown()
    }

    func testShutdownCancelsPendingReconnect() async {
        let capture = FakeCapture()
        let model = makeModel(capture)
        model.setEnabled(true)
        capture.onOutputChanged?()
        model.shutdown()
        let settled = expectation(description: "shutdown settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertEqual(capture.starts, 1)
        XCTAssertTrue(capture.disposed)
    }

    func testSensitivityIsRestoredAndApplied() {
        let capture = FakeCapture()
        let defaults = makeDefaults()
        defaults.set(1.7, forKey: "sensitivity")
        let model = CompanionModel(capture: capture, defaults: defaults)
        XCTAssertEqual(capture.gain, 1.7)
        model.sensitivity = 0.8
        XCTAssertEqual(capture.gain, 0.8)
        XCTAssertEqual(defaults.double(forKey: "sensitivity"), 0.8)
        model.shutdown()
    }
    func testCharacterChangesPersistAndKeepMouseRotation() {
        let defaults = makeDefaults()
        let model = CompanionModel(capture: FakeCapture(),defaults: defaults)
        XCTAssertFalse(model.autoReturnRotation)
        model.beginRotation(); model.rotate(dx: 80,dy: 0,dt: 0.1); model.endRotation()
        let rotation = model.animation.frame.rotation
        model.appearance.bodyColor = 0xF397B9
        model.appearance.accessory = .crown
        model.autoReturnRotation = true
        XCTAssertEqual(model.animation.frame.rotation,rotation)
        XCTAssertEqual(model.animation.frame.appearance.bodyColor,0xF397B9)
        let restored = CompanionModel(capture: FakeCapture(),defaults: defaults)
        XCTAssertEqual(restored.appearance,model.appearance)
        XCTAssertEqual(restored.animation.frame.appearance,model.appearance)
        XCTAssertTrue(restored.autoReturnRotation)
        model.shutdown(); restored.shutdown()
    }
    func testOrdinaryDragRoutesToRotationAndOptionDoesNot() throws {
        let model = makeModel(FakeCapture())
        defer { model.shutdown() }
        let view = DragHostingView(rootView: PetView(model: model))
        var began = 0, ended = 0, reset = 0, deltas: [Double] = []
        view.onRotationBegan = { began += 1 }; view.onRotationEnded = { ended += 1 }
        view.onRotationChanged = { dx,_,_ in deltas.append(dx) }; view.onResetRotation = { reset += 1 }
        func event(_ type: NSEvent.EventType,_ x: Double,_ flags: NSEvent.ModifierFlags = [],clicks: Int = 1) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type,location: NSPoint(x: x,y: 100),modifierFlags: flags,timestamp: x/100,windowNumber: 0,context: nil,eventNumber: 0,clickCount: clicks,pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown,50))
        view.mouseDragged(with: try event(.leftMouseDragged,80))
        view.mouseUp(with: try event(.leftMouseUp,80))
        XCTAssertEqual(began,1); XCTAssertEqual(ended,1); XCTAssertEqual(deltas,[30])
        XCTAssertFalse(view.mouseDownCanMoveWindow)
        view.mouseDown(with: try event(.leftMouseDown,50,.option))
        view.mouseDragged(with: try event(.leftMouseDragged,80,.option))
        view.mouseUp(with: try event(.leftMouseUp,80,.option))
        XCTAssertEqual(began,1); XCTAssertEqual(deltas,[30])
        view.mouseDown(with: try event(.leftMouseDown,50,clicks: 2))
        XCTAssertEqual(reset,1)
    }
}
