import AppKit
import XCTest
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
    private func makeModel(_ capture: FakeCapture) -> CompanionModel {
        let defaults = UserDefaults(suiteName: "Miho.tests.\(UUID().uuidString)")!
        return CompanionModel(capture: capture, defaults: defaults)
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

    func testSensitivityIsRestoredAndApplied() {
        let capture = FakeCapture()
        let defaults = UserDefaults(suiteName: "Miho.tests.\(UUID().uuidString)")!
        defaults.set(1.7, forKey: "sensitivity")
        let model = CompanionModel(capture: capture, defaults: defaults)
        XCTAssertEqual(capture.gain, 1.7)
        model.sensitivity = 0.8
        XCTAssertEqual(capture.gain, 0.8)
        XCTAssertEqual(defaults.double(forKey: "sensitivity"), 0.8)
        model.shutdown()
    }
}
